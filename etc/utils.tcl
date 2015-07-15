set verbose 0

proc murmur {args} {
   global verbose
   if $verbose {
      puts "Murmur: [join $args]"
   }
}

proc mcpopVersion {} {
   return "???"
}

#
# Things we can fake
#
proc dp_connect_safe {args} {
   return [eval dp_connect $args]
}

proc alias {newCmd args} {
   set body [join $args]
   uplevel 1 "proc $newCmd \{args\} \{$body \$args\}"
}

proc select {args} {
   return [eval mySelect $args]
}

proc echo {args} {
   puts [join $args]
}

proc set_ftclHelp {progName _procNames} {
   upvar $_procNames procNames
   
   if 0 {
      puts $procNames
   }
}

proc shTclParseArg {args opts procName} {
   #
   # Simulate dervish's shTclParseArg
   #

   #
   # Parse opts into a dict, and the list of required arguments into a list
   #
   set argList [list ]
   foreach o $opts {
      if {[llength $o] == 5} {
	 set v0 [lindex $o 0]
	 if [regexp {^<} $v0] {
	    lappend argList [lrange $o 1 3]
	 } elseif [regexp {^\[} $v0] {
	    lappend argList [lrange $o 1 3]

	    set tdv [lindex $argList end]

	    set type [lindex $tdv 0]
	    set val [lindex $tdv 1]
	    set var [lindex $tdv 2]

	    uplevel 1 [list set $var $val]
	 } else {
	    set optDict($v0) [lrange $o 1 3]

	    set type [lindex $optDict($v0) 0]
	    set val [lindex $optDict($v0) 1]
	    set var [lindex $optDict($v0) 2]

	    if {$type != "CONSTANT"} {
	       uplevel 1 [list set $var "$val"]
	    }
	 }
      }
   }
   #
   # Process the arguments, parsing them according to opts
   #
   while {[llength $args]} {
      set a [lindex $args 0]
      set args [lrange $args 1 end]

      if [info exists optDict($a)] {
	 set tdv $optDict($a)
      } else {
	 set tdv [lindex $argList 0]
	 set argList [lrange $argList 1 end]

	 set tdv [list "CONSTANT" $a [lindex $tdv 2]]
      }

      set type [lindex $tdv 0]
      set default [lindex $tdv 1]
      set var [lindex $tdv 2]

      if {$type == "CONSTANT"} {
	 set val $default
      } else {
	 set val [lindex $args 0]
	 set args [lrange $args 1 end]
      }
      
      uplevel 1 [list set $var $val]
   }

   return 1
}

proc promptSet {val} {
}

proc setWindowTitle {val} {
}

proc keylset {_x field value} {
   upvar $_x x

   if ![info exists x] {
      set x [list]
   }

   set i -1
   foreach ll $x {
      incr i
      if {[lindex $ll 0] == "$field"} {
	 set x [lreplace $x $i $i [list $field $value]]
	 return
      }
   }
   
   lappend x [list $field $value]
}

proc keylget {_x field {var "_none_"}} {
   upvar $_x x

   foreach ll $x {
      if {[lindex $ll 0] == "$field"} {
	 set val [lindex $ll 1]
	 break
      }
   }

   if [info exists val] {		# it exists
      if {$var == "_none_"} {
	 return $val
      } else {
	 if {$var != {}} {
	    uplevel 1 [list set $var $val]
	 }
	 return 1
      }
   } else {
      if {$var == "_none_"} {
	 $val				# will raise an exception
      } else {
	 return 0
      }
   }
}

proc depress {w} {
   set state [$w cget -relief]
   $w configure -relief sunken
   update; after 100
   $w configure -relief $state
}
