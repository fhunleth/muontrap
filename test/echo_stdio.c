// SPDX-FileCopyrightText: 2018 Frank Hunleth
//
// SPDX-License-Identifier: Apache-2.0

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main()
{
    // Messages are different lengths on purpose to help debug.
    // stderr is dots to make it less ugly when it prints to the console, but
    // I'll probably forget and regret it.
    fprintf(stdout, "stdout here\n");
    fprintf(stderr, "....");
    fflush(stdout);

    // Hang out long enough to satisfy the tests
    sleep(200);
    exit(0);
}
