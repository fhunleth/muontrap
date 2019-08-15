#include <err.h>
#include <errno.h>
#include <getopt.h>
#include <grp.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifdef DEBUG
static FILE *debug_fp = NULL;
#define INFO(MSG, ...) do { fprintf(debug_fp, "%d:" MSG "\n", microsecs(), ## __VA_ARGS__); fflush(debug_fp); } while (0)
#else
#define INFO(MSG, ...) ;
#endif

// asprintf can fail, but it's so rare that it's annoying to see the checks in the code.
#define checked_asprintf(MSG, ...) do { if (asprintf(MSG, ## __VA_ARGS__) < 0) err(EXIT_FAILURE, "asprintf"); } while (0)

static struct option long_options[] = {
    {"arg0", required_argument, 0, '0'},
    {"controller", required_argument, 0, 'c'},
    {"help",     no_argument,       0, 'h'},
    {"delay-to-sigkill", required_argument, 0, 'k'},
    {"group", required_argument, 0, 'g'},
    {"set", required_argument, 0, 's'},
    {"uid", required_argument, 0, 'u'},
    {"gid", required_argument, 0, 'a'},
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
static int brutal_kill_wait_us = 1000;
static uid_t run_as_uid = 0; // 0 means don't set, since we don't support privilege escalation
static gid_t run_as_gid = 0; // 0 means don't set, since we don't support privilege escalation

static int signal_pipe[2] = { -1, -1};

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
    printf("--delay-to-sigkill,-k <microseconds>\n");
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
        warn("write(signal_pipe)");
}

void enable_signals()
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

void disable_signals()
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

        // Drop/change privilege if requested
        // See https://wiki.sei.cmu.edu/confluence/display/c/POS36-C.+Observe+correct+revocation+order+while+relinquishing+privileges
        if (run_as_gid > 0 && setgid(run_as_gid) < 0)
            err(EXIT_FAILURE, "setgid(%d)", run_as_gid);

        if (run_as_uid > 0 && setuid(run_as_uid) < 0)
            err(EXIT_FAILURE, "setuid(%d)", run_as_uid);

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
                errx(EXIT_FAILURE, "'%s' already exists. Please specify a deeper group_path or clean up the cgroup",
                     controller->group_path);
            else
                err(EXIT_FAILURE, "Couldn't create '%s'. Check permissions.", controller->group_path);
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
                err(EXIT_FAILURE, "Error writing '%s' to '%s'", var->value, setting_file);
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
            err(EXIT_FAILURE, "Can't add pid to %s", controller->procfile);
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
            warn("Error removing %s", controller->group_path);
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

static void finish_controller_init()
{
    FOREACH_CONTROLLER {
        checked_asprintf(&controller->group_path, "%s/%s/%s", CGROUP_MOUNT_PATH, controller->name, cgroup_path);
        checked_asprintf(&controller->procfile, "%s/cgroup.procs", controller->group_path);
    }
}

static void cleanup()
{
    INFO("cleaning up!");

    disable_signals();

    // If the subprocess responded to our SIGTERM, then hopefully
    // nothing exists, but if subprocesses do exist, repeatedly
    // kill them until they all go away.
    int retries = 10;
    while (retries > 0 && kill_children(SIGKILL) > 0) {
        usleep(1000);
        retries--;
    }

    if (retries == 0) {
        // Hammer the child processes as a final attempt (no waiting this time)
        retries = 10;
        while (retries > 0 && kill_children(SIGKILL) > 0) {
            retries--;
        }

        if (retries == 0)
            warnx("Failed to kill all children even after retrying!");
    }

    // Clean up our cgroup
    destroy_cgroups();

    INFO("cleanup done");
}

