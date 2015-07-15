SHELL = /bin/sh

# This is the top level Makefile for MCPOP: MCP Observering [sic] Program

#=============================================================================

DIRS = bin doc etc src ups 

default:
	@echo Please invoke this makefile using sdssmake. >&2
	@exit 1

all:
	@echo "Updating all directories"
	@echo ""
	@ for f in $(DIRS); do \
		(cd $$f ; echo In $$f; 	$(MAKE) $(MFLAGS) all ); \
	done

iop :
	@(cd src; $(MAKE) $(MFLAGS) all)

install:
	@echo ""
	@echo "Make sure the current MCPOP directories under"
	@echo ""
	@echo "     `pwd`"
	@echo ""
	@echo "have the latest versions of the files.  These will be copied to the"
	@echo "the destination during the install of MCPOP."
	@echo ""
	@if [ "$(MCPOP_DIR)" = "" ]; then \
		echo "The destination directory has not been specified.  Set the environment"   >&2; \
		echo "variable MCPOP_DIR"                                                         >&2; \
		echo ""; \
		exit 1; \
	fi
	@if [ ! -d $(MCPOP_DIR) ]; then \
		echo $(MCPOP_DIR) "doesn't exist; making it"; \
		mkdir $(MCPOP_DIR); \
	fi
	@:
	@: Check the inode number for . and $(MCPOP_DIR) to find out if two
	@: directories are the same\; they may have different names due to
	@: symbolic links and automounters
	@:
	@if [ `ls -id $(MCPOP_DIR) | awk '{print $$1}'` = \
				`ls -id . | awk '{print $$1}'` ]; then \
		echo "The destination directory is the same as the current directory."          >&2; \
		echo "Aborting the installation." >&2; \
		echo ""; \
		exit 1; \
	fi

	@echo "You will be installing in"
	@echo ""
	@echo "   MCPOP_DIR = $(MCPOP_DIR)"
	@echo ""
#	@echo "running $(CVSCHECK)..."
#	@ if $(CVSCHECK); then \
#		echo > /dev/null ; \
#	else \
#	 	echo "This product did not passed the cvs check."; \
#		echo "Please correct the above error before installing."; \
##		exit 1; \
#	fi
	@echo "I'll give you 5 seconds to think about it (control-C to abort) ..."
	@for pos in          5 4 3 2 1; do \
	   echo "                              " | sed -e 's/ /'$$pos'/'$$pos; \
	   sleep 1; \
	done
	@echo "... and we're off... deleting"
	-@/bin/rm -rf $(MCPOP_DIR)
	@mkdir $(MCPOP_DIR)
	@cp Makefile $(MCPOP_DIR)
	@for f in $(DIRS); do \
		(mkdir $(MCPOP_DIR)/$$f; cd $$f; echo In $$f; $(MAKE) install ); \
	done
	@chmod -R g+w $(MCPOP_DIR)

make:
	@for f in src; do \
		(cd $$f ; echo In $$f; $(MAKE) make ); \
	done

clean:
	@echo In .
	- /bin/rm -f *~ .*~ *.bak *.orig *.old a.out .\#* \#*\#
	@for f in $(DIRS); do \
			(cd $$f ; echo In $$f; $(MAKE) clean); \
	done

