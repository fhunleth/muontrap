// SPDX-FileCopyrightText: 2018 Frank Hunleth
//
// SPDX-License-Identifier: Apache-2.0

#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <grp.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

// IMPORTANT:
// The FATAL* macros mirror err(3) and errx(3) which also exit. Exiting does not clean up
// the child process which defeats one of the reasons to use MuonTrap in the first place.
// Be careful to use these macros in places where the child is not running.
#ifdef DEBUG
static FILE *debug_fp = NULL;
#define INFO(MSG, ...) do { fprintf(debug_fp, "%d INFO:" MSG "\n", microsecs(), ## __VA_ARGS__); fflush(debug_fp); } while (0)
#define WARN(MSG, ...) do { fprintf(debug_fp, "%d WARN:" MSG "\n", microsecs(), ## __VA_ARGS__); fflush(debug_fp); } while (0)
#define WARNX(MSG, ...) do { fprintf(debug_fp, "%d WARN:" MSG "\n", microsecs(), ## __VA_ARGS__); fflush(debug_fp); } while (0)
#define FATAL(MSG, ...) do { fprintf(debug_fp, "%d  ERR:" MSG "\n", microsecs(), ## __VA_ARGS__); fflush(debug_fp); exit(EXIT_FAILURE); } while (0)
#define FATALX(MSG, ...) do { fprintf(debug_fp, "%d  ERR:" MSG "\n", microsecs(), ## __VA_ARGS__); fflush(debug_fp); exit(EXIT_FAILURE); } while (0)
#else
#define INFO(MSG, ...) ;
#define WARN(MSG, ...) ;
#define WARNX(MSG, ...) ;
#define FATAL(MSG, ...) do { fprintf(stderr, "MUONTRAP: " MSG "\n",  ## __VA_ARGS__); exit(EXIT_FAILURE); } while (0)
#define FATALX(MSG, ...) do { fprintf(stderr, "MUONTRAP: " MSG "\n",  ## __VA_ARGS__); exit(EXIT_FAILURE); } while (0)
#endif

// asprintf can fail, but it's so rare that it's annoying to see the checks in the code.
#define checked_asprintf(MSG, ...) do { if (asprintf(MSG, ## __VA_ARGS__) < 0) FATAL("asprintf"); } while (0)

static struct option long_options[] = {
    {"arg0", required_argument, 0, '0'},
    {"controller", required_argument, 0, 'c'},
    {"help",     no_argument,       0, 'h'},
    {"delay-to-sigkill", required_argument, 0, 'k'},
    {"group", required_argument, 0, 'g'},
    {"set", required_argument, 0, 's'},
    {"uid", required_argument, 0, 'u'},
    {"gid", required_argument, 0, 'a'},
    {"stdio-window", required_argument, 0, 'l'},
    {"capture-output", no_argument, 0, 'o'},
    {"capture-stderr", no_argument, 0, 'e'},
    {0,          0,                 0, 0 }
};

#define CGROUP_MOUNT_PATH "/sys/fs/cgroup"

struct controller_var {
    struct controller_var *next;
    const char *key;
    const char *value;
};

struct controller_info {
    const char *name;
    char *group_path;
    char *procfile;

    struct controller_var *vars;
    struct controller_info *next;
};

static struct controller_info *controllers = NULL;
static const char *cgroup_path = NULL;
static int brutal_kill_wait_ms = 500;
static uid_t run_as_uid = 0; // 0 means don't set, since we don't support privilege escalation
static gid_t run_as_gid = 0; // 0 means don't set, since we don't support privilege escalation

static int signal_pipe[2] = { -1, -1};
static int stdout_pipe[2] = { -1, -1};
static int stderr_pipe[2] = { -1, -1};

