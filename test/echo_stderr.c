#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main()
{
    fprintf(stderr, "stderr message\n");
    sleep(1000000);
    exit(0);
}
