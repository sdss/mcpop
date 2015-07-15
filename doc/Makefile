SHELL = /bin/sh

.SUFFIXES:
.SUFFIXES: .ps .tex .fig

.tex.ps:
	-latex $< < /dev/null
	@-dvips -o $@ $*.dvi
	@/bin/rm -f $*.aux $*.dvi $*.log



C2HTML     = $(SDSSTOOLS_DIR)/bin/c2html
HTML2LATEX = $(SDSSTOOLS_DIR)/bin/html2latex

TEX =

default:
	@echo Please invoke this makefile using sdssmake. >&2
	@exit 1

all: $(TEX) $(FIG)

install:
	@if [ "$(MCPOP_DIR)" = "" ]; then \
		echo You have not specified a destination directory >&2; \
		exit 1; \
	fi
	-@/bin/rm -rf $(MCPOP_DIR)/doc
	-@mkdir       $(MCPOP_DIR)/doc
	-@chmod 775   $(MCPOP_DIR)/doc

clean:
	- /bin/rm -fr *~ .*~ core *.bak *.orig *.old .\#* \#*\#
	- /bin/rm -fr *.log *.toc *.aux $(FIG) *.dvi
