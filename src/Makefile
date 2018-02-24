# Variables to override
#
# CC            C compiler
# CROSSCOMPILE	crosscompiler prefix, if any
# CFLAGS	compiler flags for compiling all C files
# LDFLAGS	linker flags for linking all binaries

LDFLAGS +=
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter
CFLAGS += -std=c99 -D_GNU_SOURCE

#CFLAGS += -DDEBUG

SRC=$(wildcard *.c)
OBJ=$(SRC:.c=.o)

.PHONY: all clean

all: ../priv ../priv/muontrap

%.o: %.c
	$(CC) -c $(CFLAGS) -o $@ $<

../priv:
	mkdir ../priv

../priv/muontrap: $(OBJ)
	$(CC) $^ $(LDFLAGS) -o $@

clean:
	rm -f ../priv/muontrap *.o
	-rmdir ../priv