#define DEFAULT_STDIO_WINDOW 10240 // Allow up to 10 KB out to Elixir at a time
static int stdio_bytes_max = DEFAULT_STDIO_WINDOW;
static int stdio_bytes_avail = DEFAULT_STDIO_WINDOW;
static int capture_output = 0; // Don't capture output by default
static int capture_stderr = 0; // If capturing output, don't capture stderr by default

#define FOREACH_CONTROLLER for (struct controller_info *controller = controllers; controller != NULL; controller = controller->next)

static void move_pid_to_cgroups(pid_t pid);

static void usage()
{
    printf("Usage: muontrap [OPTION] -- <program> <args>\n");
    printf("\n");
    printf("Options:\n");

    printf("--arg0,-0 <arg0>\n");
    printf("--controller,-c <cgroup controller> (may be specified multiple times)\n");
    printf("--group,-g <cgroup path>\n");
    printf("--set,-s <cgroup variable>=<value>\n (may be specified multiple times)\n");
    printf("--delay-to-sigkill,-k <milliseconds>\n");
    printf("--stdio-window <bytes>\n");
    printf("--capture-output\n");
    printf("--capture-stderr\n");
    printf("--uid <uid/user> drop privilege to this uid or user\n");
    printf("--gid <gid/group> drop privilege to this gid or group\n");
    printf("-- the program to run and its arguments come after this\n");
}

static int microsecs()
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (ts.tv_sec * 1000000) + (ts.tv_nsec / 1000);
}

void sigchild_handler(int signum)
{
    if (signal_pipe[1] >= 0 &&
            write(signal_pipe[1], &signum, sizeof(signum)) < 0)
        WARN("write(signal_pipe)");
}

