#------------------------------------------------------------------------------
#
# Informational/Internal/Status Globals defined and used in this file - 
# the user should not set any of these - she can read them however.
#

#------------------------------------------------------------------------------
#
# Globals defined and used in this file
#

#------------------------------------------------------------------------------
#
# Other Globals used in this file
#

global verbose;              
if {![info exists verbose]}               { set verbose 0 }
# global after_XXXXX - for each job in the event loop
# global XXXXXDelay  - for each job in the event loop


#------------------------------------------------------------------------------
#
# THIS IS THE PROTO-TYPICAL METHOD/STRUCTURE FOR PUTTING JOBS INTO 
# THE EVENT LOOP:  USE IT!!!!!!!
#
# The Structure that I've found works well is:
#    Let XXXXX =  name of your proc in the event loop
#        then you need a global variable  after_XXXXX that contains the 
#	 return value from the after command that put it in the event loop
#        and  you need a global variable  XXXXXDelay  that contains the time, 
#	 in milliseconds, period between invocations of your proc
#    To remove things from the event loop:
#        You can use zap1After XXXXX
#        or  set XXXXXDelay to 0
#    This structure is illustrated in the proc jobs, below.
#
# In principle, one can make a proc that invokes this structure for the user 
# automatically.   
#				Jon Bakken, 1997
#
# Robert Lupton implemented such a proc, which he named "schedule".
#

#------------------------------------------------------------------------------
#
# Robert Lupton's scheduler implementation of the after method 
#
#  if you have a proc foo that expects a scalar and a list as arguments,
#  and it should be run every 5s, you could say:
#
#       schedule foo "abcd {1 2}" 5
#
# to cancel it, use 
#
#       schedule foo "" 0
#
# The command
#	schedule list
# will list all scheduled tasks (schedule list will be more verbose);
#	schedule list task [quiet]
# returns that task's arguments and interval; if quiet is specified nothing is
# printed and 1/0 is returned according to whether the task is/isn't scheduled
#
proc schedule {procname {args ""} {delay 0}} {
    global after_$procname ${procname}Delay verbose scheduled
    global show_scheduled_errors

    if {$procname == "list"} {
       if {$args != ""} {
	  set cmd $args; global ${cmd}Delay
	  if {![info exists scheduled($cmd)] || ![info exists ${cmd}Delay]} {
	     if !$delay {	
		echo "Command $cmd is not currently scheduled"
	     }
	     return 0
	  }
	  if $delay {
	     return 1
	  } else {
	     return [list $scheduled($cmd) [expr 0.001*[set ${cmd}Delay]]]
	  }
       }
       
       if {$delay != 0} {
	  error "You cannot specify a delay with schedule list"
       }
	  
       set fmt "%-30s  %-30s  %4s"
       puts [format $fmt "command" "arguments" "interval (s)"]
       puts [format $fmt "-------" "---------" "------------"]

       foreach cmd [lsort [array names scheduled]] {
	  global ${cmd}Delay
	  
	  set arg [string trimleft $scheduled($cmd)]
	  if {"$arg" == ""} {
	     set arg "{}"
	  }

	  if {[string length $arg] > 30} {# insert some newlines
	     set alist [split $arg " "]
	     set arg ""; set line ""
	     loop i 0 [llength $alist] {
		if {[string length "$line"] > 30} {
		   append arg "$line\\\n[format [lindex $fmt 0] {}]         ";
		   set line ""
		}
		append line "[lindex $alist $i] "
	     }
	     append arg "$line"
	  }

	  puts [format $fmt  $cmd $arg \
		    [format "%.1f" [expr 0.001*[set ${cmd}Delay]]]]
       }
       if [info exists show_scheduled_errors] {
	  echo; echo "Errors will be popped up"
       } else {
	  echo; echo "Variable show_scheduled_errors is not set"
       }
       return
    }

    if {$delay < 0 && [set ${procname}Delay] != [expr -$delay*1000]} {
        # someone has set the delay to 0, so stop $procname
        set delay [set ${procname}Delay]
    }
    if {$delay > 3000} { echo "scheduler: delay is $delay, in seconds" }

    if {$delay >= 0} {
        set ${procname}Delay [expr int($delay*1000)]

        zap1After after_$procname;      # if we already have in event loop,
        # delete it. One is enough
        if {$delay == 0} {
            murmur  "Stopping $procname"
	    if [info exists after_$procname] {unset after_$procname}
	    if [info exists scheduled($procname)] {unset scheduled($procname)}

            return 0
        } else {
            murmur  "Starting $procname"
        }
    }

    # do the work. Trap errors: the first time around, send error message 
    # to screen; otherwise only do so if show_scheduled_errors is set
    if {$delay < 0 || [info exists show_scheduled_errors]} {
        if [catch {eval $procname $args} msg] {
            murmur $msg
	   if [info exists show_scheduled_errors] {
	      tkerror "Error from scheduled job $procname in process [pid]: $msg"
	   }
        }
    } else {
        if [catch {eval $procname $args} msg] {
            murmur $msg
	    echo $msg
	    global errorInfo
	    echo $errorInfo
	    echo "$procname is scheduled, further errors sent to murmur"
        }
    }

    # reschedule this proc, i.e. put it back into the event loop.
    # A negative delay means that this is a re-schedule, so no messages
    # should be printed
    if {$delay > 0} {
       if 0 {
	   murmur [format "Next $procname event loop pending in %d ms at %s" \
		       [set ${procname}Delay] exec deltaDate [set ${procname}Delay]]
        }
        set delay [expr -$delay]
        set scheduled($procname) $args;	# this is solely to allow use to list
       					# scheduled commands with their args
    }

    set after_$procname \
	[after [set ${procname}Delay] \
	     [list schedule $procname "$args" $delay]]

    return 0
}

#------------------------------------------------------------------------------
#
alias jobs "schedule list"
#
#------------------------------------------------------------------------------
#
# deletes all after commands with the after_XXX syntax/structure
#
proc zapAfters { } {
    foreach scheduled [info global after*] { zap1After $scheduled }
    return 0
}

#------------------------------------------------------------------------------
#
# deletes the specified after command in the event loop.
#
proc zap1After { scheduled } {
    global verbose

    # 1st try the actual parameter specified
    global $scheduled
    if {[info exists $scheduled]} {
        if {[string length $scheduled]} {
            #murmur "Cancelling event loop: uplevel 0 after cancel [set $scheduled]"
            uplevel 0 after cancel [set $scheduled]
        }
        uplevel 0 unset $scheduled
        return 0
    }

    # Now try putting after_  before what was specified
    set scheduled "after_$scheduled"
    global $scheduled
    if {[info exists $scheduled]} {
        if {[string length $scheduled]} {
            #murmur "Cancelling event loop: uplevel 0 after cancel [set $scheduled]"
            uplevel 0 after cancel [set $scheduled]
        }
        uplevel 0 unset $scheduled
        return 0
    }

    # Nothing to delete, but that is not really an error condition
    regsub {after_after_} $scheduled "" name
    murmur "Can not find $name in the event loop, so can not delete it"
    return 0
}
