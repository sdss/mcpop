#
# Remove the toplevel window until we want it
#
if {![info exists initialised]} {
   set initialised 1
   catch {				# we may not have access to tk
      wm withdraw .
   }
}

mcpOpen
while {![array exists mcpData]} {
   array set mcpData [mcpReadPacket]
}

source $env(MCPOP_DIR)/etc/utils.tcl
source $env(MCPOP_DIR)/etc/afterUtilities.tcl
source $env(PLC_DIR)/etc/interlockStartup.tcl

set dt 1
startInterlocks "" $dt
