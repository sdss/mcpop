SHELL = /bin/sh

default:
	@echo Please invoke this makefile using sdssmake. >&2
	@exit 1

all:

install: 
	@if [ "$(MCPOP_DIR)" = "" ]; then \
		echo You have not specified a destination directory >&2; \
		exit 1; \
	fi
	-@/bin/rm -rf $(MCPOP_DIR)/etc
	@ umask 002; mkdir $(MCPOP_DIR)/etc
	 umask 222; cp Makefile *.tcl $(MCPOP_DIR)/etc

clean:
	- /bin/rm -f *~ .*~ core *.bak *.orig *.old .\#* \#*\#
