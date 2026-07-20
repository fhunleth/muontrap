// SPDX-FileCopyrightText: 2026 David Calvo
//
// SPDX-License-Identifier: Apache-2.0

#include <stdio.h>
#include <stdlib.h>

int main()
{
    int i;
    for (i = 0; i < 1000; i++) {
        printf("%d-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n", i);
    }
    fflush(stdout);

    // Exit immediately since the :epipe regression test needs
    // acknowledgments to still be in flight
    exit(0);
}
