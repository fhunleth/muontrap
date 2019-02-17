calling_from_make:
	mix compile

all:
	$(MAKE) -C src all
	if [ -f test/Makefile ]; then $(MAKE) -C test; fi

clean:
	$(MAKE) -C src clean
	if [ -f test/Makefile ]; then $(MAKE) -C test clean; fi

.PHONY: all clean calling_from_make
