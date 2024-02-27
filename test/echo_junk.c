// SPDX-FileCopyrightText: 2018 Frank Hunleth
//
// SPDX-License-Identifier: Apache-2.0

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main()
{
    const char junk[] = {253, 245, 116, 105, 238, 103, 33, 99, 235, 229, 124, 121, 255, 229, 10};

    fwrite(junk, sizeof(junk), 1, stdout);
    fflush(stdout);

    // Hang out long enough to satisfy the tests
    sleep(200);
    exit(0);
}
