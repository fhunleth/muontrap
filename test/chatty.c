// SPDX-FileCopyrightText: 2018 Frank Hunleth
// SPDX-FileCopyrightText: 2023 Ben Youngblood
//
// SPDX-License-Identifier: Apache-2.0

#include <stdio.h>

int main(void)
{
  /* Make standard output unbuffered. */
  setvbuf(stdout, (char *)NULL, _IONBF, 0);

  while (1)
    printf("Hello, world!\n");

  return 0;
}