void enable_signal_handlers()
{
    struct sigaction sa;
    sa.sa_handler = sigchild_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;

    sigaction(SIGCHLD, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGQUIT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
}

void disable_signal_handlers()
{
    sigaction(SIGCHLD, NULL, NULL);
    sigaction(SIGINT, NULL, NULL);
    sigaction(SIGQUIT, NULL, NULL);
    sigaction(SIGTERM, NULL, NULL);
}

static int fork_exec(const char *path, char *const *argv)
{
    INFO("Running %s", path);
    for (char *const *arg = argv; *arg != NULL; arg++) {
        INFO("  arg: %s", *arg);
    }

    pid_t pid = fork();
    if (pid == 0) {
        // child

        // Move to the container
        move_pid_to_cgroups(getpid());

        if (capture_output) {
            // Replace stdout a with flow controlled versions
            if (dup2(stdout_pipe[1], STDOUT_FILENO) < 0)
                FATAL("dup2 STDOUT_FILENO");

            // If capturing stderr too, do the same thing.
            if (capture_stderr) {
                if (dup2(stderr_pipe[1], STDERR_FILENO) < 0)
                    FATAL("dup2 STDERR_FILENO");
            }
        } else {
            // Not capturing stdout, so send it to /dev/null to get it dropped with as little processing as possible
            int dev_null_fd = open("/dev/null", O_WRONLY);
            if (dev_null_fd < 0)
                FATAL("Can't open /dev/null");

            if (dup2(dev_null_fd, STDOUT_FILENO) < 0)
                FATAL("dup2 STDOUT_FILENO");

            // If not capturing output at all, but the user says to capture
            // stderr, send stderr to /dev/null as well. As odd as this sounds
            // here, it's due to the `:stderr_to_stdout` option mapping to
            // `capture_stderr`.
            if (capture_stderr) {
                if (dup2(dev_null_fd, STDERR_FILENO) < 0)
                    FATAL("dup2 STDERR_FILENO");
            }

            close(dev_null_fd);
        }

        // Drop/change privilege if requested
        // See https://wiki.sei.cmu.edu/confluence/display/c/POS36-C.+Observe+correct+revocation+order+while+relinquishing+privileges
        if (run_as_gid > 0 && setgid(run_as_gid) < 0)
            FATAL("setgid(%d)", run_as_gid);

        if (run_as_uid > 0 && setuid(run_as_uid) < 0)
            FATAL("setuid(%d)", run_as_uid);

        execvp(path, argv);

        // Not supposed to reach here.
        exit(EXIT_FAILURE);
    } else {

        return pid;
    }
}

static int mkdir_p(const char *abspath, int start_index)
{
    int rc = 0;
    int last_errno = 0;
    char *group_path = strdup(abspath);
    for (int i = start_index; ; i++) {
        if (group_path[i] == '/' || group_path[i] == 0) {
            char save = group_path[i];
            group_path[i] = 0;
            rc = mkdir(group_path, 0755);
            if (rc < 0)
                last_errno = errno;

            group_path[i] = save;
            if (save == 0)
                break;
        }
    }
    free(group_path);

    // Return the last call to mkdir since that's the one that matters
    // and earlier directories are likely already created.
    errno = last_errno;
    return rc;
}

static void create_cgroups()
{
    FOREACH_CONTROLLER {
        int start_index = strlen(CGROUP_MOUNT_PATH) + 1 + strlen(controller->name) + 1;
        INFO("Create cgroup: mkdir -p %s", controller->group_path);
        if (mkdir_p(controller->group_path, start_index) < 0) {
            if (errno == EEXIST)
                FATALX("'%s' already exists. Please specify a deeper group_path or clean up the cgroup",
                     controller->group_path);
            else
                FATAL("Couldn't create '%s'. Check permissions.", controller->group_path);
        }
    }
}

static int write_file(const char *group_path, const char *value)
{
   FILE *fp = fopen(group_path, "w");
   if (!fp)
       return -1;

   int rc = fwrite(value, 1, strlen(value), fp);
   fclose(fp);
   return rc;
}

static void update_cgroup_settings()
{
    FOREACH_CONTROLLER {
        for (struct controller_var *var = controller->vars;
             var != NULL;
             var = var->next) {
            char *setting_file;
            checked_asprintf(&setting_file, "%s/%s", controller->group_path, var->key);
            if (write_file(setting_file, var->value) < 0)
                FATAL("Error writing '%s' to '%s'", var->value, setting_file);
            free(setting_file);
        }
    }
}

static void move_pid_to_cgroups(pid_t pid)
{
    FOREACH_CONTROLLER {
        FILE *fp = fopen(controller->procfile, "w");
        if (fp == NULL ||
            fprintf(fp, "%d", pid) < 0)
            FATAL("Can't add pid to %s", controller->procfile);
        fclose(fp);
    }
}

static void destroy_cgroups()
{
    FOREACH_CONTROLLER {
        // Only remove the final directory, since we don't keep track of
        // what we actually create.
        INFO("rmdir %s", controller->group_path);
        if (rmdir(controller->group_path) < 0) {
            INFO("Error removing %s (%s)", controller->group_path, strerror(errno));
            WARN("Error removing %s", controller->group_path);
        }
    }
}

static int procfile_killall(const char *group_path, int sig)
{
    int children_killed = 0;

    FILE *fp = fopen(group_path, "r");
    if (!fp)
        return children_killed;

    int pid;
    while (fscanf(fp, "%d", &pid) == 1) {
        INFO("  kill -%d %d", sig, pid);
        kill(pid, sig);
        children_killed++;
    }
    fclose(fp);
    return children_killed;
}

static int kill_children(int sig)
{
    int children_killed = 0;
    FOREACH_CONTROLLER {
        INFO("killall -%d from %s", sig, controller->procfile);
        children_killed += procfile_killall(controller->procfile, sig);
    }
    return children_killed;
}

#ifdef DEBUG
static void read_proc_cmdline(int pid, char *cmdline)
{
    char *cmdline_filename;

    checked_asprintf(&cmdline_filename, "/proc/%d/cmdline", pid);
    FILE *fp = fopen(cmdline_filename, "r");
    if (fp) {
        size_t len = fread(cmdline, 1, 128, fp);
        if (len > 0)
            cmdline[len] = 0;
        else
            strcpy(cmdline, "<NULL>");
        fclose(fp);
    } else {
        sprintf(cmdline, "Error reading %s", cmdline_filename);
    }

    free(cmdline_filename);
}

static void procfile_dump_children(const char *group_path)
{
    INFO("---Begin child list for %s", group_path);
    FILE *fp = fopen(group_path, "r");
    if (!fp) {
        INFO("Error reading child list!");
        return;
    }

    int pid;
    while (fscanf(fp, "%d", &pid) == 1) {
        char cmdline[129];
        read_proc_cmdline(pid, cmdline);
        INFO("  %d: %s", pid, cmdline);
    }
    fclose(fp);
    INFO("---End child list for %s", group_path);
}

static void dump_all_children_from_cgroups()
{
    FOREACH_CONTROLLER {
        procfile_dump_children(controller->procfile);
    }
}
#endif

static void finish_controller_init()
{
    FOREACH_CONTROLLER {
        checked_asprintf(&controller->group_path, "%s/%s/%s", CGROUP_MOUNT_PATH, controller->name, cgroup_path);
        checked_asprintf(&controller->procfile, "%s/cgroup.procs", controller->group_path);
    }
}

static int wait_for_sigchld(pid_t pid_to_match, int timeout_ms)
{
    struct pollfd fds[1];
    fds[0].fd = signal_pipe[0];
    fds[0].events = POLLIN;

    int end_timeout_us = microsecs() + (1000 * timeout_ms);
    int next_time_to_wait_ms = timeout_ms;
    do {
        INFO("poll - %d ms", next_time_to_wait_ms);
        if (poll(fds, 1, next_time_to_wait_ms) < 0) {
            if (errno == EINTR)
                continue;

            WARN("poll");
            return -1;
        }

        if (fds[0].revents) {
            int signal;
            ssize_t amt = read(signal_pipe[0], &signal, sizeof(signal));
            if (amt < 0) {
                WARN("read signal_pipe");
                return -1;
            }

            INFO("signal_pipe - SIGNAL %d", signal);
            switch (signal) {
            case SIGCHLD: {
                int status;
                pid_t pid = wait(&status);
                if (pid_to_match == pid) {
                    INFO("cleaned up matching pid %d.", pid);
                    return 0;
                }
                INFO("cleaned up pid %d.", pid);
                break;
            }

            case SIGTERM:
            case SIGQUIT:
            case SIGINT:
                return -1;

            default:
                WARNX("unexpected signal: %d", signal);
                return -1;
            }
        }

        next_time_to_wait_ms = (end_timeout_us - microsecs()) / 1000;
    } while (next_time_to_wait_ms > 0);

    INFO("timed out waiting for pid %d", pid_to_match);
    return -1;
}

static void cleanup_all_children()
{
    // In order to cleanup the cgroup, all processes need to exit.
    // The immediate child of muontrap will have either exited
    // at this point, so any other processes are orphaned descendents.
    // I.e., Their parent is now PID 1 and we won't get a SIGCHLD when
    // they die. We only know who they are since they're in the cgroup.

    // Send every child a SIGKILL
    int children_left = kill_children(SIGKILL);
    if (children_left > 0) {
        INFO("Found %d pids and sent them a SIGKILL", children_left);
        // poll to see if the cleanup is done every 1 ms
        int poll_intervals = brutal_kill_wait_ms / 1;
        do {
            usleep(1000);

            // Check for children and send SIGKILLs again. This
            // handles the race where we a new process was spawned
            // when we iterated through the pids the previous time.
            children_left = kill_children(SIGKILL);
            INFO("%d pids are still around", children_left);
            poll_intervals--;
        } while (poll_intervals && children_left);

        if (children_left > 0) {
            WARNX("Failed to kill %d pids!", children_left);
#ifdef DEBUG
            dump_all_children_from_cgroups();
#endif
        }
    }
}

static void kill_child_nicely(pid_t child)
{
    // Start with SIGTERM
    int rc = kill(child, SIGTERM);
    INFO("kill -%d %d -> %d (%s)", SIGTERM, child, rc, rc < 0 ? strerror(errno) : "success");
    if (rc < 0)
        return;

    // Wait a little for the child to exit
    if (wait_for_sigchld(child, brutal_kill_wait_ms) < 0) {
        // Child didn't exit, so SIGKILL it.
        rc = kill(child, SIGKILL);
        INFO("kill -%d %d -> %d (%s)", SIGKILL, child, rc, rc < 0 ? strerror(errno) : "success");
        if (rc < 0)
            return;

        if (wait_for_sigchld(child, brutal_kill_wait_ms) < 0)
            WARNX("SIGKILL didn't work on %d", child);
    }
}

static struct controller_info *add_controller(const char *name)
{
    // If the controller exists, don't add it twice.
    for (struct controller_info *c = controllers; c != NULL; c = c->next) {
        if (strcmp(name, c->name) == 0)
            return c;
    }

    struct controller_info *new_controller = malloc(sizeof(struct controller_info));
    new_controller->name = name;
    new_controller->group_path = NULL;
    new_controller->vars = NULL;
    new_controller->next = controllers;
    controllers = new_controller;

    return new_controller;
}

static void add_controller_setting(struct controller_info *controller, const char *key, const char *value)
{
    struct controller_var *new_var = malloc(sizeof(struct controller_var));
    new_var->key = key;
    new_var->value = value;
    new_var->next = controller->vars;
    controller->vars = new_var;
}

#if defined(__linux__)
static int process_stdio(int from_fd)
{
    ssize_t written;
    if (stdio_bytes_avail <= 0)
        return 0;

retry:
    written = splice(from_fd, NULL, STDOUT_FILENO, NULL, stdio_bytes_avail, SPLICE_F_MOVE);
    if (written < 0) {
        if (errno == EINTR)
            goto retry;

        WARN("failed to splice stdio (%d bytes)", stdio_bytes_avail);
        return -1;
    }
    stdio_bytes_avail -= written;
    return 0;
}
#else
static int process_stdio(int from_fd)
{
    if (stdio_bytes_avail <= 0)
        return 0;

    size_t max_to_read = stdio_bytes_avail > 4096 ? 4096 : stdio_bytes_avail;
    char buff[max_to_read];
    ssize_t got = read(from_fd, buff, max_to_read);

    if (got > 0) {
        for (ssize_t i = 0; i < got;) {
            ssize_t written = write(STDOUT_FILENO, &buff[i], got - i);

            if (written <= 0) {
                if (errno == EINTR)
                    continue;

                WARN("failed to copy stdio");
                return -1;
            }
            stdio_bytes_avail -= written;
            i += written;
        }
    }
    return 0;
}
#endif

static int child_wait_loop(pid_t child_pid, int *still_running)
{
    struct pollfd fds[4];
    fds[0].fd = STDIN_FILENO;
    fds[0].events = POLLIN | POLLHUP; // POLLERR is implicit
    fds[1].fd = signal_pipe[0];
    fds[1].events = POLLIN;
    fds[2].fd = stdout_pipe[0];
    fds[2].events = POLLIN;
    fds[3].fd = stderr_pipe[0];
    fds[3].events = POLLIN;
    int poll_num = 2;

    for (;;) {
        poll_num = 2;
        // Also poll stdout and optionally stderr when capturing output and accepting stdio data
        if (capture_output && stdio_bytes_avail > 0) {
            poll_num++;

            if (capture_stderr)
                poll_num++;
        }

        if (poll(fds, poll_num, -1) < 0) {
            if (errno == EINTR)
                continue;

            WARN("poll");
            return EXIT_FAILURE;
        }

        if (fds[0].revents & POLLHUP) {
            // Erlang signals that it's done by closing stdin. Exit immediately.
            INFO("stdin closed. Exiting...");
            return EXIT_FAILURE;
        }

        if (fds[0].revents & POLLIN) {
            uint8_t acknowledgments[32];
            ssize_t amt = read(STDIN_FILENO, acknowledgments, sizeof(acknowledgments));
            if (amt < 0) {
                INFO("read STDIN_FILENO");
                return EXIT_FAILURE;
            }

            // More than one acknowledgment may have come in, so process them all.
            // NOTE: each ack is 1+its_value
            int total_acks = amt;
            for (ssize_t i = 0; i < amt; i++)
                total_acks += acknowledgments[i];

            stdio_bytes_avail += total_acks;
            if (stdio_bytes_avail > stdio_bytes_max) {
                WARNX("Too many acks %d/%d, got %d", (int) stdio_bytes_avail, (int) stdio_bytes_max, total_acks);
                return EXIT_FAILURE;
            }
        }

        if (poll_num > 2 && fds[2].revents) {
            if (process_stdio(fds[2].fd) < 0)
                return EXIT_FAILURE;
        }

        if (poll_num > 3 && fds[3].revents) {
            if (process_stdio(fds[3].fd) < 0)
                return EXIT_FAILURE;
        }

        if (fds[1].revents) {
            int signal;
            ssize_t amt = read(signal_pipe[0], &signal, sizeof(signal));
            if (amt < 0) {
                WARN("read signal_pipe");
                return EXIT_FAILURE;
            }

            switch (signal) {
            case SIGCHLD: {
                int status;
                pid_t dying_pid = wait(&status);
                if (dying_pid == child_pid) {
                    // Let the caller know that the child isn't running and has been cleaned up
                    *still_running = 0;

                    int exit_status;
                    if (WIFSIGNALED(status)) {
                        // Crash on signal, return the signal in the exit status. See POSIX:
                        // http://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_08_02
                        exit_status = 128 + WTERMSIG(status);
                        INFO("child terminated via signal %d. our exit status: %d", status, exit_status);
                    } else if (WIFEXITED(status)) {
                        exit_status = WEXITSTATUS(status);
                        INFO("child exited with exit status: %d", exit_status);
                    } else {
                        INFO("child terminated with unexpected status: %d", status);
                        exit_status = EXIT_FAILURE;
                    }
                    return exit_status;
                } else {
                    INFO("something else caused sigchild: pid=%d, status=%d. our child=%d", dying_pid, status, child_pid);
                }
                break;
            }

            case SIGTERM:
            case SIGQUIT:
            case SIGINT:
                return EXIT_FAILURE;

            default:
                WARNX("unexpected signal: %d", signal);
                return EXIT_FAILURE;
            }
        }
    }
}

int main(int argc, char *argv[])
{
#ifdef DEBUG
    char filename[64];
    sprintf(filename, "muontrap-%d.log", getpid());
    debug_fp = fopen(filename, "w");
    if (!debug_fp)
        debug_fp = stderr;
#endif
    INFO("muontrap argc=%d", argc);
    if (argc == 1) {
        usage();
        exit(EXIT_FAILURE);
    }

    int opt;
    char *argv0 = NULL;
    struct controller_info *current_controller = NULL;
    while ((opt = getopt_long(argc, argv, "a:c:g:hk:s:0:", long_options, NULL)) != -1) {
        switch (opt) {
        case 'a': // --gid
        {
            char *endptr;
            run_as_gid = strtoul(optarg, &endptr, 0);
            if (*endptr != '\0') {
                struct group *group = getgrnam(optarg);
                if (!group)
                    FATALX("Unknown group '%s'", optarg);
                run_as_gid = group->gr_gid;
            }
            if (run_as_gid == 0)
                FATALX("Setting the group to root or gid 0 is not allowed");
            break;
        }

        case 'c':
            current_controller = add_controller(optarg);
            break;

        case 'g':
            if (cgroup_path)
                FATALX("Only one cgroup group_path supported.");
            cgroup_path = optarg;
            break;

        case 'h':
            usage();
            exit(EXIT_SUCCESS);

        case 'k': // --delay-to-sigkill
            brutal_kill_wait_ms = strtoul(optarg, NULL, 0);
            break;

        case 'l': // --stdio-window
            stdio_bytes_max = strtol(optarg, NULL, 0);
            if (stdio_bytes_max < 16)
                stdio_bytes_max = 16;

            stdio_bytes_avail = stdio_bytes_max;
            break;

        case 'o': // --capture-output
            capture_output = 1;
            break;

        case 'e': // --capture-stderr
            capture_stderr = 1;
            break;

        case 's':
        {
            if (!current_controller)
                FATALX("Specify a cgroup controller (-c) before setting a variable");

            char *equalsign = strchr(optarg, '=');
            if (!equalsign)
                FATALX("No '=' found when setting a variable: '%s'", optarg);

            // NULL terminate the key. We can do this since we're already modifying
            // the arguments by using getopt.
            *equalsign = '\0';
            add_controller_setting(current_controller, optarg, equalsign + 1);
            break;
        }

        case 'u': // --uid
        {
            char *endptr;
            run_as_uid = strtoul(optarg, &endptr, 0);
            if (*endptr != '\0') {
                struct passwd *passwd = getpwnam(optarg);
                if (!passwd)
                    FATALX("Unknown user '%s'", optarg);
                run_as_uid = passwd->pw_uid;
            }
            if (run_as_uid == 0)
                FATALX("Setting the user to root or uid 0 is not allowed");
            break;
        }

        case '0': // --argv0
            argv0 = optarg;
            break;

        default:
            usage();
            exit(EXIT_FAILURE);
        }
    }

    if (argc == optind)
        FATALX("Specify a program to run");

    if (cgroup_path == NULL && controllers)
        FATALX("Specify a cgroup group_path (-g)");

    if (cgroup_path && !controllers)
        FATALX("Specify a cgroup controller (-c) if you specify a group_path");

    finish_controller_init();

    // Finished processing commandline. Initialize and run child.

    if (pipe(signal_pipe) < 0)
        FATAL("pipe");
    if (fcntl(signal_pipe[0], F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(signal_pipe[1], F_SETFD, FD_CLOEXEC) < 0)
        WARN("fcntl(FD_CLOEXEC)");

    if (capture_output) {
        if (pipe(stdout_pipe) < 0)
            FATAL("pipe");
        if (fcntl(stdout_pipe[0], F_SETFD, FD_CLOEXEC) < 0 ||
            fcntl(stdout_pipe[1], F_SETFD, FD_CLOEXEC) < 0)
            WARN("fcntl(FD_CLOEXEC)");

        if (capture_stderr) {
            if (pipe(stderr_pipe) < 0)
                FATAL("pipe");
            if (fcntl(stderr_pipe[0], F_SETFD, FD_CLOEXEC) < 0 ||
                fcntl(stderr_pipe[1], F_SETFD, FD_CLOEXEC) < 0)
                WARN("fcntl(FD_CLOEXEC)");
        }
    }

    enable_signal_handlers();

    create_cgroups();

    update_cgroup_settings();

    const char *program_name = argv[optind];
    if (argv0)
        argv[optind] = argv0;
    pid_t pid = fork_exec(program_name, &argv[optind]);

    int still_running = 1;
    int exit_status = child_wait_loop(pid, &still_running);

    if (still_running) {
        // Kill our immediate child if it's still running
        kill_child_nicely(pid);
    }

    // Cleanup all descendents if using cgroups
    cleanup_all_children();

    destroy_cgroups();
    disable_signal_handlers();

    exit(exit_status);
}
