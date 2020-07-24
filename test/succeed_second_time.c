#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int read_counter(const char *filename)
{
    FILE *fp = fopen(filename, "r");
    if (!fp)
        return 0;

    int counter;
    if (fscanf(fp, "%d", &counter) != 1)
        counter = 0;
    fclose(fp);
    return counter;
}

static void write_counter(const char *filename, int counter)
{
    FILE *fp = fopen(filename, "w");
    fprintf(fp, "%d\n", counter);
    fclose(fp);
}

int main(int argc, char **argv)
{
    if (argc != 2)
        errx(EXIT_FAILURE, "Pass a filename");

    int counter = read_counter(argv[1]);
    printf("Called %d times\n", counter);
    write_counter(argv[1], counter + 1);

    // Only exit successful on the second call.
    if (counter == 1)
        exit(EXIT_SUCCESS);
    else
        exit(EXIT_FAILURE);
}
