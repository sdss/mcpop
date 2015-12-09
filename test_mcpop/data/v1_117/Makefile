SHELL = /bin/sh

all :;

# Here's my (CPL's) understanding of what's going on:
#   The mcp_fiducials CVS module is just the mcp module's fiducial-tables subdir
#   We are the Makefile in that module or subdir.
#   If we are the module, we want to be able to install ourselves, but only when
#   installing a new ups version.
#   If we are the mcp product subdir, we never, ever, ever want to install ourselves
#   over the mcp_fiducials files. And there is no real need to install our files at all.
#
# Basically, fiducial tables are no longer meaningful as part of the
# mcp product. The only way they are changed is via new versions of the mcp_fiducials
# product.
#
install : all
	@if [ X$(MCP_FIDUCIALS_DIR) != X"" ]; then \
	    if [ ! -d $(MCP_FIDUCIALS_DIR) ]; then \
		mkdir $(MCP_FIDUCIALS_DIR); \
		cp Makefile alt.dat az.dat rot.dat $(MCP_FIDUCIALS_DIR); \
		cp -r ups $(MCP_FIDUCIALS_DIR); \
	    else \
		echo NOT copying fiducial files into the existing $(MCP_FIDUCIALS_DIR); \
	    fi; \
	else \
	    echo NOT copying files into $(MCP_DIR)/fiducial-tables; \
	fi

clean :
	- rm -f *.o core *~
