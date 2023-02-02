// SPDX-FileCopyrightText: 2018 Frank Hunleth
//
// SPDX-License-Identifier: Apache-2.0

#include <err.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    // This test kills itself with a SIGTERM to see if
    // muontrap reports the expected exit code.
    if (kill(getpid(), SIGTERM) < 0)
        err(EXIT_FAILURE, "kill");

    // Give the OS up to a second to deliver the signal.
    sleep(1);

    errx(EXIT_FAILURE, "expected a signal");
}
