# Makefile for building the muontrap port process
#
# Makefile targets:
#
# all/install   build and install
# clean         clean build products and intermediates
#
# Variables to override:
#
# MIX_APP_PATH  path to the build directory
# CC            C compiler. MUST be set if crosscompiling
# CFLAGS        compiler flags for compiling all C files
# LDFLAGS       linker flags for linking all binaries

PREFIX = $(MIX_APP_PATH)/priv
BUILD  = $(MIX_APP_PATH)/obj

MUONTRAP = $(PREFIX)/muontrap

LDFLAGS +=
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter
# _GNU_SOURCE is needed for splice(2) on Linux
CFLAGS += -std=c99 -D_GNU_SOURCE -Wno-empty-body

#CFLAGS += -DDEBUG

SRC = $(wildcard *.c)
OBJ = $(SRC:%.c=$(BUILD)/%.o)

calling_from_make:
	cd .. && mix compile

all: install

install: $(PREFIX) $(BUILD) $(MUONTRAP)

$(OBJ): Makefile

$(BUILD)/%.o: %.c
	@echo " CC $(notdir $@)"
	$(CC) -c $(CFLAGS) -o $@ $<

$(MUONTRAP): $(OBJ)
	@echo " LD $(notdir $@)"
	$(CC) $^ $(LDFLAGS) -o $@

$(PREFIX) $(BUILD):
	mkdir -p $@

clean:
	$(RM) $(MUONTRAP) $(BUILD)/*.o

.PHONY: all clean calling_from_make install

# Don't echo commands unless the caller exports "V=1"
${V}.SILENT:
