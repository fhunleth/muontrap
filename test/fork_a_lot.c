#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    for (int i = 0; i < 100; i++) {
        pid_t pid = fork();
        if (pid == 0) {
            // Child
            sleep(1000000);
        }
    }

    // parent
    sleep(1000000);
    exit(0);
}
