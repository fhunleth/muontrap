#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

void ignore_signal(int signum)
{
    // Sleeping will keep this process from exiting
    sleep(1000000);
}

int main(int argc, char **argv)
{
    struct sigaction sa;
    sa.sa_handler = ignore_signal;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;

    sigaction(SIGTERM, &sa, NULL);
    sleep(1000000);
    exit(0);
}
