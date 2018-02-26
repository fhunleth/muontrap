all:
	$(MAKE) -C src
	if [ -f test/Makefile ]; then $(MAKE) -C test; fi

clean:
	$(MAKE) -C src clean
	if [ -f test/Makefile ]; then $(MAKE) -C test clean; fi
