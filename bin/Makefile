SHELL = /bin/sh

PROGS_MADE = iop

default:
	@echo Please invoke this makefile using sdssmake. >&2
	@exit 1

all:	;

install:
	@if [ "$(MCPOP_DIR)" = "" ]; then \
		echo You have not specified a destination directory >&2; \
		exit 1; \
	fi
	-@/bin/rm -rf $(MCPOP_DIR)/bin
	@ umask 002; mkdir $(MCPOP_DIR)/bin
	for i in *; do   \
		if [ -f $$i ]; then \
			cp $$i $(MCPOP_DIR)/bin ; \
			chmod 555 $(MCPOP_DIR)/bin/$$i; \
		fi;\
	done

clean:
	- /bin/rm -f *~ .*~ core *.bak *.orig *.old $(PROGS_MADE) .\#* \#*\#

