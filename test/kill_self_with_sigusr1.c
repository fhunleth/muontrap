// SPDX-FileCopyrightText: 2018 Frank Hunleth
// SPDX-FileCopyrightText: 2023 Eric Rauer
//
// SPDX-License-Identifier: Apache-2.0

#include <err.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    // This test kills itself with a SIGUSR1 to see if
    // muontrap reports the expected exit code.
    if (kill(getpid(), SIGUSR1) < 0)
        err(EXIT_FAILURE, "kill");

    // Give the OS up to a second to deliver the signal.
    sleep(1);

    errx(EXIT_FAILURE, "expected a signal");
}

