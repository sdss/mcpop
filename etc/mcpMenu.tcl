#
# Remove the toplevel window until we want it
#
if {![info exists initialised]} {
   set initialised 1
   catch {				# we may not have access to tk
      wm withdraw .
   }
}

source $env(MCPOP_DIR)/etc/utils.tcl
source $env(MCPOP_DIR)/etc/mcp.tcl
source $env(MCPOP_DIR)/etc/afterUtilities.tcl
source $env(PLC_DIR)/etc/documentation.tcl; # for PLC version
source $env(PLC_DIR)/etc/interlockStartup.tcl

start_mcpMenu
exit 0
