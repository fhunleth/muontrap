// SPDX-FileCopyrightText: 2018 Frank Hunleth
// SPDX-FileCopyrightText: 2019 Timmo Verlaan
//
// SPDX-License-Identifier: Apache-2.0

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main()
{
    fprintf(stderr, "stderr message\n");
    // Hang out long enough to satisfy the tests
    sleep(120);
    exit(0);
}
