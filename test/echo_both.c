// SPDX-FileCopyrightText: 2024 Frank Hunleth
//
// SPDX-License-Identifier: Apache-2.0

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main()
{
    fprintf(stdout, "stdout message\n");
    fflush(stdout);
    fprintf(stderr, "stderr message\n");
    fflush(stderr);

    // Hang out long enough to satisfy the tests
    sleep(120);
    exit(0);
}
