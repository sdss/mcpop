SHELL = /bin/sh
#
# Expected variables on the command line:
# CC=        The name of the appropriate compiler, with suitable flags
# CCCHK=     A set of compiler flags which check ANSI C strictly
# LLIBS=     A set of libraries for linking against.
#
# N.b. This may be needed to override sdssmake's opinion that we should be building 32 bit;
# at least on hub25m the 32-bit compiler is broken (and tcl/tk are build 64-bit anyway)

ARCH = -m64

.c.o :
	$(CC) -c $(CCCHK) $(CFLAGS) -DCHECK_LEAKS $(ARCH) $*.c
#

BIN	= ../bin
INCDIRS	= -I../include \
          -I$(TK_DIR)/include -I$(TK_DIR)/src \
	  -I$(TCLDP_DIR)/include \
          -I$(TCL_DIR)/include -I$(TCL_DIR)/src \
	  -I$(PLC_DIR)/include -I$(PLC_DIR)/src

CFLAGS  = $(SDSS_CFLAGS) $(INCDIRS) 
CFLAGS_DEFGP  = $(SDSS_CFLAGS_DEFGP) $(INCDIRS) 
#
#
#
OBJECTS = main.o mcp_sockets.o tclMcp.o

LDFLAGS = -L$(TK_DIR)/lib -ltk -L$(TCL_DIR)/lib -ltcl -L$(TK_DIR)/lib -ltk -L$(TCLDP_DIR)/lib -ldpnetwork \
	$(LLIBS) $(ARCH)

#=============================================================================
# TARGETS
#=============================================================================

default:	
	@echo Please invoke this makefile using sdssmake. >&2
	@exit 1

all: $(BIN)/iop
	@echo ""
#
# main program.
#
$(BIN)/iop : $(OBJECTS)
	$(CC) -o $@ $(OBJECTS) $(LDFLAGS)

install:
	@if [ "$(MCPOP_DIR)" = "" ]; then \
		echo You have not specified a destination directory >&2; \
		exit 1; \
	fi
	-@/bin/rm -rf $(MCPOP_DIR)/src
	@mkdir        $(MCPOP_DIR)/src
	@chmod 775    $(MCPOP_DIR)/src
	- cp *.c      $(MCPOP_DIR)/src
	- cp Makefile      $(MCPOP_DIR)/src
	- chmod 444   $(MCPOP_DIR)/src/*.c

clean :
	rm -f *~ *.o core *.bak *.orig *.old .#* #*#
#
make :
	@if [ "$(CCENV)" = "" ]; then ccenv=`uname`; else ccenv=$(CCENV); fi; \
	echo \
	"make_make -cc '$(CC) $(CFLAGS)' -nostd -file Makefile" \
							"-env $$ccenv *.c"; \
	make_make -cc '$(CC) $(CFLAGS)' -nostd -file Makefile -env $$ccenv *.c
#
# include file dependencies.
#
# All line below START_DEPEND are machine generated; Do Not Edit
#
#START_DEPEND
