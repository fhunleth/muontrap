calling_from_make:
	mix compile

all:
	$(MAKE) -C c_src all
	if [ -f test/Makefile ]; then $(MAKE) -C test; fi

clean:
	$(MAKE) -C c_src clean
	if [ -f test/Makefile ]; then $(MAKE) -C test clean; fi

.PHONY: all clean calling_from_make

.SILENT:
