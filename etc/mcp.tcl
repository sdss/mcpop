lappend mcpHelp_procs mcpIack

proc mcpIack {args} {
   set opts [list \
		 [list [info level 0] "Acknowledge an MCP reboot"] \
		]
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   mcpPut "IACK"

   global iack_button menuColors
   catch {				# we may not be running Tk
      if [winfo exists $iack_button] {
	 $iack_button configure -fg $menuColors(background)
      }
   }
}

alias miack mcpIack


proc mcpHandler {} {
   global mcpData mcpError mcpTol keydisplays BAD_POLARITY shutters_are_open

   resetErrorArray mcpError
   
   if {![info exists mcpData(serialNum)]} {
      set mcpData(serialNum) 0
   }
   incr mcpData(serialNum)

   readMCPValues

   set mcpError(timeStamp) $mcpData(ctime)
   incr mcpError(serialNum)
   
   if {[getclock] - $mcpData(ctime) > $mcpTol(timeout)} {
      set mcpError(timeout) [utclock $mcpData(ctime)]
   }

   if ![regexp {[ais]d[1-6]} [busyNodes]] {# no busy non-mt nodes,
      					# so we don't care about the MCP
      return
   }
   if {[info exists shutters_are_open] && !$shutters_are_open} {
      return;				# not exposing; ignore MCP
   }
   
   foreach type "alt az rot" {
      if [bad_axis_state $type] {
	 global msg_axis_state

	 switch $type {
	    "alt" {
	       set axis_select "altitude"
	    }
	    "az" {
	       set axis_select "azimuth"
	    }
	    "rot" {
	       set axis_select "rotator"
	    }
	 }
	 set mcpError($axis_select) $msg_axis_state($mcpData(${type}state))
      }
   }
}

###############################################################################
#
# Reset the MCP crate
#
lappend mcpHelp_procs mcpResetCrate

alias mcpPowerCycle mcpResetCrate

proc mcpResetCrate {args} {
   global cameraLatNode cameraPortNum

   set soft 0; set hard 0; set medium 0

   set opts [list \
		 [list [info level 0] "Reset the MCP/TPM crate"] \
		 [list -soft CONSTANT 1 soft \
		      "Soft reset; just reset MCP board (default)"] \
		 [list -hard CONSTANT 1 hard \
		      "Hard reset; reset entire MCP crate"] \
		 [list -medium CONSTANT 1 medium \
		      "Software hard reset; reset entire MCP crate"] \
		]
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   if {$soft + $hard + $medium == 0} {
      set soft 1
   }

   if {$soft + $hard + $medium != 1} {
      error "Please speciy only one type of reset at a time"
   }
   #
   # Is some sort of software reboot desired?
   #
   if $soft {
      catch {mcpPut SYS.RESET 0}
      return
   } elseif $medium {
      catch {mcpPut SYS.RESET 1}
      return
   }
   #
   # OK, hard.  Use a relay to init the crate
   #
   set latNode $cameraLatNode(mcp_reset)
   set portNum $cameraPortNum(mcp_reset)
   
   set retryDelay 1500000;		# microseconds
   set cameraConnectTime 100000;	# same as imager/spectro
   set tries 2
   
   set power [ftelnet $cameraConnectTime $retryDelay $tries $latNode $portNum]

   puts -nonewline "Engaging reset relay"
   puts $power "!11";			# turn power on to relay
   loop i 0 5 {
      puts -nonewline "."
      after 100
   }
   puts "\nReleasing relay"
   puts $power "!10";			# turn relay on
   
   close $power
}

###############################################################################
#
# Code to talk to the MCP telnet server
#
lappend mcpHelp_procs mcpServerPort

proc mcpServerPort {args} {
   set opts [list \
		 [list [info level 0] "Return mcp server port number"] \
		 {{[port]} INTEGER 31011 port "Port to use"}\
		]
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   return $port
}

#
# Connect to the command server process on the MCP
#
proc mcpServerConnect {args} {
   global mcpCommandPort

   set opts [list \
		 [list [info level 0] "Return mcp server port number"] \
		 [list {[port]} INTEGER [mcpServerPort] port "Port to use"]\
		 [list {[host]} STRING "sdssmcp" host "Host to connect to"]\
		]
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   if [info exists mcpCommandPort] {	# already open
      return
   }

   if [catch {
      set mcpCommandPort [lindex [dp_connect_safe $host $port] 0]
   } msg] {
      return -code error -errorinfo $msg $msg
   }

   set return [string trimright [dp_receive $mcpCommandPort]]

   if {[lindex $return 1] == "refused:"} {
      close $mcpCommandPort; unset mcpCommandPort
      error $return;
   }

   get_mcp_plc_versions

   if [catch {
      mcpPut USER.ID [whoami]@[exec uname -n] [pid]
   } msg] {
      echo "MCP version doesn't support USER.ID; continuing"
   }

   dp_atexit appendUnique "close $mcpCommandPort"

   return $mcpCommandPort
}

proc mcpServerDisconnect {args} {
   global mcpCommandPort

   set opts [list \
		 [list [info level 0] "Return mcp server port number"] \
		 [list {[port]} INTEGER [mcpServerPort] port "Port to use"]\
		 [list {[host]} STRING "sdssmcp" host "Host to connect to"]\
		]
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   if ![info exists mcpCommandPort] {	# already open
      return
   }

   catch {close $mcpCommandPort; unset mcpCommandPort}
}

###############################################################################
#
# Send a command to the MCP, and return the response
#
lappend mcpHelp_procs mcpPut

proc mcpPut {args} {
   global mcpCommandPort

   set opts [list \
		 [list [info level 0] "Send a command to the MCP"] \
		]
   if {$args == "" || [regexp {^-h(e(l(p)?)?)?} [lindex $args 0]]} {
      if {[shTclParseArg $args $opts [info level 0]] == 0} {
	 return ""
      }
   }

   global verbose; if $verbose {
      echo mcpPut: $args
   }

   if ![info exists mcpCommandPort] {
      if [catch {
	 mcpServerConnect
      } msg] {
	 echo "RHL err $msg"
	 return ""
      }
   }

   if [catch {
      while {[select $mcpCommandPort {} {} 0] != ""} {
	 dp_receive $mcpCommandPort;	# flush old responses
      }
   } msg] {
      echo "Error in select mcpCommandPort: $msg"
      catch {close $mcpCommandPort}; unset mcpCommandPort
      return ""
   }

   if [catch {
      if {[select {} $mcpCommandPort {} 1] == ""} {
	 return "";			# timed out
      }
      puts $mcpCommandPort [join $args]
   } msg] {
      if [regexp {Connection reset by peer|Broken pipe} $msg] {
	 catch {close $mcpCommandPort}; unset mcpCommandPort
      }
      error $msg
   }

   if {[select $mcpCommandPort {} {} 5] == ""} {
      return "";			# timed out
   }
   if [catch {
      set reply [dp_receive $mcpCommandPort]
   } msg] {
      if [regexp {Connection reset by peer|Broken pipe} $msg] {
	 catch {close $mcpCommandPort; unset mcpCommandPort}
      }
      error $msg
   }

   if ![regexp {(.*) *ok\n?} $reply foo reply] {
      echo "error reading reply from MCP: [string trimright $reply]"
   }

   return [string trimright $reply]
}

###############################################################################

proc get_mcp_plc_versions {} {
   global mcpVersion plcVersion fiducialsVersion
   global fiducialsVersion_button plcVersion_button menuColors

   if [catch {set mcpVersion "MCP: [mcpVersion]"}] {
      set mcpVersion "MCP: ???"
   }
   
#jrh
   if [ catch { set plcVersion "PLC: [lindex [mcpSystemStatus -misc] 1]" } ] {
      set plcVersion "PLC: ???"
   }

#   if [catch {set plcVersion "PLC: [plcVersion]"}] {
#      set plcVersion "PLC: ???"
#   }

   if [regexp {\?\?\?|MISMATCH|NOTAG} $plcVersion] {
      set fg $menuColors(iack)
   } else {
      set fg $menuColors(foreground)
   }

   catch {				# we may not be running Tk
      if [winfo exists $plcVersion_button] {
	 $plcVersion_button configure -fg $fg
      }
   }
   #
   # Now the fiducials
   #
   
   # jrh
   if [ catch {set _fiducialsVersion [lindex [mcpSystemStatus -misc] 2]}] {
      set _fiducialsVersion "???"
   }

   #if [catch {set _fiducialsVersion [fiducialsVersion]}] {
   #   set _fiducialsVersion "???"
   #}
   
   if [regexp {(^\?\?\?|MISMATCH:|NOTAG|blank|NOCVS|undefined|[^:]+:[^:]+:[^:]+|[^|]+\|[^|]+\|[^|]+)$} $_fiducialsVersion] {
      set fg $menuColors(iack)
   } else {
      set fg $menuColors(foreground)
   }

   set fiducialsVersion "Fiducials: $_fiducialsVersion"
   catch {				# we may not be running Tk
      if [winfo exists $fiducialsVersion_button] {
	 $fiducialsVersion_button configure -fg $fg
      }
   }
}

###############################################################################

lappend mcpHelp_procs mcpVersion

proc mcpVersion {args} {
   global tccData

   set close 0
   set opts [list \
		 [list [info level 0] "Return MCP version number"] \
		 {-close CONSTANT 1 close "Close port after reading version"}\
		 ]
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }
   
   set name [mcpPut "version"]

   if ![regexp \
	   {mcpVersion=".Name: ([^ ]*) *\$([^"]*)} $name foo mcpVersion rest] {
      set mcpVersion "(unavailable)"
   } elseif {$mcpVersion == ""} {
      set mcpVersion "NOCVS$rest"
   }

   if $close {
      global mcpCommandPort
      catch {
	 close $mcpCommandPort
	 unset mcpCommandPort
      }
   }

   return $mcpVersion
}

###############################################################################

lappend mcpHelp_procs plcVersion

proc plcVersion {args} {
   global interlockDescriptions

   set opts [list \
		 [list [info level 0] "Return PLC version"] \
		 ]
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }
   
   set version [lindex [mcpSystemStatus -misc] 1]

  if {![regexp {Version ([^ ]+) +} \
	     $interlockDescriptions(version_id) {} plc_n]} {
      return "NOCVS:$version:$plc_n"
   } elseif {$version == ""} {
      return "(unavailable)"
   } elseif {$version == $plc_n} {	# version from PLC matches version in
      ;					# interlockDescriptions (i.e. sdss.csv)
      return $plc_n;
   } else {
      return "MISMATCH:$version:$plc_n"
   }
}


lappend mcpHelp_procs fiducialsVersion

proc fiducialsVersion {args} {
   set fullpath 0
   set opts [list \
		 [list [info level 0] "Return MPC_FIDUCIALS version"] \
		 [list -fullpath CONSTANT 1 fullpath \
		      "Return full path of fiducials file"] \
		 ]
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   set dir [lrange [exec ls -l /p/mcpbase/fiducial-tables] end end]

   if $fullpath {
      return $dir
   }
   
   set version [file tail $dir]
   if {$version == "fiducial-tables"} {
      set version "mcp:[file tail [file dirname $dir]]"
   } 

   if {$version == [mcpFiducialsVersion]} {
      return $version
   } else {
      return "MISMATCH:$version:[mcpFiducialsVersion]"
   }
}

lappend mcpHelp_procs mcpFiducialsVersion

proc mcpFiducialsVersion {args} {
   set opts \
       [list \
	    [list [info level 0] "Return the MCP's idea of the fiducial table version"] \
	   ]
   
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   return [lindex [mcpSystemStatus -misc] 2]
}

###############################################################################

lappend mcpHelp_procs mcpAxisStatus

proc mcpAxisStatus {args} {
   set opts \
       [list \
	    [list [info level 0] ""] \
	    {<axis> STRING "" axis "The axis whose status is desired"} \
	   ]
   
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }
   
   #
   # Send command to MCP
   #
   loop i 0 10 {			# command may fail
      set vals [mcpPut $axis AXIS.STATUS]
      
      if {[lindex $vals 0] != "ERR:"} {
	 break
      }

      catch {
	 after 10
      }
   }
   
   if [regexp {I don't have} $vals] {
      set $vals ""
   }
   
   return $vals
}

###############################################################################

lappend mcpHelp_procs mcpSystemStatus

proc mcpSystemStatus {args} {
   global tccData

   set types "cw ffs ff hgcd ne uv wht spec1 spec2 align inst misc instID"
   foreach t $types {
      set ${t}_st 0
      if [info exists all_st] {
	 append all_st "+"
      }
      append all_st " \$${t}_st"
   }
   set return_permit 0

   set opts [list \
	       [list [info level 0] \
 "Return status of mcp systems (e.g. spectro lamps); if no type is specified all
 available information is returned. The last value for each type of object
 is the mcp permit for that system.

 If only one system's status is requested it's returned as a list,
 otherwise a keyed list is returned.
 "] \
		 [list -perm CONSTANT 1 return_permit \
		      "Return the subsystem's permit as an extra element of list"] \
		 [list -cw CONSTANT 1 cw_st \
		      "Return counterweight positions/limit (U or L)"] \
		 [list -ff CONSTANT 1 ff_st \
		      "Return Flatfield lamp status (0: off)"] \
		 [list -hgcd CONSTANT 1 hgcd_st \
		      "Return HgCdlamp status (0: off)"] \
		 [list -ne CONSTANT 1 ne_st \
		      "Return Ne lamp status (0: off)"] \
		 [list -uv CONSTANT 1 uv_st \
		      "Return UV  lamp status (0: off)"] \
		 [list -wht CONSTANT 1 wht_st \
		      "Return white lamp status (0: off)"] \
		 [list -ffs CONSTANT 1 ffs_st \
		      "Return flat field screen status (0: open)"] \
		 [list -spec1 CONSTANT 1 spec1_st \
		      "Return spec1 status: (opn cls latch_opn in_place)"] \
		 [list -spec2 CONSTANT 1 spec2_st \
		      "Return spec2 status: (opn cls latch_opn in_place)"] \
		 [list -align CONSTANT 1 align_st \
		      "Return alignment clamp status: (ext ret)"] \
		 [list -inst CONSTANT 1 inst_st \
		      "Return instrument status: (saddle instID)"] \
		 [list -instID CONSTANT 1 instID_st \
		      "Return instrument ID: (instID)"] \
		 [list -misc CONSTANT 1 misc_st \
		      "Return misc status: (iacked plc_version)"] \
		]
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }
   #
   # Send status command to MCP
   #
   loop i 0 10 {			# command may fail
      set status [mcpPut "SYSTEM.STATUS"]
      
      if {[lindex $status 0] != "ERR:"} {
	 break
      }

      catch {
	 after 10
      }
   }

   parse_system_status $status \
       cw ffs ff ne hgcd uv wht spec1 spec2 align inst misc
   set instID [lindex $inst 1]
   #
   # There are no uv/wht status bits, so fake them from the permit
   #
   foreach v "uv wht" {
      set perm [lindex [set $v] end]
      set $v [list $perm $perm $perm $perm  $perm]
   }
   #
   # Pop off the word which tells us which petals are enabled,
   # and set the ffs_n_enab variables
   #   
   set which_ffs [lrange $ffs end end]
   set ffs [lrange $ffs 0 [expr [llength $ffs] - 2]]

   foreach n "1 2" {
      global ffs_${n}_enab
      set ffs_${n}_enab [expr ($which_ffs & $n) ? 1 : 0]
   }

   if !$return_permit {
      foreach v "ffs ff ne hgcd uv wht" {
	 set $v [lrange [set $v] 0 [expr [llength [set $v]] - 2]]
      }
   }
   
   if 1 {
      regsub -all {00} [join $ffs] -1 ffs;
      regsub -all {11} [join $ffs] -2 ffs;
      regsub -all {01} [join $ffs] 1 ffs;
      regsub -all {10} [join $ffs] 0 ffs;
   }

   set nstat [eval expr $all_st];	# how many flags were set
   
   if {$nstat == 0} {
      foreach t $types {
	 set ${t}_st 1
	 incr nstat
      }
   }

   if {$nstat == 1} {
      foreach t $types {
	 if [set ${t}_st] {
	    set res [set $t]
	    break;
	 }
      }
   } else {
      foreach t $types {
	 if [set ${t}_st] {
	    lappend res [list $t [set $t]]
	 }
      }
   }

   return $res
}

#
# Parse the reply from SYSTEM.STATUS
#
proc parse_system_status {status \
			      _cw _ffs _ff _ne _hgcd _uv _wht \
			      _spec1 _spec2 _align _inst _misc} {
   #
   # Variables to get from SYSTEM.STATUS, and their keys (we apologise
   # for the lack of uniformity in these keys)
   #
   set vars [list cw ffs ff ne hgcd uv wht spec1 spec2 misc  inst]
   set keys [list CW FFS FF Ne HgCd UV WHT SP1:  SP2:  Misc: Inst: END]
   #
   # Figure out how to parse status if we don't already know
   #
   set len [llength $status]

   global system_status_offsets
   if {$len > 0 && (![info exists system_status_offsets(llength)] ||
       $system_status_offsets(llength) != $len)} {
      set system_status_offsets(llength) $len

      set start [expr [lsearch $status [lindex $keys 0]] + 1]
      loop i 0 [llength $vars] {
	 set k [lindex $keys [expr $i+1]]
	 set v [lindex $vars $i]
	 if {$k == "END"} {
	    set end [expr [llength $status] - 1]
	 } else {
	    set end [expr [lsearch $status $k] - 1]
	 }
	 
	 set system_status_offsets($v) [list $start $end]
	 
	 if {$end != "end"} {
	    set start [expr $end + 2]
	 }
      }
   }
   #
   # Actually parse list
   #
   foreach v $vars {
      upvar [set _$v] $v

      if {$len == 0} {			# SYSTEM.STATUS must have failed
	 if [info exists $v] {
	    unset $v
	 }
	 
	 if [info exists system_status_offsets] { # at least we know how many fields we wanted
	    loop i [lindex $system_status_offsets($v) 0] [expr [lindex $system_status_offsets($v) 1] + 1] {
	       lappend $v -999
	    }
	 } else {			# surely 20's enough?
	    loop i 0 20 {
	       lappend $v -999
	    }
	 }
      } else {
	 set $v [lrange $status \
		     [lindex $system_status_offsets($v) 0] \
		     [lindex $system_status_offsets($v) 1]]
      }
   }
   #
   # Special case the alignment clamp
   #
   upvar $_align align
   set align [lrange $misc 0 1]
   set misc [lrange $misc 2 end]

   return [expr $len > 0 ? 1 : 0]
}

###############################################################################
#
# Return the status of the given axis' brake
#
proc mcpBrakeStatus {axis} {
   set vals [mcpAxisStatus $axis]

   if {$vals == ""} {
      return -1
   }
   
   return [lindex $vals 11]
}

###############################################################################
#
# Attempt to toggle the state of the the semCmdPort semaphore that controls
# access to motion etc. MCP commands
#
# If state is specified, try to go to that state (0 => give)
#
lappend mcpHelp_procs mcpFullAccess

proc mcpFullAccess {args} {
   set force_give 0; set give 0; set steal 0; set take 0
   set toggle 0
   
   set opts [list \
		 [list [info level 0] \
 "Take/give the semCmdPort semaphore that controls access to the MCP.

 N.b.: it is not possible to steal the semaphore from a command-line iop,
 but you can take it from an mcpMenu
 "] \
		 [list {-give} CONSTANT 1 give "Give the semaphore"] \
		 [list {-forcegive} CONSTANT 1 force_give "Force giving the semaphore"] \
		 [list {-take} CONSTANT 1 take "Try to take the semaphore"] \
		 [list {-steal} CONSTANT 1 steal "Steal the semaphore"] \
		 [list {-toggle} CONSTANT 1 toggle \
		      "Toggle the semaphore's state"] \
		]
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   if {$force_give + $give + $steal + $take + $toggle != 1} {
      error "Please choose exactly one action"
   }

   global menuColors took_semCmdPort

   if ![regexp {semCmdPort=([01])} [mcpPut SEM.SHOW] foo i] {
      echo "I cannot determine who has the semCmdPort semaphore"
      set i 0
   }
   set took_semCmdPort $i

   if $toggle {
      if $took_semCmdPort {
	 set give 1
      } else {
	 set take 1
      }
   }

   if $give {
      set reply [mcpPut "SEM.GIVE"]
   } elseif $force_give {
      set reply [mcpPut "SEM.GIVE 1"]
   } elseif $take {
      set reply [mcpPut "SEM.TAKE"]
   } elseif $steal {
      set reply [mcpPut "SEM.STEAL"]
   } else {
      error "Impossible condition"
   }

   if {$reply == "took semaphore"} {
      show_semCmdPort 1
   } else {
      if $take {
	 set status_msg "Cannot get semaphore for full access to MCP"
	 if [regexp {Unable to take semaphore owner ([^:]*)} \
		 $reply foo owner] {
	    append status_msg ": owner $owner"
	 }
	 set_status_msg $status_msg

	 if {[info commands winfo] == "" || ![winfo exists .mcp_menu]} {
	    echo $status_msg
	 }
	 bell

	 return 0
      }
      show_semCmdPort 0
   }

   return 1;
}

###############################################################################
#
# Make a "menu" window; first make the required globals
#
if ![info exists ticks_per_degree] {	# just until we run AXIS.STATUS
   array set ticks_per_degree [list Rotator 1  Altitude 1  Azimuth 1]
}

if ![info exists setAxisArr] {
   array set setAxisArr [list Rotator "IR"  Altitude "TEL2"  Azimuth "TEL1"]
}

if ![info exists axis_adjposArr] {
   array set axis_adjposArr [list Rotator 0  Altitude 0  Azimuth 0]
}

if ![info exists axis_adjvelArr] {
   array set axis_adjvelArr \
       [list Rotator 100000  Altitude 100000  Azimuth 100000]
}

if ![info exists axis_adjaccArr] {
   array set axis_adjaccArr [list Rotator 45000  Altitude 25000  Azimuth 50000]
}

if ![info exists axis_velArr] {
   array set axis_velArr [list Rotator 0  Altitude 0  Azimuth 0]
}

if ![info exists axis_accLimitArr] {
   array set axis_accLimitArr [list Rotator 6.0  Altitude 0.11  Azimuth 4.0]
}

if ![info exists axis_velLimitArr] {
   array set axis_velLimitArr [list Rotator 2.25  Altitude 1.5  Azimuth 2.25]
}

if ![info exists JK_vel] {
   array set JK_vel [list Rotator 0  Altitude 0  Azimuth 0]
}

if ![info exists axis_incvelArr] {
   array set axis_incvelArr [list Rotator 1000  Altitude 1000  Azimuth 1000]
}

if ![info exists menuColors] {
   array set menuColors [list \
			     unknown yellow \
			     background black \
			     button_background slategray \
			     foreground white \
			     full_access "green" \
			     restrict_access "red" \
			     selected_axis green \
			     selected_axis_J red \
			     selected_axis_K green \
			     status yellow \
			     FF ivory \
			     HgCd cyan \
			     Ne red \
			     UV violet \
			     Wht white \
			     FFS_open white \
			     FFS_closed black \
			     iack red \
			     ]
   set menuColors(nonselected_axis) $menuColors(foreground)
}

#
# This proc is a wrapper for mcpMenu designed to be run as
#   iop -command "start_mcpMenu"
#
proc start_mcpMenu {{geom ""} {update 2} {wait 1}} {
   global exit_mcpMenu;			# exit when this is set

   if [catch { mcpMenu -geom $geom -dt $update } msg] {
      catch { destroy .mcp_menu }
      error $msg
   }

   if $wait {
      tkwait variable exit_mcpMenu
   }
}

lappend mcpHelp_procs mcpMenu

proc mcpMenu {args} {
   global menuColors mcpMenu_serialNumber

   set find_menu 0
   set opts [list \
		 [list [info level 0] "Display the MCP Menu"] \
		 {-geom STRING "" geom "X geometry string"}\
		 {-dt DOUBLE "5" dt "How often to update the axis positions"} \
		 {-find CONSTANT 1 find_menu "Find the MCP menu window"} \
		]
   
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }
   if {$dt == 0} { set dt 0.5 };	# as is done for popup

   if [winfo exists .mcp_menu] {
      if $find_menu {
	 wm deiconify .mcp_menu
	 raise .mcp_menu
	 
	 return;
      } else {
      }
      destroy .mcp_menu
   }
   set mcpMenu_serialNumber -1

   option add *Background $menuColors(background)
   option add *Foreground $menuColors(foreground)

   toplevel .mcp_menu
   wm title .mcp_menu "MCP Menu"
   if {$geom != ""} {
      wm geometry .mcp_menu $geom
   }
   pack [frame .mcp_menu.main -height 5c -width 7c]
   #
   # Reset the list used to control disableable buttons
   #
   global maybe_bindings maybe_buttons
   if [info exists maybe_bindings] {
      unset maybe_bindings
   }
   if [info exists maybe_buttons] {
      unset maybe_buttons
   }
   #
   # Start creating the menu window
   #
   set i 0
   #---------------------------------------------------------------------------
   incr i
   pack [set row [frame .mcp_menu.main.row$i]] -expand 1 -fill x
   global iack_button; set iack_button $row.iack
   global permit_button; set permit_button $row.permit

   global mcpMenu_time; set mcpMenu_time "???"
   get_mcp_plc_versions
   
   pack [label $row.axis_name -textvariable mcpVersion] \
       -side left -anchor w
   pack [label $row.sp -relief flat -width 1] \
       -side left -anchor w

   pack [label $row.iack \
	     -relief flat -text Rebooted -fg $menuColors(background)] \
       -side left -anchor w
   bind $row.iack <Button-1> "depress $iack_button; mcpIack"

   pack [button $permit_button -command "mcpFullAccess -toggle"] \
       [label $row.time -textvariable mcpMenu_time] \
       -side right -anchor e
   bind $permit_button <Button-3> \
       "set_status_msg \"Stealing authority...\"; update; mcpFullAccess -steal"

   show_semCmdPort

   #---------------------------------------------------------------------------
   incr i
   pack [set row [frame .mcp_menu.main.row$i]] -expand 1 -fill x
   global plcVersion_button; set plcVersion_button $row.plcVersion
   global fiducialsVersion_button
   set fiducialsVersion_button $row.fiducialsVersion

   pack [label $row.plcVersion -textvariable plcVersion] \
       -side left -anchor w
   pack [label $row.sp2 -relief flat -width 1] \
       -side left -anchor w

   pack [label $row.fiducialsVersion -textvariable fiducialsVersion] \
       -side left -anchor w
   pack [label $row.sp3 -relief flat -width 1] \
       -side left -anchor w

   #---------------------------------------------------------------------------
   global axisStatus

   set_status_msg ""
   schedule getMcpStatus {} $dt
   
   global la_axis_state; set la_axis_state "MSAE"
   global la_axis_pos_dms; set la_axis_pos_dms "DegMinSec"
   global la_axis_pos_act; set la_axis_pos_act "ActualPos"
   global la_axis_pos_err; set la_axis_pos_err "Error"
   global la_axis_pos_vlt; set la_axis_pos_vlt "Voltage"
   global la_axis_fid; set la_axis_fid "Fiducl"
   global la_axis_fid_pos; set la_axis_fid_pos "Position"

   foreach a "Label Azimuth Altitude Rotator" {
      incr i
      pack [set row [frame .mcp_menu.main.row$i]] -expand 1 -fill x

      switch -regexp $a {
	 {^La} { set name "" }
	 {^Az} { set name "AZ" }
	 {^Al} { set name "AL" }
	 {^Rot} { set name "ROT" }
      }
      set aname [get_aname $a]

      pack [label $row.axis_name -width 5] \
	  [label $row.axis_state -textvariable ${aname}_axis_state -width 4] \
	  [label $row.axis_pos_dms -textvariable ${aname}_axis_pos_dms \
	       -width 15] \
	  [label $row.axis_pos_act -textvariable ${aname}_axis_pos_act \
	       -anchor e -width 10] \
	  [label $row.axis_pos_err -textvariable ${aname}_axis_pos_err \
	       -anchor e -width 8] \
	  [label $row.axis_pos_vlt -textvariable ${aname}_axis_pos_vlt \
	       -anchor e -width 8] \
	  [label $row.pad -width 2] \
	  [label $row.axis_fid -textvariable ${aname}_axis_fid \
	       -anchor e -width 6 -padx 0] \
	  [label $row.axis_pos_fid -textvariable ${aname}_axis_fid_pos \
	       -anchor e -width 13] \
	  -side left -anchor w -pady 0 -padx 0 -ipadx 0

      if {$a != "Label"} {
	 global axis_label_widget; set axis_label_widget($a) $row.axis_name.cmd
	 pack [label $row.axis_name.cmd -width 3 \
		   -text $name -relief groove] -anchor w
	 bind $row.axis_name.cmd <Button-1> \
	     "depress $row.axis_name.cmd; set_active_axis $a"

	 pack propagate $row.axis_name 0
	 $row.axis_name configure -width 5
      } else {
	 $row.axis_fid configure -relief groove
	 maybe_bind $row.axis_fid "f\r"
      }
   }

   #---------------------------------------------------------------------------
   incr i
   pack [set row [frame .mcp_menu.main.row$i]] -expand 1 -fill x

   pack [label $row.clin_lab -text "Clino: "] \
       [label $row.clin_val -textvariable alt_clinometer] \
       -side left -anchor w

   global cwpos
   set cwchars [list ^ ! @ \# $]

   pack \
       [label $row.axis_name_pad -text "  "] \
       [label $row.axis_name -text "CWeights:" -relief groove] \
       -side left -anchor w
   maybe_bind $row.axis_name "[lindex $cwchars 0]\r"

   loop c 1 5 {
      if ![info exists cwpos($c)] {
	 set cwpos($c) "??"
      }
      pack \
	  [label $row.cwlab_pad$c -text " "] \
	  [label $row.cwlab$c -text [format "%d" $c] -relief groove] \
	  [label $row.cwval$c -textvariable cwpos($c)] \
	  -side left -anchor w
      maybe_bind $row.cwlab$c "[lindex $cwchars $c]\r"
   }

   pack [label $row.abort -text " abort" -relief groove] -side left
   maybe_bind $row.abort "%%"

   set umbilPos "????"
   pack [label $row.umb_pad -text "  "] \
       [label $row.umbilical -text "Inst" -relief groove] \
       [label $row.umbilicalPos -textvariable umbilPos] \
       -side left

   #---------------------------------------------------------------------------
   # Controls <-J-- ... --K->
   incr i
   pack [set row [frame .mcp_menu.main.row$i]] -expand 1 -fill x

   global axis_select axis_name axis_vel_str axis_vel_asec_str axis_incvel_str
   if ![info exists axis_select] {
      set axis_select "Rotator"
   }
   show_active_axis

   global menu_JK_widget
   set menu_JK_widget(J) $row.axis_velJ; set menu_JK_widget(K) $row.axis_velK
   pack [label $row.axis_name -textvariable axis_name] \
       [label $row.axis_velJ -text "<-J-- " -relief groove] \
       [label $row.axis_vel -textvariable axis_vel_str] \
       [label $row.axis_velK -text " --K->" -relief groove] \
       [label $row.axis_pad -text " "] \
       [label $row.axis_incvelLab -text "Increment" -relief groove] \
       [label $row.axis_incvel -textvariable axis_incvel_str] \
       [label $row.axis_vel_asecLab -text "Cts  V (asec/s) "] \
       [label $row.axis_vel_asec -textvariable axis_vel_asec_str] \
       -side left -anchor w

   bind $row.axis_velJ <Button-1> \
       "depress $row.axis_velJ; do_menu_cmd J; do_menu_cmd \"\r\""
   bind $row.axis_velK <Button-1> \
       "depress $row.axis_velK; do_menu_cmd K; do_menu_cmd \"\r\""
   bind $row.axis_incvelLab <Button-1> \
       "depress $row.axis_incvelLab; do_menu_cmd I; do_menu_cmd \"\r\""

   #---------------------------------------------------------------------------
   incr i
   pack [set row [frame .mcp_menu.main.row$i]] -expand 1 -fill x

   global axis_adjposArr
   set adjpos $axis_adjposArr($axis_select)
   set_axis_adjpos_str $adjpos
   if ![info exists axis_adjvel_str] {
      set_axis_adjvel_str 0
   }

   pack [label $row.plabel -text "Choose Destination Position" -relief groove]\
       [label $row.pos -textvariable axis_adjpos_dms] \
       [frame $row.fill] \
       [label $row.vlabel -text "Velocity" -relief groove] \
       [label $row.vel -textvariable axis_adjvel_str -width 20] \
       -side left -anchor w
   pack $row.fill -expand 1 -fill x

   bind $row.plabel <Button-1> \
       "depress $row.plabel; do_menu_cmd D; do_menu_cmd \"\r\""
   bind $row.vlabel <Button-1> \
       "depress $row.vlabel; do_menu_cmd V; do_menu_cmd \"\r\""

   #---------------------------------------------------------------------------
   #
   # Buttons to control lamps etc.
   #
   incr i
   pack [set row [frame .mcp_menu.main.row$i]] -expand 1 -fill x
   #
   # Lamps
   #
   pack [label $row.lamps -text "Lamps:"] -side left -anchor w
   foreach lamp "FF HgCd Ne UV Wht" {
      global ${lamp}_status;
      pack [checkbutton $row._$lamp -text $lamp -variable ${lamp}_status \
		-background $menuColors(button_background) \
		-selectcolor $menuColors($lamp)] \
       -side left -anchor w

      maybe_bind_button $row._$lamp "toggle_lamp $lamp"
   }
   #
   # FF screen
   #
   pack [label $row._FFS -text " FFS:"] -side left -anchor w

   global FFS_status;
   if ![info exists FFS_status] {
      set FFS_status ""
   }
   
   foreach oc "closed open" {
      pack [radiobutton $row._FFS_$oc -text $oc -value $oc \
		-variable FFS_status \
		-background $menuColors(button_background) \
		-selectcolor $menuColors(FFS_$oc)] \
	  -side left -anchor w
      
      maybe_bind_button $row._FFS_$oc \
	  "open_ffs [expr ![string compare $oc "closed"] ? 0 : 1]"
   }

   pack [label $row._FFS_ena -text " Enabled:"] -side left -anchor w
   foreach n "1 2" {
      global ffs_${n}_enab
      if ![info exists ffs_${n}_enab] { set ffs_${n}_enab 1 }

      if {$n == 1} { set text "T" } else { set text "B" }
      pack [checkbutton $row._FFS_$n -text $text -variable ffs_${n}_enab \
		-background $menuColors(button_background)] \
	  -side left -anchor w
   
      maybe_bind_button $row._FFS_$n "toggle_ffs_enable $n"
   }
   #---------------------------------------------------------------------------
   #
   # Buttons to control the spectrographs
   #
   loop sp 1 3 {
      incr i
      pack [set row [frame .mcp_menu.main.row$i]] -expand 1 -fill x

      pack [label $row.spectro$sp -text "SP$sp "] -side left -anchor w
      #
      # slithead doors
      #
      pack [label $row._Door -text " Door:"] -side left -anchor w
      
      global sp${sp}Door_status
      if ![info exists sp${sp}Door_status] {
	 set sp${sp}Door_status "unknown"
      }
      
      foreach oc "closed open" {
	 pack [radiobutton $row.sp${sp}Door_$oc -text $oc -value $oc \
		   -variable sp${sp}Door_status \
		   -background $menuColors(button_background) \
		   -selectcolor black] \
	     -side left -anchor w

	 maybe_bind_button $row.sp${sp}Door_$oc \
	     "open_spectro_door $sp [expr ![string compare $oc "closed"] ? 0 : 1]"
      }
      #
      # slithead latches
      #
      pack [label $row._Slithead -text " Slithead:"] -side left -anchor w
      
      global sp${sp}Slithead_status;
      if ![info exists sp${sp}Slithead_status] {
	 set sp${sp}Slithead_status ""
      }
      
      foreach oc "retracted extended" {
	 pack [radiobutton $row.sp${sp}Slithead_$oc -text $oc -value $oc \
		   -variable sp${sp}Slithead_status \
		   -background $menuColors(button_background) \
		   -selectcolor black] \
	     -side left -anchor w
	 
	 maybe_bind_button $row.sp${sp}Slithead_$oc \
	     "ext_slit_latch $sp [expr ![string compare $oc "extended"] ? 1 : 0]"
      }
   }

   #---------------------------------------------------------------------------
   incr i
   pack [set row [frame .mcp_menu.main.row$i]] -expand 1 -fill x

   set j 0
   foreach n [list brake clear_brake { } move { } \
		  monitor init reset_amps stop hold { } correct {  } help] {
      if [regexp {^ *$} $n] {
	 pack [label $row._[incr j] -text $n -relief flat] -side left
      } else {
	 pack [label $row.$n -text $n -relief groove] -side left
      }
   }

   maybe_bind $row.brake "b"
   maybe_bind $row.clear_brake "c\r"
   maybe_bind $row.move "m\r"
   maybe_bind $row.monitor "&\r"
   maybe_bind $row.init "y\r"
   maybe_bind $row.reset_amps "*\r"
   maybe_bind $row.stop "s"
   maybe_bind $row.hold "h"
   maybe_bind $row.correct "\003\r"
   bind $row.help <Button-1> "do_menu_cmd ?"

   activate_maybe_bind 0
   #---------------------------------------------------------------------------
   incr i
   pack [set row [frame .mcp_menu.main.row$i]] -expand 1 -fill x

   pack [label $row.axis_name -textvariable status_msg \
	     -fg $menuColors(status)] -side left -anchor w
   
   #---------------------------------------------------------------------------
   #
   # User entry row
   #
   pack [frame .mcp_menu.getString] -expand 1 -fill x
   pack [label .mcp_menu.getString.lab] -side left
   pack [label .mcp_menu.getString.val -relief groove -anchor w \
	     -textvariable getString] -side left -expand 1 -fill x
   set_getString_prompt ""
   
   #---------------------------------------------------------------------------
   #
   # Buttons
   #
   pack \
       [button .mcp_menu.interlocks \
	    -text "interlocks" -command "startInterlocks {} $dt"] \
       [button .mcp_menu.telescope \
	    -text "telescope" -command "make_telescope {} $dt"] \
       [button .mcp_menu.updates \
	    -text "updates: ? Hz" \
	    -command "mcpMenu_update_rate .mcp_menu.updates"] \
       [button .mcp_menu.activate \
	    -text "enable" -command "activate_maybe_bind"] \
       -side left
   show_update_rate .mcp_menu.updates $dt
  
   pack [frame .mcp_menu.fill] -expand 1 -fill x
   pack [button .mcp_menu.quit \
	    -text quit -command killMcpMenu] \
       -side right

   #---------------------------------------------------------------------------
   #
   # Set the variable which controls reading strings
   #
   global readString; set readString 0
   #
   # Set key bindings for a-zA-Z
   #
   set A 65;				# ascii for 'A'
   set a 97;				# ascii for 'a'
   set zero 48;				# ascii for '0'
   loop i 0 10 {
      bind .mcp_menu [format %c [expr $zero + $i]] {do_menu_cmd %A}
   }
   loop i 0 26 {
      bind .mcp_menu [format %c [expr $A + $i]] {do_menu_cmd %A}
      bind .mcp_menu [format %c [expr $a + $i]] {do_menu_cmd %A}
   }
   foreach c [list Return plus minus equal underscore parenleft parenright \
		  braceleft braceright asciitilde bar quotedbl apostrophe \
		  space grave period colon Delete BackSpace asterisk question \
		  asciicircum exclam at numbersign dollar ampersand percent \
		 ] {
      bind .mcp_menu "<$c>" {do_menu_cmd %A}
   }
   bind .mcp_menu "<Control-c>" {do_menu_cmd 3}
   bind .mcp_menu "<Control-v>" {do_menu_cmd 22}
   bind .mcp_menu "<Control-x>" {do_menu_cmd 24}
   bind .mcp_menu "<Control-p>" {do_menu_cmd PID}
      
   bind .mcp_menu <Enter> {focus .mcp_menu}
   #
   # Set the active instrument
   #
   global axis_select;

   if ![info exists axis_select] {
      set active_axis "Rotator"
   }

   set_active_axis $axis_select
   #
   # Revert to default colourmap
   #
   option add *Background [. cget -bg]
   option add *Foreground [. cget -highlightcolor]
   #
   # set the prompt/window title
   #
   promptSet "mcpMenu> "
   setWindowTitle "mcpMenu @ [exec uname -n] ([pid])"
}

proc set_status_msg {msg} {
   global status_msg status_msg_time
   
   set status_msg $msg;
   set status_msg_time [getclock]
}

proc mcpMenu_update_rate {{parent ""}} {
   if [winfo exists .set_rate] { destroy .set_rate }

   toplevel .set_rate -class transient
   wm title .set_rate "Set Update Rate"

   if {$parent != ""} {
      set x [expr int([winfo rootx $parent]+[winfo width $parent]/2)]
      set y [expr int([winfo rooty $parent]+[winfo height $parent]/2)]
      wm geometry .set_rate +$x+$y
   }
   #
   # Header
   #
   pack [frame .set_rate.top] .set_rate.top -expand 1 -fill x
   
   label .set_rate.top.label -text "Update Interval(s)"
   frame .set_rate.top.fill
   button .set_rate.top.ok -text accept \
       -command "if {\$update_rate == 0} {set update_rate 0.5}
		 schedule getMcpStatus  {} \$update_rate
	  	 destroy .set_rate
                 show_update_rate .mcp_menu.updates \$update_rate
"
   button .set_rate.top.cancel -text cancel -command "destroy .set_rate"
   
   pack .set_rate.top.ok .set_rate.top.cancel .set_rate.top.label \
       -side left
   pack .set_rate.top.fill -before .set_rate.top.label \
       -side left  -expand 1 -fill x
   #
   # Scale
   #
   global getMcpStatusDelay update_rate
   set update_rate [expr 1e-3*$getMcpStatusDelay]

   set len 12;				# length of scale in cm
   scale .set_rate.scale -from 0 -to 50 \
       -length ${len}c -orient horizontal \
       -tickinterval 10 -sliderlength [expr 0.25*$len]c \
       -variable update_rate -command ""
   pack .set_rate.scale
}

proc show_update_rate {button dt} {
   if {$dt < 1} {
      set text "updates: [expr int(1/$dt)] Hz"
   } elseif {$dt == 1} {
      set text "updates: 1 Hz"
   } else {
      set text "updates: 1/$dt Hz"
   }

   $button configure -text $text
}

proc maybe_bind {button str} {
   global maybe_bindings
   lappend maybe_bindings [list $button $str]
}

proc maybe_bind_button {widget cmd} {
   global maybe_buttons
   lappend maybe_buttons [list $widget $cmd]
}

proc activate_maybe_bind {{activate -1}} {
   global maybe_bindings maybe_buttons menuColors

   if {$activate < 0} {
      if [keylget maybe_bindings active val] {
	 set activate [expr $val ? 0 : 1]
      } else {
	 set activate 1
      }
   }

   if $activate {
      set_status_msg "Buttons are enabled"
      set text "disable"
   } else {
      set_status_msg "Buttons are disabled"
      set text "enable"
   }

   if [winfo exists .mcp_menu.activate] {
      .mcp_menu.activate configure -text $text
   }
   
   foreach el $maybe_bindings {
      set button [lindex $el 0]
      set str [lindex $el 1]

      if {$button == "active"} {
	 continue
      }

      if $activate {
	 bind $button <Button-1> "depress $button;
	                           foreach c \[split $str {}\] {
				      do_menu_cmd \"\$c\"
				   }"
	 bind $button <Button-2> "echo :$str:\[split $str {}\]:"
	 $button configure -fg $menuColors(foreground)
      } else {
	 bind $button <Button-1> "depress $button; bell;
                                  set_status_msg {buttons are deactivated}"
	 $button configure -fg "slategray"
      }
   }

   foreach el $maybe_buttons {
      set widget [lindex $el 0]
      set cmd [lindex $el 1]

      if $activate {
	 bind $widget <Button-1> $cmd
	 $widget configure -state normal
      } else {
	 bind $widget <Button-1> "depress $widget; bell;
                                  set_status_msg {buttons are deactivated}"
	 $widget configure -state disabled
      }
   }

   keylset maybe_bindings active $activate
}

proc killMcpMenu {} {
   global exit_mcpMenu;			# used by start_mcpMenu

   mcpFullAccess -give
   destroy .mcp_menu
   schedule getMcpStatus {} 0
   catch {
      global mcpCommandPort
      close $mcpCommandPort; unset mcpCommandPort
   }
   set exit_mcpMenu 1

   if [winfo exists .mcp_pid_display] {
      destroy .mcp_pid_display
   }
}

proc getString {prompt} {
   global getString readString finished_readString

   if [info exists finished_readString] {
      unset finished_readString
   }

   set_getString_prompt $prompt
   set readString 1; set getString ""
   tkwait variable finished_readString
   set readString 0
   set_getString_prompt ""

   set retString $getString; set getString ""

   return $retString
}

proc set_getString_prompt {{prompt ""}} {
   if {$prompt == ""} {
      .mcp_menu.getString.lab configure -relief flat -text ">"
      bind .mcp_menu.getString.lab <Button-1> do_mcp_command
   } else {
      .mcp_menu.getString.lab configure -relief groove -text $prompt
      bind .mcp_menu.getString.lab <Button-1> ""
   }
}

#
# Submit a command to the MCP
#
proc do_mcp_command {} {
   set_status_msg ""

   regsub { *$} [getString "MCP command:"] "" command

   if {$command == ""} {
      return
   }

   eval sendMcpCmd status_msg [string toupper $command]
}

#
# Return an abbreviation for an axis
#
proc get_aname {a} {
   return [string tolower [string range $a 0 1]]
}

###############################################################################
#
# A proc to get information from the MCP; usually scheduled
#
proc getMcpStatus {args} {
   global ticks_per_degree axisStatus setAxisArr alt_clinometer
   global mcpMenu_time mcpMenu_serialNumber
   global axis_select;			# selected axis
   global mcpVersion
   global status_msg status_msg_time
   
   set active_axis_only [expr [incr mcpMenu_serialNumber]%4 != 0]
   
   if {$mcpMenu_serialNumber%20 == 0 || 
       [regexp {\?\?\?|unavailable} $mcpVersion]} {
      get_mcp_plc_versions
   }

   show_semCmdPort

   if {[getclock] - $status_msg_time > 15} {
      set status_msg ""
   }

   foreach a "Azimuth Altitude Rotator" {
      if {$active_axis_only && $a != $axis_select} {
	 continue;
      }

      set vals [mcpAxisStatus $setAxisArr($a)]
      if {$vals == ""} {
	 return
      }
      set mcpMenu_getclock [getclock]
      
      set i -1
      set tpd [lindex $vals [incr i]]; set ticks_per_degree($a) $tpd
      set monitor_on [lindex $vals [incr i]]
      set axis_status [lindex $vals [incr i]];# from axis_status()
      set actual_position [lindex $vals [incr i]]
      set position [lindex $vals [incr i]]
      set voltage [lindex $vals [incr i]]
      set velocity [lindex $vals [incr i]]
      set fiducialidx [lindex $vals [incr i]]
      set markvalid [lindex $vals [incr i]]
      set fid_mark [lindex $vals [incr i]]
      set stop_button_in [lindex $vals [incr i]]
      set brake_is_on [lindex $vals [incr i]]
      set axis_stat [lindex $vals [incr i]];# from axis_stat[]
      catch {
	 set alt_clinometer [format %.2f [lindex $vals [incr i]]]
      }

      if {$monitor_on == ""} {
	 return
      }

      set aname [get_aname $a]

      set val ""
      if $monitor_on { append val "*" } else { append val "U" }
      
      switch -regexp $axis_status {
	 {^[012]$} { append val "*" }
	 {^8$}     { append val "S" }
	 {^10$}    { append val "E" }
	 {^14$}    { append val "A" }
	 {.}       { append val "*" }
      }

      if {($axis_stat & (1<<22))} {	# amp_ok
	 append val "*"
      } else {
	 if {$brake_is_on == 1} {
	    append val "B"
	 } elseif {($axis_stat & (1<<8))} {# closed_loop
	    append val "*"
	 } else {
	    append val "O"
	 }
      }
      if $stop_button_in {
	 append val "S"
      } else {
	 append val "*"
      }

      global ${aname}_axis_state; set ${aname}_axis_state $val

      if ![regexp {^[U*]\*\*\*$} $val] {	# axis isn't ready to move
	 global JK_vel
	 set JK_vel($a) 0
      }
	    
      global ${aname}_axis_pos_dms
      set ${aname}_axis_pos_dms \
	  [format_dms [expr $actual_position/$tpd]]
      
      global ${aname}_axis_pos_act
      set ${aname}_axis_pos_act $actual_position
      
      global ${aname}_axis_pos_err
      set ${aname}_axis_pos_err [expr $actual_position - $position]
      
      global ${aname}_axis_pos_vlt
      set ${aname}_axis_pos_vlt $voltage
            
      global ${aname}_axis_velocity
      set ${aname}_axis_velocity [expr int($velocity/409.6)]

      global axis_velArr;
      if [info exists axis_select] {
	 set axis_velArr($axis_select) [set ${aname}_axis_velocity]
	 if {$a == $axis_select} {
	    set_axis_vel_str $axis_velArr($axis_select)
	 }
      }

      set val ""
      if {$fiducialidx <= 0} {
	 set pos "No Crossing"
      } else {
	 if $markvalid {
	    append val "V"
	 } else {
	    append val " "
	 }
	 append val [format " %3d;" $fiducialidx]

	 set pos [format_dms [expr $fid_mark/$tpd]]
      }

      global ${aname}_axis_fid ${aname}_axis_fid_pos
      
      set ${aname}_axis_fid $val
      set ${aname}_axis_fid_pos $pos
   }

   if !$active_axis_only {
      #
      # Get the system status
      #
      set status [mcpSystemStatus]
      #
      # Lamps and flatfield screen
      #
      foreach type "FF HgCd Ne FFS Wht UV" {
	 set stat [keylget status [string tolower $type]]
	 
	 set on 0
	 foreach i $stat {
	    incr on $i
	 }
	 set on [expr $on ? 1 : 0]
	 if {$type == "FFS"} {
	    if $on { set on "closed" } else { set on "open" }
	 }
	 
	 global ${type}_status
	 set ${type}_status $on
      }
      #
      # Spectrographs
      #
      loop sp 1 3 {
	 set stat [keylget status spec$sp]
	 foreach which "Door Slithead" {
	    global sp${sp}${which}_status;
	    
	    if {$which == "Door"} {
	       if [lindex $stat 0] {
		  set state "open"
	       } else {
		  set state "closed"
	       }
	    } else {
	       if [lindex $stat 2] {
		  set state "extended"
	       } else {
		  set state "retracted"
	       }
	    }
	    
	    set sp${sp}${which}_status $state
	 }
      }
      #
      # Counter weights
      #
      global cwpos
      
      set vals [keylget status cw]
      loop c 1 5 {
	 set cwpos($c) [lrange $vals [expr 2*($c-1) + 0] [expr 2*($c-1) + 1]]
	 regsub -all { |\.} $cwpos($c) "" cwpos($c)
      }
      #
      # Inst
      #
      set vals [keylget status inst]

      #
      # Misc
      #
      set vals [keylget status misc]

      set iacked [lindex $vals 0]
      
      if {$iacked != ""} {
	 global iack_button menuColors
	 catch {				# we may not be running Tk
	    if [winfo exists $iack_button] {
	       if $iacked {
		  set fg $menuColors(background)
	       } else {
		  set fg $menuColors(iack)
	       }

	       if {[$iack_button cget -fg] != "$fg"} {
		  $iack_button configure -fg $fg
	       }
	    }
	 }
      }
   }
   #
   # Update the time-of-last-packet info
   #
   global mcpMenu_time

   set mcpMenu_time [utclock [getclock]]
}

###############################################################################
#
# Return an axis's position in degrees
#
proc mcpGetPosition {axis} {
   global setAxisArr ticks_per_degree

   set vals [mcpAxisStatus $setAxisArr($axis)]
	 
   if {[regexp {I don't have} $vals] || $vals == ""} {
      return ""
   }
	 
   set tpd [lindex $vals 0]; set ticks_per_degree($axis) $tpd
   set actual_position [lindex $vals 3]

   if {$actual_position == ""} {
      echo $vals
      return ""
   }
	 
   return [expr $actual_position/$tpd]
}

###############################################################################
#
# Show who has the semCmdPort semaphore
#
proc show_semCmdPort {{i -1}} {
   global permit_button menuColors took_semCmdPort

   if {$i < 0} {
      if {[catch {set sem_show [mcpPut SEM.SHOW]}] ||
	  ![regexp {semCmdPort=([01])} $sem_show foo i]} {
	 set text "MCP is unavailable"
	 set bg $menuColors(unknown)
	 $permit_button configure -text $text -bg $bg -fg black

	 return;
      }

      set took_semCmdPort [expr !$i];	# force update
   }

   if {$took_semCmdPort != $i} {
      set took_semCmdPort $i
      #
      # Deal with menu button, if it exists
      #
      if {[info exists permit_button] && [winfo exists $permit_button]} {
	 if $took_semCmdPort {
	    set text "Full"
	    set bg $menuColors(full_access)
	 } else {
	    set text "Restrict"
	    set bg $menuColors(restrict_access)
	 }
	 $permit_button configure -text $text -bg $bg -fg black
      }
   }
}

###############################################################################
#
# Format an angle (in degrees) in degree:min:sec
#
proc format_dms {fdeg} {
   if {$fdeg < 0} {
      set sign "-"
      set fdeg [expr -$fdeg]
   } else {
      set sign " "
   }
   
   set deg [expr int($fdeg)]
   set min [expr int(60*($fdeg - $deg))]
   set sec [expr 3600*($fdeg - $deg - $min/60.0)]

   if {[format %05.2f $sec] >= 60.0} {
      set sec [expr $sec - 60.0]
      incr min 1
      if {$min >= 60} {
	 incr min -60
	 incr deg
      }
   } elseif {$sec < -60.0} {
      set sec [expr $sec + 60.0]
      incr min -1
      if {$min < 0} {
	 incr min 60
	 incr deg -1
      }
   } 

   return [format "$sign%03d:%02d:%05.2f" $deg $min $sec]
}

###############################################################################

proc sendMcpCmd {_str args} {
   upvar $_str str
   set reply [mcpPut $args]

   if {$reply != ""} {
      bell
      set str "$args: $reply"
      set_status_msg $str

      return 1
   }

   return 0
}

###############################################################################
#
# Convert a decimal angle or ddd:mm:ss.ss value to a decimal angle;
# return 0 in case of successful conversion, -1 otherwise
#
proc get_angle {str _val} {
   upvar $_val val
   #
   # Is str a decimal number?
   #
   if {[regexp {^ *[+-]?([0-9]*)\.([0-9]*)} $str foo lhs rhs] &&
       ($lhs != "" || $rhs != "")} {
      set val $str
      return 0
   }
   #
   # No; should be deg:min:sec
   #
   set sign ""; set deg ""; set min ""; set sec ""
   regexp {^ *([+-])?([0-9]*):?([0-9]*):?([0-9]+\.([0-9]*))?} $str \
       foo sign deg min sec
   if {$deg == "" && $min == "" && $sec == ""} {
	      return -1
   }

   set val 0
   if {$deg != ""} {
      set val [expr $val + $deg]
   }

   if {$min != ""} {
      set val [expr $val + $min/60.0]
   }

   if {$sec != ""} {
      set val [expr $val + $sec/3600.0]
   }

   if {$sign == "-"} {
      set val [expr -$val]
   }

   return 0
}

###############################################################################
#
# Set which axis is being controlled
#
proc set_active_axis {axis} {
   global axis_select axis_velArr axis_incvelArr axis_adjposArr axis_adjvelArr

   set axis_select $axis

   set_axis_name_str $axis_select
   set_axis_vel_str $axis_velArr($axis_select)
   set_axis_incvel_str $axis_incvelArr($axis_select)
   set_axis_adjpos_str $axis_adjposArr($axis_select)
   set_axis_adjvel_str $axis_adjvelArr($axis_select)
   
   show_active_axis
}

###############################################################################
#
# Show which axis is currently being controlled
#
proc show_active_axis {} {
   global axis_select axis_label_widget menuColors

   foreach a [array names axis_label_widget] {
      if {$a == $axis_select} {
	 set fg $menuColors(selected_axis)
      } else {
	 set fg $menuColors(nonselected_axis)
      }
      
      $axis_label_widget($a) configure -fg $fg
   }
}

###############################################################################
#
# Toggle a lamp
#
proc toggle_lamp {type} {
   set status [mcpSystemStatus -[string tolower $type]]

   set n_on 0
   foreach i $status {
      incr n_on $i
   }
   
   if {$n_on == 0} {
      set_status_msg "Turning $type lamps on"
      sendMcpCmd status_msg [string toupper $type.ON]
   } else { 
      set_status_msg "Turning $type lamps off"
      sendMcpCmd status_msg [string toupper $type.OFF]
   }
}

###############################################################################
#
# Open (1), close (0), or toggle (-1) the flat field screens
#
proc open_ffs {open} {
   if {$open < 0} {			# toggle
      set nclosed 0
      foreach i [mcpSystemStatus -ffs] {
	 incr nclosed $i
      }
   
      if {$nclosed == 0} {
	 set open 0
      } elseif {$nclosed == 8} {
	 set open 1
      } else {
	 bell
	 set_status_msg "flatfield screen is in unknown state"
	 set FFS_status unknown
	 return
      }
   }

   if $open {
      set_status_msg "Opening flatfield screen"
      sendMcpCmd status_msg FFS.OPEN
   } else {
      set_status_msg "Closing flatfield screen"
      sendMcpCmd status_msg FFS.CLOSE
   }
}

#
# Toggle whether the FFS petals are enabled
#
proc toggle_ffs_enable {n} {
   global ffs_1_enab ffs_2_enab
   set ffs_${n}_enab [expr ![set ffs_${n}_enab]]

   if {$n == 1} { set tb "top" } else { set tb "bottom" }

   if [set ffs_${n}_enab] {
      set pparticiple "Enabling"
   } else {
      set pparticiple "Disabling"
   }      

   set_status_msg "$pparticiple $tb petals"
   sendMcpCmd status_msg ffs.select [expr $ffs_1_enab | ($ffs_2_enab << 1)]
}

###############################################################################
#
# Deal with the spectrographs
#
proc open_spectro_door {sp open} {
   if {$open < 0} {
      set vals [mcpSystemStatus -spec$sp]
      set slit_door_open [lindex $vals 0]
      set slit_door_closed [lindex $vals 0]

      if {$slit_door_open && !$slit_door_close} {
	 set open 0
      } elseif {!$slit_door_open && $slit_door_close} {
	 set open 1
      } else {
	 bell
	 set_status_msg "SP$sp slit door is neither open or closed"
	 return
      }
   }

   if $open {
      set_status_msg "Opening SP$sp slit door"
      sendMcpCmd status_msg SP$sp SLITDOOR.OPEN
   } else {
      set_status_msg "Closing SP$sp slit door"
      sendMcpCmd status_msg SP$sp SLITDOOR.CLOSE
   }
}

proc ext_slit_latch {sp extend} {
   if {$extend < 0} {
      set vals [mcpSystemStatus -spec$sp]
      
      set slit_head_latch_ext [lindex $vals 2]
      
      if $slit_head_latch_ext {
	 set extend 0
      } else {
	 set extend 1
      }
   }
      
   if $extend {
      set_status_msg "Extending SP$sp slithead latch"
      sendMcpCmd status_msg SP$sp SLITHEADLATCH.CLOSE
   } else {
      set_status_msg "Retracting SP$sp slithead latch"
      sendMcpCmd status_msg SP$sp SLITHEADLATCH.OPEN
   }
}

###############################################################################
#
# Actually move an axis
#
proc set_pos_va {axis pos vel acc} {
   global setAxisArr ticks_per_degree
   global axis_accLimitArr axis_velLimitArr

   if {$ticks_per_degree($axis) == 1} {
      bell
      set_status_msg "I don't know the scale for axis $axis"
      return 1
   }

   if {abs($vel/$ticks_per_degree($axis)) > $axis_velLimitArr($axis)} {
      bell
      set_status_msg [format "velocity $vel is too large (max: %.0f)" \
		      [expr $axis_velLimitArr($axis)*$ticks_per_degree($axis)]]
      return 1
   }

   if {abs($acc/$ticks_per_degree($axis)) > $axis_accLimitArr($axis)} {
      bell
      set_status_msg [format "acceleration $acc is too large (max: %.0f)" \
		      [expr $axis_accLimitArr($axis)*$ticks_per_degree($axis)]]
      return 1
   }
   
   return [sendMcpCmd status_msg $setAxisArr($axis) SET.POS.VA $pos $vel $acc]
}

###############################################################################

proc do_menu_cmd {c} {
   global axis_select axis_name axis_velArr JK_vel
   global axis_incvelArr axis_adjposArr axis_adjvelArr axis_adjaccArr
   global setAxisArr ticks_per_degree
   global getString readString finished_readString
   #
   # Do we want to read a string rather than process events? We expect
   # someone to be tkwaiting on finished_readString, usually proc getString
   #
   if $readString {
      if {$c == "\r"} {
	 set finished_readString 1
      } elseif {$c == "\177" || $c == "\010"} {
	 if {$getString == ""} {
	    bell
	    set finished_readString 1
	 } else {
	    regsub {.$} $getString {} getString
	 }
      } else {
	 append getString $c
      }
      return
   }

   set_status_msg ""

   global menu_last_char
   if {$c == "\r"} {
      if [info exists menu_last_char] {
	 set c $menu_last_char
	 unset menu_last_char
	 set getString ""; set_getString_prompt
      }
   } elseif {$c == "\177" || $c == "\010"} {
      if [info exists menu_last_char] {
	 set c $menu_last_char
	 unset menu_last_char
	 set getString ""; set_getString_prompt
      }
      return
   } elseif {$c == 22 || [regexp {[ ?%bBhHjJkKsS]} $c]} {
      ;					# immediate action
   } else {
      global mcpHelp
      
      if [regexp {^[0-9]$} $c] {
	 bell
	 return
      }

      set menu_last_char $c
      if [info exists mcpHelp([string tolower $c])] {
	 set getString $mcpHelp([string tolower $c])
      } elseif {$c == "\003"} {		# correct
	 set getString "Correct fiducial positions"
      } elseif {$c == 24} {		# ^X
	 set getString "Reset the MCP/TPM crate"
      } else {
	 set getString "$c";
      }
      set_getString_prompt "Command:"
      return
   }

   switch -regexp -- $c {
      "\003" {
	 set status_msg "Correcting position of $axis_select"
	 sendMcpCmd status_msg $setAxisArr($axis_select) CORRECT
      }
      "22" {				# ^V
	 set_status_msg "MCPOP version: [mcpopVersion]"
      }
      "24" {				# ^X
	 set reply [getString "Soft or hard reset? \[soft|hard\]"]

	 if {$reply == "0" || $reply == "soft" || $reply == "SOFT"} {
	    set_status_msg "Resetting MCP board"
	    mcpResetCrate -soft
	 } elseif {$reply == "1" || $reply == "hard" || $reply == "HARD"} {
	    set_status_msg "Resetting MCP/MEI/TPM VME crate"
	    mcpResetCrate -hard
	 } else {
	    set_status_msg \
		"Please decide between \"soft\" and \"hard\" and try again"
	 }
      }
       "PID" {
	   set reply [getString "Display PID configurator (y/n)?"]
       if {$reply=="y"} {
         display_PID_coeffs
       }
      }
      "\[ \r\]" {
	 set_status_msg ""
	 set getString ""; set_getString_prompt
      }
      {[aA]} {
	 set reply [getString "Offset position by xxx counts"]

	 if ![regexp {^[+-]?[0-9]+$} $reply] {
	    if ![regexp {^ *$} $reply] {
	       set_status_msg "Illegal number: $reply"
	    }
	 } else {
	    set actual_pos [get_aname $axis_select]_axis_pos_act
	    global $actual_pos
	    
	    set adjpos [expr [set $actual_pos] + $reply]
	    set axis_adjposArr($axis_select) $adjpos
	    set_axis_adjpos_str $adjpos
	 }
      }
      {[bB]} {
	 if {$axis_select == "Rotator"} {
	    set_status_msg "The rotator doesn't have a brake"
	    bell
	 } else {
	    set status_msg "$axis_select Brake Turned On"
	    sendMcpCmd status_msg $setAxisArr($axis_select) BRAKE.ON
	 }
	 set JK_vel($axis_select) 0
      }
      {[cC]} {
	 set status_msg "$axis_select Brake Turned Off"
	 sendMcpCmd status_msg $setAxisArr($axis_select) BRAKE.OFF
	 set JK_vel($axis_select) 0
      }
      {[dD]} {
	 set reply [getString "Destination position xxx:xx:xx.xxx"]

	 if {[get_angle $reply ang] < 0} {
	    if ![regexp {^ *$} $reply] {
	       set_status_msg "Illegal number: $reply"
	    }
	 } else {
	    set axis_adjposArr($axis_select) \
		[expr $ang*$ticks_per_degree($axis_select)]
	    set_axis_adjpos_str $axis_adjposArr($axis_select)
	 }
      }
      {[fF]} {
	 set status_msg "$axis_select Fiducial Position Set"
	 sendMcpCmd status_msg $setAxisArr($axis_select) SET.FIDUCIAL
      }
      {[gG]} {
	 foreach a "Altitude Azimuth" {
	    if {$axis_adjvelArr($a) == 0} {
	       bell
	       set_status_msg "Velocity for $a is 0"
	       return;
	    }
	 }
	 
	 set_status_msg "Moved Altitude and Azimuth"
	 foreach a "Altitude Azimuth" {
	    if ![set_pos_va $a $axis_adjposArr($a) \
		     $axis_adjvelArr($a) $axis_adjaccArr($a)] {
	       break
	    }
	    set JK_vel($axis_select) 0
	 }
      }
      {[hH]} {
	 set status_msg "$axis_select held"
	 if {[sendMcpCmd status_msg $setAxisArr($axis_select) HOLD] == 0} {
	    set axis_velArr($axis_select) 0
	    set_axis_vel_str 0
	    set JK_vel($axis_select) 0
	 }
      }
      {[iI]} {
	 set reply [getString "Set velocity increment"]

	 if ![regexp {^[+-]?[0-9]+$} $reply] {
	    if ![regexp {^ *$} $reply] {
	       set_status_msg "Illegal number: $reply"
	    }
	 } else {
	    set axis_incvelArr($axis_select) $reply
	    set_axis_incvel_str $axis_incvelArr($axis_select)
	 }
      }
      {[jJkK]} {
	 if [regexp {[jJ]} $c] {
	    set dv -$axis_incvelArr($axis_select)
	 } else {
	    set dv $axis_incvelArr($axis_select)
	 }
	 
	 set JK_vel($axis_select) [expr $JK_vel($axis_select) + $dv]
	 
	 set axis_velArr($axis_select) $JK_vel($axis_select)
	 set_axis_vel_str $axis_velArr($axis_select)
	 
	 set status_msg "Adjusting velocity for $axis_select"
	 if [sendMcpCmd status_msg $setAxisArr($axis_select) SET.VELOCITY \
		 $axis_velArr($axis_select)] {# failed
	    set JK_vel($axis_select) [expr $JK_vel($axis_select) - $dv]
	 }
      }
      {[lL]} {
	 set_active_axis "Altitude"
      }
      {[mM]} {
	 if {$axis_adjvelArr($axis_select) == 0} {
	    bell
	    set_status_msg "Velocity for $axis_select is 0"
	    return;
	 }
	 
	 set_status_msg "Moving $axis_select"
	 set_pos_va $axis_select $axis_adjposArr($axis_select) \
	     $axis_adjvelArr($axis_select) $axis_adjaccArr($axis_select)
	 set JK_vel($axis_select) 0
      }
      {[oO]} {
	 set reply [getString "Offset position by xxx:xx:xx.xxx"]

	 if {[get_angle $reply ang] < 0} {
	    if ![regexp {^ *$} $reply] {
	       set_status_msg "Illegal number: $reply"
	    }
	 } else {
	    set actual_pos [get_aname $axis_select]_axis_pos_act
	    global $actual_pos

	    set adjpos \
		[expr [set $actual_pos] + $ang*$ticks_per_degree($axis_select)]
	    set axis_adjposArr($axis_select) $adjpos
	    set axis_adjpos_str $adjpos
	 }
      }
      {[pP]} {
	 set reply [getString "Position xxx:xx:xx.xxx"]

	 if {[get_angle $reply ang] < 0} {
	    if ![regexp {^ *$} $reply] {
	       set_status_msg "Illegal number: $reply"
	    }
	 } else {
	    set status_msg "Set Position for $axis_select"
	    set pos [expr $ang*$ticks_per_degree($axis_select)]
	    sendMcpCmd status_msg $setAxisArr($axis_select) SET.POSITION $pos
	 }
      }
      {[rR]} {
	 set_active_axis "Rotator"
      }
      {[sS]} {
	 set status_msg "Stopping $axis_select"
	 if {[sendMcpCmd status_msg $setAxisArr($axis_select) STOP] == 0} {
	    set axis_velArr($axis_select) 0
	    set_axis_vel_str 0
	    set JK_vel($axis_select) 0
	 }
      }
      {[tT]} {
	 bell
	 set_status_msg "Command \"t\" (Manual trigger) is not implemented"
      }
      {[vV]} {
	 set reply [getString "Set velocity"]

	 if ![regexp {^[+-]?[0-9]+$} $reply] {
	    if ![regexp {^ *$} $reply] {
	       set_status_msg "Illegal number: $reply"
	    }
	 } else {
	    set axis_adjvelArr($axis_select) $reply
	    set_axis_adjvel_str $reply
	 }
      }
      {[wW]} {
	 set reply \
	     [getString "xx|name: 2=EMPTY;3=SCF;4=S;5=SC;6=SE;7=SEC;8=SI"]

	 set status_msg ""
	 sendMcpCmd status_msg CWINST $reply
      }
      {[xX]} {
	 killMcpMenu
      }
      {[yY]} {
	 set status_msg "Initialising $axis_select"
	 sendMcpCmd status_msg $setAxisArr($axis_select) INIT
      }
      {[zZ]} {
	 set_active_axis "Azimuth"
      }
      {[*]} {
	 set status_msg "Amp reset"
	 sendMcpCmd status_msg $setAxisArr($axis_select) AMP.RESET
	 set JK_vel($axis_select) 0
      }
      {[+=]} {
	 set status_msg "ALIGNment Clamp Turned On"
	 sendMcpCmd status_msg CLAMP.ON
      }
      {[-_]} {
	 set status_msg "ALIGNment Clamp Turned Off"
	 sendMcpCmd status_msg CLAMP.OFF
      }
      {[()]} {
	 if {$c == "("} {
	    set sp 1
	 } else {
	    set sp 2
	 }

	 open_spectro_door $sp -1
      }
      {[{}]} {
	 if {$c == "\{"} {
	    set sp 1
	 } else {
	    set sp 2
	 }
	 
	 ext_slit_latch $sp -1
      }
      {~} {
	 open_ffs -1
      }
      {\|} {
	 toggle_lamp FFL
      }
      {"} {				# "
	 toggle_lamp Ne
      }
      {:} {
	 toggle_lamp HgCd
      }
      {%} {
	 set status_msg "CW ABORT"
	 sendMcpCmd status_msg CWABORT
      }
      {[!@#$^]} {
	switch $c {
	   "^" { set cw -999; # All }
	   "!" { set cw 0 }
	   "@" { set cw 1 }
	   "\#" { set cw 2 }
	   "$" { set cw 3 }
	}

	 set reply [getString "Desired CW position (or U/L)"]

	 if [regexp {^[bB]$} $reply] {	# balance
	    set reply 0
	 } elseif [regexp {^[0Ll]$} $reply] {	# lower limit
	    set reply 15
	 } elseif {[regexp {^[uU]$} $reply]} {# upper limit
	    set reply 799
	 }
	   
	 if ![regexp {^[+-]?[0-9]+$} $reply] {
	    if ![regexp {^ *$} $reply] {
	       set_status_msg "Illegal number: $reply"
	    }
	 } else {
	    set status_msg "Moving counterweight"
	    sendMcpCmd status_msg CWMOV $cw $reply
	 }
      }
      {&} {
	 set status_msg "Toggling monitor for $axis_select"
	 sendMcpCmd status_msg $setAxisArr($axis_select) SET.MONITOR -1
      }
      {%} {
	 set status_msg "Aborting CW motion"
	 sendMcpCmd status_msg CWABORT
      }
      {[?]} {
         mcpMenuHelp
      }
      default {
	 bell
	 set_status_msg "Command \"$c\" is not (yet?) implemented"
      }
   }

   update
}

###############################################################################
#
# Misc procs to set strings used in mcpMenu
#
proc set_axis_name_str {val} {
   global axis_name
   set axis_name "$val Motion"
}

proc set_axis_vel_str {val} {
   global axis_select axis_vel_str axis_vel_asec_str ticks_per_degree \
       menu_JK_widget menuColors

   if ![winfo exists $menu_JK_widget(J)] {
      return
   }

   set axis_vel_str [format "%6s" $val]
   set axis_vel_asec_str [format "%6.1f" \
			      [expr 3600*$val/$ticks_per_degree($axis_select)]]

 
   set fg(J) $menuColors(nonselected_axis)
   set fg(K) $menuColors(nonselected_axis)
   if {$val < 0} {
      set fg(J) $menuColors(selected_axis_J)
   } elseif {$val > 0} {
      set fg(K) $menuColors(selected_axis_K)
   }

   foreach v "J K" {
      $menu_JK_widget($v) configure -fg $fg($v)
   }
}

proc set_axis_incvel_str {val} {
   global axis_incvel_str
   set axis_incvel_str $val
}

proc set_axis_adjpos_str {val} {
   global axis_adjpos_dms axis_select ticks_per_degree
   set axis_adjpos_dms [format_dms [expr $val/$ticks_per_degree($axis_select)]]
}

proc set_axis_adjvel_str {val} {
   global axis_adjvel_str
   set axis_adjvel_str $val
}

###############################################################################
#
# Help for the menu
#
if ![info exists mcpHelp] {
   array set \
       mcpHelp [list \
		    a  "Change destination position by an offset in counts" \
		    b* "Set brake" \
		    c  "Enable axis and clear brake" \
		    d  "Set destination position" \
		    f  "Accept a fiducial" \
		    g  "Go to an (alt, az) position" \
		    h* "Hold an axis" \
		    i  "Set a velocity increment dv for the j/k commands" \
		    j* "Decrease the currently selected axis' velocity by dv" \
		    k* "Increase the currently selected axis' velocity by dv" \
		    l  "Select the aLtitude axis (or click on \"AL\")" \
		    m  "Move current axis to position with specified vel. and acc." \
		    o  "Change destination position by an offset" \
		    p  "Set current position" \
            ctrl-p "Display PID configuration GUI" \
		    r  "Select the Rotator axis (or click on \"ROT\")" \
		    s* "Stop the selected axis" \
		    t  "Manual trigger (not implemented)" \
		    v  "Set the velocity" \
		    w  "Set the counterweights for a given instrument" \
		    x  "Exit the menu" \
		    y  "Initialise axis (say \"yes\" to moving)" \
		    z  "Select the aZimuth axis (or click on \"AZ\")" \
		    *  "Reset the amplifiers" \
		    +  "Set the alignment clamp (equivalent to =)" \
		    -  "Unset the alignment clamp (equivalent to _)" \
		    (  "Toggle SP1's slit door" \
		    )  "Toggle SP2's slit door" \
		    "{"  "Toggle SP1's slithead latch" \
		    "}"  "Toggle SP2's slithead latch" \
		    ~  "Toggle the Flatfield screen" \
		    |  "Toggle the Flatfield lamps" \
		    :  "Toggle the HgCd lamps" \
		    \" "Toggle the Ne lamps" \
		    %* "Abort a counterweight motion" \
		    &  "Toggle monitoring an axis" \
		    ^  "Move all counterweights" \
		    !  "Move counterweight 1" \
		    @  "Move counterweight 2" \
		    \#  "Move counterweight 3" \
		    \$  "Move counterweight 4" \
		   ]
}		       

proc mcpMenuHelp {{text ""}} {
   #
   # First find/create the display window
   #
   if [winfo exists .mcp_menu_help] {
      wm deiconify .mcp_menu_help
      raise .mcp_menu_help
   } else {
      toplevel .mcp_menu_help -class Dialog
      wm title .mcp_menu_help "MCP Menu Help"

      label .mcp_menu_help.title -text "Help for the MCP Menu"
      pack .mcp_menu_help.title
      #
      # Use a text not a label so that cut-and-paste works
      #
      frame .mcp_menu_help.frame
      text .mcp_menu_help.frame.text -wrap word -relief flat \
	  -height 35 -setgrid true \
	  -yscrollcommand {.mcp_menu_help.frame.scroll set}
      pack [scrollbar .mcp_menu_help.frame.scroll \
		-command {.mcp_menu_help.frame.text yview}] -side left -fill y
      pack .mcp_menu_help.frame.text -side right -fill both -expand true
      pack .mcp_menu_help.frame
      #
      # Bottom panel of buttons
      #
      frame .mcp_menu_help.bottom
      button .mcp_menu_help.bottom.quit -text "close" -relief groove \
	  -command "destroy .mcp_menu_help"
      button .mcp_menu_help.bottom.icon -text "iconify" -relief groove \
	  -command "wm iconify .mcp_menu_help"
      pack .mcp_menu_help.bottom.quit .mcp_menu_help.bottom.icon \
	  -side left
      
      pack .mcp_menu_help.bottom
   }
   #
   # Here's the help string
   #
   if {$text == ""} {
      set text \
"\
Many commands are restricted to the \"authorised\" user; to request that
status click on the button in the top left hand corner -- it'll say \"Full\"
if you are that blessed person. Click again to relinquish authority; right
click to steal the authority from someone/thing.  If the MCP has rebooted, the
word \"Rebooted\" will appear in red; click on it to acknowledge the reboot.

As an alternative to remembering which key does what, you may click on
outlined text to change the associated value or issue a command. The
bottom row of command buttons (clear_brake etc.) may be dis/enabled with the
(dis/en)able button at the bottom of the menu.

To reset the MCP/TPM crate, hit ^X; to show iop's version hit ^V. 
You can issue any command you like by clicking on the \">\" near the bottom.

The \"MSAE\" column means:
  \"Monitor status\"  *: monitored; U: not monitored
  \"axis Status\"     *: OK; S: stop; E: e-stop; A: aborted
  \"Amp status\"      *: in closed loop; B: brake on; O: out of closed loop;
  \"E-stop\"          *: out; S: in

You can change the update rate with the \"updates\" button; your
selected rate will only be adopted when you press \"accept\". A rate
of \"0\" is interpreted as 2Hz. Your actual rate will probably be a
little lower than what you requested.

Commands followed by a \"*\" don't require you to hit a carriage return.

"
   
      global mcpHelp
   
      foreach c [lsort -ascii [array names mcpHelp]] {
         if [regexp {[!@#$]} $c] {
	    if {$c == "!"} {
               append text "\t!@\#\$\tMove counterweight 1, 2, 3, or 4\n"
            }
         } else {
            append text "\t$c\t$mcpHelp($c)\n"
         }
      }
   }
   #
   # Insert that text
   #
   .mcp_menu_help.frame.text delete 1.0 end
   .mcp_menu_help.frame.text insert end $text
   
   set width [string length $text]
   if {$width < 50} {
      set width 50
   } elseif {$width > 80} {
      set width 80
   }
   set lines [split $text "\n"]
   
   .mcp_menu_help.frame.text configure -width $width
}

###############################################################################
#
# Format an axis status word
#
lappend mcpHelp_procs formatAxisStat

proc formatAxisStat {args} {
   global AXIS_STAT;

   set opts \
       [list \
	    [list [info level 0] ""] \
	    {<status> INTEGER 0.0 status \
		 "Status word as returned by e.g. AXIS STATUS"} \
	    ]

   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   set text ""
   foreach el [array names AXIS_STAT] {
      if {$status & $el} {
	 lappend text "$AXIS_STAT($el)"
      }
   }
   
   return $text
}

###############################################################################
#
# Manage a window to display/set the MEI PID coefficients
#
proc display_PID_coeffs {args} {
   global menuColors setAxisArr

   set opts \
       [list \
	    [list [info level 0] \
		 "Create a window to display/set the MEI's PID coefficients"] \
	    {-geom STRING "" geom "X geometry string"}\
	   ]
   
   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   if [winfo exists .mcp_pid_display] {
      wm deiconify .mcp_pid_display
      raise .mcp_pid_display
      
      foreach axis "Azimuth Altitude Rotator" {
	 set aname [get_aname $axis]
	 
	 set values [mcpPut $setAxisArr($axis) GET.FILTER.COEFFS]
	 
	 loop j 1 [llength $values] {
	    if [regexp {^([^=]+)=([0-9]*)} \
		    [lindex $values $j] {} cname val] {
	       global ${aname}_coeff_$cname;
	       set ${aname}_coeff_$cname "$val"
	    }
	 }
      }
      
      return
   }

   option add *Background $menuColors(background)
   option add *Foreground $menuColors(foreground) 

   toplevel .mcp_pid_display

   wm title .mcp_pid_display "MEI PID Coefficients"
   if {$geom != ""} {
      wm geometry .mcp_pid_display $geom
   }
   pack [frame .mcp_pid_display.main]
   #
   # Create the coefficient displays
   #
   set i 0
   foreach axis "Axis Azimuth Altitude Rotator" {
      incr i
      pack [set row [frame .mcp_pid_display.main.row$i]] -expand 1 -fill x

      set aname [get_aname $axis]

      if {$axis == "Axis"} {
	 set values [mcpPut GET.FILTER.COEFFS];# just get names
      } else {
	 set values [mcpPut $setAxisArr($axis) GET.FILTER.COEFFS]
      }
      
      pack [label $row.axis_name -width 9 -text $axis] -side left
      loop j 1 [llength $values] {
	 if [regexp {^([^=]+)=([0-9]*)} [lindex $values $j] {} cname val] {
	    global ${aname}_coeff_$cname;
	    if {$axis == "Axis"} {
	       set ${aname}_coeff_$cname "$cname"
	    } else {
	       set ${aname}_coeff_$cname "$val"
	    }
      
	    pack [label $row.coeff_$cname \
		      -textvariable ${aname}_coeff_$cname \
		      -width [expr [string length $cname] + 2]] -side left
	    if {$axis != "Axis"} {
	       bind $row.coeff_$cname <Button-1> \
		   "depress $row.coeff_$cname; update_pid_coeff $axis $cname $row.coeff_$cname"
	    }
	 }
      }
   }
   #---------------------------------------------------------------------------
   #
   # Buttons
   #
   pack [button .mcp_pid_display.help -text help \
	     -command {mcpMenuHelp "\
 If buttons are enabled in the main mcpMenu window you may click on a
 value to change it; you'll be prompted in the mcpMenu window for your
 desired value. Hit delete if you decide that you really don't want to
 change anything.

 You need to hold the command semaphore to be allowed to change
 coefficients, and do please be careful.
"}] -side left
   pack [button .mcp_pid_display.refresh -text "update" \
	     -command "display_PID_coeffs"] -side left

   pack [frame .mcp_pid_display.fill] -expand 1 -fill x

   pack [button .mcp_pid_display.quit -text "quit" \
	     -command "destroy .mcp_pid_display"] -side right
   button .mcp_pid_display.icon -text "iconify" -relief groove \
	  -command "wm iconify .mcp_pid_display"
   pack .mcp_pid_display.icon -side right
   #
   # Revert to default colourmap
   #
   option add *Background [. cget -bg]
   option add *Foreground [. cget -highlightcolor]
}

proc update_pid_coeff {axis cname {parent ""}} {
   global setAxisArr maybe_bindings

   if ![keylget maybe_bindings active] {
      bell
      set_status_msg "buttons are deactivated"
      return
   }

   set val [getString "New value of $cname coefficient for $axis:"]

   if {$val != ""} {
      set var [get_aname $axis]_coeff_$cname; global $var
      set old [set $var]
      if [yes_or_no "Setting PID Coefficient" \
	      "Change $axis $cname coefficient from $old to $val?" \
	     $parent] {
	 sendMcpCmd "Setting $cname for $axis" \
	     $setAxisArr($axis) SET.FILTER.COEFF $cname $val
      } else {
	 bell
	 set_status_msg "Not changing $cname for $axis"
      }
   }
}

###############################################################################
#
# Popup a y-or-no dialog
#
proc yes_or_no {title text {parent ""}} {
   set id [getclock]
   global dialog_done$id

   set w "._[string tolower $title]_${id}_dialog"
   regsub -all { } $w "_" w;
   if [winfo exists $w] {
      destroy $w
   }

   global menuColors
   option add *Background $menuColors(background)
   option add *Foreground $menuColors(foreground)

   toplevel $w -class Dialog
   wm title $w $title
   frame $w.frame

   button $w.frame.yes -text "Yes" -command "set dialog_done$id 1"
   button $w.frame.no  -text "No"  -command "set dialog_done$id 0"
   bind $w "<Control-c>" [$w.frame.no cget -command]

   label $w.text -text $text

   pack $w.frame.yes $w.frame.no -side left
   pack $w.text
   pack $w.frame
   #
   # Revert to default colourmap
   #
   option add *Background [. cget -bg]
   option add *Foreground [. cget -highlightcolor]
   #
   # grab the focus
   #
   tkwait visibility $w
   focus $w                             
   #
   # put up the dialog, wait for a result, and restore the focus
   #
   if {$parent != ""} {
      set x [expr int([winfo rootx $parent]+[winfo width $parent]/2)]
      set y [expr int([winfo rooty $parent]+[winfo height $parent]/2)]
      wm geometry $w +$x+$y
      wm transient $w .
   }
   tkwait variable dialog_done$id

   destroy $w

   set val [set dialog_done$id]
   catch {
      unset dialog_done$id
   }

   return  $val
}

###############################################################################
#
# Format an mcpFiducials file nicely
#
lappend mcpHelp_procs formatMcpFiducials

proc formatMcpFiducials {args} {
   set diff 0;				# include encoder errors in output
   set keeptime 0;			# include unix time in output
   set utc 1;				# Print dates in utc?
   
   set opts \
       [list \
	    [list [info level 0] "Format an mcpFiducials file for a human
 to read.  Specify either a filename or an MJD"] \
	    {{[file]} STRING "" file "The file to format nicely (or an mjd)"} \
	    {-mjd INTEGER -1 mjd "Desired MJD (0 => today)"} \
	    {-outfile STRING "" outfile "File to write to (default: stdout)"} \
	    {-keeptimestamp CONSTANT 1 keeptime \
		 "Include unix timestamp in output"} \
	    {-diff CONSTANT 1 diff "Add columns for encoder errors"} \
	    {-localtime CONSTANT 0 utc "Print all dates local time, not UTC"} \
	    ]

   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   if {$file == "" && $mjd < 0} {
      error "Please specify either a filename or an mjd"
   } elseif {$file != "" && $mjd >= 0} {
      error "Please specify either a filename _or_ an mjd, not both"
   }

   if {$mjd == 0} { set mjd [mjd4Gang] }

   if ![file exists $file] {
      if {$mjd < 0 && ![regexp {^[0-9]+$} $file foo]} {
	 error "I cannot find a file called $file"
      }

      if {$mjd <= 0} {
	 set mjd $file
      }
      set file "/mcptpm/$mjd/mcpFiducials-$mjd.dat"

      if ![file exists $file] {
	 error "I cannot find a fiducials file for MJD $mjd ($file)"
      }
   }

   set fd [open $file "r"]

   if {$outfile == "" || $outfile == "stdout"} {
      set ofd stdout
   } else {
      if [catch {set ofd [open $outfile "w"]} msg] {
	 close $fd
	 return -code error -errorinfo $msg
      }
   }
   #
   # Finally, to work
   #
   while {[gets $fd line] >= 0} {
      regsub {INSTRUMENT} $line {ROTATOR} line;# fixed after mcp v5_8_6
      
      if [regexp {^[^ ]+ ([0-9]+) } $line {} t] {
	 regsub {^([^ ]+ )([0-9]+) } $line {\1} line
	 if $utc {
	    set time [utclock $t]
	 } else {
	    set time [fmtclock $t "%Y-%m-%d %H:%M:%S %Z"]
	 }

	 if {$keeptime} {
	    puts -nonewline $ofd "$t | $time "
	 } else {
	    puts -nonewline $ofd "$time "
	 }
      }
      
      if {$diff &&
	  [regexp {^(ALT|AZ|ROT)_FIDUCIAL} $line] && [lindex $line 1] > 0} {
	 foreach e "1 2" {
	    set t$e [lindex $line [expr 2 + ($e-1)]]
	    set e$e [lindex $line [expr 4 + ($e-1)]]
	 }
	 puts $ofd "$line | [expr $e1 - $t1] [expr $e2 - $t2]"
	 continue
      }

      puts $ofd $line
   }
   #
   # Cleanup
   #
   if {$ofd != "stdout"} {
      close $ofd
   }
}

###############################################################################
#
# Format an mcpCmdLog nicely
#
lappend mcpHelp_procs formatMcpCmd

proc formatMcpCmd {args} {
   set keeptime 0;			# include unix time in output
   set utc 1;				# Print dates in utc?
   
   set opts \
       [list \
	    [list [info level 0] "Format an mcpCmdLog file for a human
 to read.  Specify either a filename or an MJD"] \
	    {{[file]} STRING "" file "The file to format nicely (or an mjd)"} \
	    {-mjd INTEGER -1 mjd "Desired MJD (0 => today)"} \
	    {-outfile STRING "" outfile "File to write to (default: stdout)"} \
	    {-uid STRING "" uid \
	  "Only print commands from this UID (\"TCC\" is an acceptable UID)"} \
	    {-keeptimestamp CONSTANT 1 keeptime \
		 "Include unix timestamp in output"} \
	    {-localtime CONSTANT 0 utc "Print all dates local time, not UTC"} \
	    ]

   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   if {$file == "" && $mjd < 0} {
      error "Please specify either a filename or an mjd"
   } elseif {$file != "" && $mjd >= 0} {
      error "Please specify either a filename _or_ an mjd, not both"
   }

   if {$mjd == 0} { set mjd [mjd4Gang] }

   if ![file exists $file] {
      if {$mjd < 0 && ![regexp {^[0-9]+$} $file foo]} {
	 error "I cannot find a file called $file"
      }

      if {$mjd <= 0} {
	 set mjd $file
      }
      set file "/mcptpm/$mjd/mcpCmdLog-$mjd.dat"

      if ![file exists $file] {
	 error "I cannot find a logfile for MJD $mjd ($file)"
      }
   }

   set fd [open $file "r"]

   if {$outfile == "" || $outfile == "stdout"} {
      set ofd stdout
   } else {
      if [catch {set ofd [open $outfile "w"]} msg] {
	 close $fd
	 return -code error -errorinfo $msg
      }
   }

   if {$uid == "TCC"} { set uid 0 }
   #
   # Finally, to work
   #
   while {[gets $fd line] >= 0} {
      set line [split $line ":"]

      set t [lindex $line 0]
      set who [lindex $line 1]
      set cmd [lindex $line 2]

      if {$uid != "" && $who != $uid} {
	 continue
      }

      if $utc {
	 set time [utclock $t]
      } else {
	 set time [fmtclock $t "%Y-%m-%d %H:%M:%S %Z"]
      }

      if {$keeptime} {
	 puts $ofd "$t | $time |$who| $cmd"
      } else {
	 puts $ofd "$time |$who| $cmd"
      }
   }
   #
   # Cleanup
   #
   if {$ofd != "stdout"} {
      close $ofd
   }
}

###############################################################################

set leapseconds 33

lappend mcpHelp_procs utime2sdsstime

proc utime2sdsstime {args} {
   global leapseconds

   set opts \
       [list \
	    [list [info level 0] "\
 Given a unix time, return the time since midnight TAI,
 i.e. the MCP's sdss_time.  See also sdsstime2utime

 N.b. sdsstime2utime \[mjd4Gang\] \[utime2sdsstime \$TIME\] == \$TIME
 "] \
	    {<utime> DOUBLE 0.0 utime "Time since 1 Jan 1970 (UTC)"} \
	    ]

   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   set unixTime0 [tstampNew 1970 1 1 0 0 0]

   set midnight [tstampNow]
   handleSet $midnight.hour   0
   handleSet $midnight.minute 0
   handleSet $midnight.second 0

   set sdsstime [expr $utime - [deltaTstamp $midnight $unixTime0]]

   tstampDel $unixTime0; tstampDel $midnight

   return [format %.2f [expr $sdsstime + $leapseconds]]
}

###############################################################################

lappend mcpHelp_procs murmur2utime
lappend mcpHelp_procs murmurToClock

alias murmurToClock murmur2utime

proc murmur2utime {args} {
   global leapseconds
   
   set opts \
       [list \
	    [list [info level 0] "\
 Given an time from a murmur log, return the unixtime (since 1 Jan 1970)"] \
	    {<month> STRING "" month "Month (e.g. Nov)"} \
	    {<day> STRING "" day "Day (e.g. 06)"} \
	    {<hms> STRING "" hms "hr:min:sec (e.g. 03:48:50)"} \
	    ]

   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   set date [exec date]
   set TZ [lindex $date 4]
   set year [lindex $date 5]

   set tstamp [convertToTstamp "$month $day $hms $TZ $year"]
   set utime [tstampToClock $tstamp]
   tstampDel $tstamp

   return $utime
}

############################################################################### 
lappend mcpHelp_procs clockToMjd

proc clockToMjd {args} {
   set opts \
       [list \
	    [list [info level 0] "\
 Given a unix time (seconds since since 1 Jan 1970), return the MJD"] \
	    {<clock> DOUBLE 0.0 clock \
		 "unixtime, as returned by e.g. getclock"} \
	    ]

   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   set tstamp [clockToTstamp $clock]
   set mjd [expr int([tstampToMJD $tstamp])]
   tstampDel $tstamp

   return $mjd
}

###############################################################################

lappend mcpHelp_procs sdsstime2utime

proc sdsstime2utime {args} {
   global leapseconds
   
   set opts \
       [list \
	    [list [info level 0] "\
 Given an sdss_time (as used by the MCP) and an MJD, return the
 unixtime (since 1 Jan 1970) corresponding to that sdss_time.

 N.b. sdsstime2utime \[mjd4Gang\] \[utime2sdsstime \$TIME\] == \$TIME
 "] \
	    {<mjd> INTEGER 0 mjd "MJD when sdss_time was measured"} \
	    {<sdss_time> DOUBLE 0.0 sdss_time "Time since midnight (TAI)"} \
	    ]

   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   set unixTime0 [tstampNew 1970 1 1 0 0 0]

   set tstamp [tstampFromMJD [expr int($mjd) + $sdss_time/(24.0*3600)]]
   set utime [deltaTstamp $tstamp $unixTime0]

   tstampDel $unixTime0

   return [format %.2f [expr $utime - $leapseconds]]
}

###############################################################################

lappend mcpHelp_procs TAI2Utime
lappend mcpHelp_procs tai2Utime

alias tai2Utime TAI2Utime

proc TAI2Utime {args} {
   set opts \
       [list \
	    [list [info level 0] "\
 Convert a time in TAI seconds (as provided by the TCC) to unix time"] \
	    {<tai> DOUBLE 0 tai "TAI time in seconds"} \
	    ]

   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   if ![regexp {\.} $tai] {
      append tai ".0"
   }

   set utime [expr  $tai - 3506716835.0 + 0.5]
   regsub {\.5$} $utime "" utime;	# can overflow TCL ints

   return $utime
}

###############################################################################
#
# perform ftclHelpDefine's on all procs lappended to mcpHelp_procs
#
set_ftclHelp iop mcpHelp_procs
