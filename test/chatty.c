// SPDX-FileCopyrightText: 2018 Frank Hunleth
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
