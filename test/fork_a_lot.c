// SPDX-FileCopyrightText: 2018 Frank Hunleth
//
// SPDX-License-Identifier: Apache-2.0

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>

// Fork a tree of children and print out the pids

static void do_fork(int left)
{
    if (left == 0)
        return;

    for (int i = 0; i < 2; i++) {
        pid_t pid = fork();
        if (pid == 0) {
            // Child
            do_fork(left - 1);
            // Hang out long enough to satisfy the tests
            sleep(120);
        }
        printf("%d\n", pid);
        fflush(stdout);
    }

}
int main(int argc, char **argv)
{
    // Fork a tree of children.
    // 4 -> this pid + 2 children + 4 grandchildren + 8 great-grandchildren, etc.
    // for a total of 2^(4+1) - 1 processes
    do_fork(4);

    // parent
    sleep(120);
    exit(0);
}
