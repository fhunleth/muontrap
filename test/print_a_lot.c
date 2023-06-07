// SPDX-FileCopyrightText: 2018 Frank Hunleth
//
// SPDX-License-Identifier: Apache-2.0

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main()
{
    int i;
    for (i = 0; i < 1000; i++) {
        printf("%d-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n", i);
    }
    fflush(stdout);

    // Sleep a little since muontrap doesn't wait for all output to be consumed
    sleep(1);
    exit(0);
}