static void kill_child_nicely(pid_t child)
{
    // Start with SIGTERM
    int rc = kill(child, SIGTERM);
    INFO("kill -%d %d -> %d (%s)", SIGTERM, child, rc, rc < 0 ? strerror(errno) : "success");
    if (rc < 0)
        return;

    // Wait a little.
    if (brutal_kill_wait_us > 0) {
        int start = microsecs();
        int timeleft = brutal_kill_wait_us;
        INFO("Wait %d us. Time is %d", timeleft, microsecs());
        for (;;) {
            rc = usleep(timeleft);
            if (rc == 0) {
                break;
            } else {
                int reason = errno;

                // Error from usleep. Check if moot since child exited.
                if (kill(child, 0) < 0) {
                    INFO("Child %d not running any more.", child);
                    return;
                }
                if (reason == EINTR) {
                    // Try again with a possibly shorter timeout.
                    timeleft = brutal_kill_wait_us - (microsecs() - start);
                    if (timeleft <= 0)
                        break;
                } else {
                    warn("usleep");
                    break;
                }
            }
        }

        INFO("Wait complete. Time is %d", microsecs());
    }

    // Brutal kill
    rc = kill(child, SIGKILL);
    INFO("kill -%d %d -> %d (%s)", SIGKILL, child, rc, strerror(errno));
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
                    errx(EXIT_FAILURE, "Unknown group '%s'", optarg);
                run_as_gid = group->gr_gid;
            }
            if (run_as_gid == 0)
                errx(EXIT_FAILURE, "Setting the group to root or gid 0 is not allowed");
            break;
        }

        case 'c':
            current_controller = add_controller(optarg);
            break;

        case 'g':
            if (cgroup_path)
                errx(EXIT_FAILURE, "Only one cgroup group_path supported.");
            cgroup_path = optarg;
            break;

        case 'h':
            usage();
            exit(EXIT_SUCCESS);

        case 'k': // --delay-to-sigkill
            brutal_kill_wait_us = strtoul(optarg, NULL, 0);
            if (brutal_kill_wait_us > 1000000)
                errx(EXIT_FAILURE, "Delay to sending a SIGKILL must be < 1,000,000 (1 second)");
            break;

        case 's':
        {
            if (!current_controller)
                errx(EXIT_FAILURE, "Specify a cgroup controller (-c) before setting a variable");

            char *equalsign = strchr(optarg, '=');
            if (!equalsign)
                errx(EXIT_FAILURE, "No '=' found when setting a variable: '%s'", optarg);

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
                    errx(EXIT_FAILURE, "Unknown user '%s'", optarg);
                run_as_uid = passwd->pw_uid;
            }
            if (run_as_uid == 0)
                errx(EXIT_FAILURE, "Setting the user to root or uid 0 is not allowed");
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
        errx(EXIT_FAILURE, "Specify a program to run");

    if (cgroup_path == NULL && controllers)
        errx(EXIT_FAILURE, "Specify a cgroup group_path (-g)");

    if (cgroup_path && !controllers)
        errx(EXIT_FAILURE, "Specify a cgroup controller (-c) if you specify a group_path");

    finish_controller_init();

    if (pipe(signal_pipe) < 0)
        err(EXIT_FAILURE, "pipe");

    enable_signals();
    atexit(cleanup);

    create_cgroups();

    update_cgroup_settings();

    const char *program_name = argv[optind];
    if (argv0)
        argv[optind] = argv0;
    pid_t pid = fork_exec(program_name, &argv[optind]);
    struct pollfd fds[2];
    fds[0].fd = STDIN_FILENO;
    fds[0].events = POLLHUP; // POLLERR is implicit
    fds[1].fd = signal_pipe[0];
    fds[1].events = POLLIN;

    for (;;) {
        if (poll(fds, 2, -1) < 0) {
            if (errno == EINTR)
                continue;

            err(EXIT_FAILURE, "poll");
        }

        if (fds[0].revents) {
            INFO("stdin closed. cleaning up...");
            disable_signals();
            kill_child_nicely(pid);
            break;
        }
        if (fds[1].revents) {
            int signal;
            ssize_t amt = read(signal_pipe[0], &signal, sizeof(signal));
            if (amt < 0)
                err(EXIT_FAILURE, "read signal_pipe");

            switch (signal) {
            case SIGCHLD: {
                int status;
                pid_t dying_pid = wait(&status);
                if (dying_pid == pid) {
                    int exit_status = WIFEXITED(status) ? WEXITSTATUS(status) : EXIT_FAILURE;
                    INFO("main child exited. status=%d, our exit code: %d", status, exit_status);
                    exit(exit_status);
                } else {
                    INFO("something else caused sigchild: pid=%d, status=%d. our child=%d", dying_pid, status, pid);
                }
                break;
            }

            case SIGTERM:
            case SIGQUIT:
            case SIGINT:
                exit(EXIT_FAILURE);

            default:
                err(EXIT_FAILURE, "unexpected signal: %d", signal);
            }
        }
    }

    exit(EXIT_SUCCESS);
}
