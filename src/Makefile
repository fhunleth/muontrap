# Makefile for building the muontrap port process
#
# Makefile targets:
#
# all/install   build and install
# clean         clean build products and intermediates
#
# Variables to override:
#
# MIX_COMPILE_PATH path to the build's ebin directory
# CC            C compiler. MUST be set if crosscompiling
# CFLAGS        compiler flags for compiling all C files
# LDFLAGS       linker flags for linking all binaries

PREFIX = $(MIX_COMPILE_PATH)/../priv
BUILD  = $(MIX_COMPILE_PATH)/../obj

MUONTRAP = $(PREFIX)/muontrap

LDFLAGS +=
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter
CFLAGS += -std=c99 -D_GNU_SOURCE

#CFLAGS += -DDEBUG

SRC = $(wildcard *.c)
OBJ = $(SRC:%.c=$(BUILD)/%.o)

calling_from_make:
	cd .. && mix compile

all: install

install: $(PREFIX) $(BUILD) $(MUONTRAP)

$(OBJ): Makefile

$(BUILD)/%.o: %.c
	$(CC) -c $(CFLAGS) -o $@ $<

$(MUONTRAP): $(OBJ)
	$(CC) $^ $(LDFLAGS) -o $@

$(PREFIX):
	mkdir -p $@

$(BUILD):
	mkdir -p $@

clean:
	$(RM) $(MUONTRAP) $(BUILD)/*.o

.PHONY: all clean calling_from_make install
