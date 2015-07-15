SHELL = /bin/sh

# Edit-Time-stamp: <97/01/23 12:30:28 bakken>

default:
	@echo Please invoke this makefile using sdssmake. >&2
	@exit 1

all:	;

install:
	@if [ "$(MCPOP_DIR)" = "" ]; then \
		echo You have not specified a destination directory >&2; \
		exit 1; \
	fi
	-@/bin/rm -rf $(MCPOP_DIR)/ups
	@mkdir        $(MCPOP_DIR)/ups
	@cp Makefile  $(MCPOP_DIR)/ups
	for f in *.table; do \
		eups expandtable -w $$f $(MCPOP_DIR)/ups; \
	done

clean:
	- /bin/rm -fr *~ .*~ core *.bak *.orig *.old .\#* \#*\#
