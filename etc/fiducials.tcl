#
# Analyse mcpFiducials-mjd.dat logs
#
lappend fiducialHelp_procs plotMcpFiducials

alias readMcpFiducials plotMcpFiducials

proc plotMcpFiducials {args} {
   global pg

   set absolute 0; set canonical 0; set error 0; set reset 0;
   set scale 0; set updown 0
   set ms 0
   set read_old_mcpFiducials 0;		# read old-style files
   set verbose 0
   set az 0; set alt 0; set rot 0;

   set sargs $args;			# save initial values

   set opts \
       [list \
	    [list [info level 0] "Read and analyze an mcpFiducials file
 e.g.
 plotMcpFiducials -mjd 51799 \\
       -alt -y pos1 -x time -reset -canon -updown -table stdout
 "] \
	    {{[file]} STRING "" file "The mcpFiducials file to read"} \
	    {-az CONSTANT 1 az "Read azimuth data"} \
	    {-alt CONSTANT 1 alt "Read altitude data"} \
	    {-rot CONSTANT 1 rot "Read rotator data"} \
	    [list -mjd INTEGER [mjd4Gang] mjd \
		 "Read mcpFiducials file for this MJD"] \
	    {-dir STRING "/mcptpm/%d" mjd_dir_fmt \
		 "Directory to search for \$file, maybe taking MJD as an argument"} \
	    {-index0 INTEGER 0 index0 \
	       "Ignore all data in the mcpFiducials file with index < index0"}\
	    {-index1 INTEGER 0 index1 \
	       "Ignore all data in the mcpFiducials file with index > index0"}\
	    {-time0 STRING 0 time0 \
	 "Ignore all data in the mcpFiducials file older than this timestamp;
 If less than starting time, interpret as starting time + |time0|.
 See also -index0"} \
	    {-time1 STRING 0 time1 \
	 "Ignore all data in the mcpFiducials file younger than this timestamp;
 If less than starting time, interpret as starting time + |time1|.
 See also -index1"} \
	    {-canonical CONSTANT 1 canonical \
		 "Set the `canonical' fiducial to its canonical value"} \
	    {-setCanonical STRING "" setCanonical \
  "Specify the canonical fiducial and optionally position,
     e.g. -setCanonical 78
          -setCanonical 78:168185
 "}\
	    {-error CONSTANT 1 error \
		 "Plot error between true and observed fiducial positions"} \
	    {-errormax DOUBLE 0 errormax \
 "Ignore errors between true and observed fiducial positions larger than <max>"} \
	    {-reset CONSTANT 1 reset \
	 "Reset fiducials every time we recross the first one in the file?"} \
	    {-scale CONSTANT 1 scale \
 "Calculate the scale and ensure that it's the same for all fiducial pairs?"} \
	    {-absolute CONSTANT 1 absolute \
	 "Plot the values of the encoder, not the scatter about the mean"} \
	    {-updown CONSTANT 1 updown \
		 "Analyze the `up' and `down' crossings separately"}\
	    {-x STRING "" xvec "Vector to use on x-axis (no plot if omitted)"}\
	    {-y STRING "" yvec "Vector to use on y-axis"} \
	    {-fiducialfile STRING "" fiducial_file \
		 "Read true positions of fiducials from this file rather
 than using the values in the mcpFiducials file.
 Filename may be a format, in which case %s will be replaced by e.g. \"rot\".
 If you prefer, you may simple specify an MCP version number.\
 "} \
	    {-ms CONSTANT 1 ms "Show MS actions (must have -xvec time)"} \
	    {-plotfile STRING "" plot_file "Write plot to this file.
 If the filename is given as \"file\", a name will be chosen for you."} \
	    {-tablefile STRING "" table_file \
		 "Write fiducials table to this file (may be \"stdout\")"} \
	    {-verbose CONSTANT 1 verbose "Be chatty?"} \
	    {-read_old_mcpFiducials CONSTANT 1 read_old_mcpFiducials \
		 "Read old mcpFiducial files (without encoder2 info)?"} \

	    ]

   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }
   #
   # Check that flags make sense
   #
   if $error {
      if $canonical {
	 error "Please don't specify -canonical with -error"
      }
      if $reset {
	 error "Please don't specify -reset with -error"
      }
      if $updown {
	 error "Please don't specify -updown with -error"
      }
      if {$table_file != ""} {
	 error "Please don't specify e.g. -table with -error"
      }
   } else {
      if {$fiducial_file != "" && $setCanonical != ""} {
	 error \
	     "-fiducialfile only makes sense with -error or without -setCanon"
      }
   }

   if {$setCanonical != ""} {
      if ![regexp {^([0-9]+)(:([0-9]+))?$} $setCanonical {} ff {} ffval] {
	 error "Invalid -setCanonical argument: $setCanonical"
      }
      if {$ffval == ""} {		# grrr tcl grrr. Why is it set at all?
	 unset ffval
      }
   }

   if $scale {
      if !$absolute {
	 if $verbose {
	    echo "-scale only makes sense with -absolute; I'll set it for you"
	 }
	 set absolute 1
      }
   }
   #
   # Check the time[01] values.  They were read as STRING so that
   # floating point formats are permitted, but DOUBLE doesn't have
   # enough precision for the number of seconds since 1 Jan 1970
   #
   loop i 0 2 {
      if {![regexp {^[+-]?[0-9]+$} [set time$i]] &&
	  ![regexp {^[+-]?[0-9]*\.[0-9]*([Ee][+-]?[0-9]+)?$} [set time$i]]} {
	 error "-time$i must specify a number (saw [set time$i])"
      }
   }
   #
   # Which axis are we interested in?
   #
   if {$az + $alt + $rot == 0} {
      error "Please specify an axis"
   } elseif {$az + $alt + $rot > 1} {
      error "Please specify only one axis"
   }
   
   set axis_scale1 0; set axis_scale2 0
   if $alt {
      set axis "altitude"
      set struct ALT_FIDUCIAL
      set names [list time fididx pos1 pos2 deg alt_pos velocity]
   }
   if $az {
      set axis "azimuth"
      set struct AZ_FIDUCIAL
      set names [list time fididx pos1 pos2 deg velocity]
   }
   if $rot {
      set axis "rotator"
      set struct ROT_FIDUCIAL
      set names [list time fididx pos1 pos2 deg latch velocity]
   }

   if $read_old_mcpFiducials {
      lappend names true
   } else {
      lappend names true1; lappend names true2
   }
   #
   # Find the desired file
   #
   if {$file == ""} {
      set file [format mcpFiducials-%d.dat $mjd]
   } else {
      if {$mjd != [mjd4Gang]} {
	 error "You may not specify \[file\] and -mjd"
      }
   }
   
   if [file exists $file] {	# OK, found it
      set dfile $file;
   } else {
      if [regexp {%d} $mjd_dir_fmt] {# need the MJD
	 if ![regexp {mcpFiducials-([0-9]+)\.dat} $file foo mjd] {
	    error \
		"I cannot find a file called $file, and I cannot parse it for an mjd"
	 }
      }
      
      set dir [format $mjd_dir_fmt $mjd]
      
      set dfile $dir/$file
      if ![file exists $dfile] {
	 error "I cannot find $file in . or $dir"
      }
   }

   if $verbose {
      echo File: $dfile
   }
   #
   # Check that the requested vectors exist
   #
   if {$xvec != "" && $yvec == ""} {
      set yvec pos1
   }
   if {$xvec != "" && [lsearch $names $xvec] < 0} {
      if {$xvec == "i"} {		# plot against the index
	 set xvec index
      }

      if {$xvec != "index"} {
	 error "There is no vector $xvec in the file"
      }
   }
   if {$yvec != "" && [lsearch $names $yvec] < 0} {
      error "There is no vector $yvec in the file"
   }
   #
   # What are the canonical values of the fiducials?
   #
   if ![info exists ffval] {		# not specified via -setCanonical
      if $az {
	 if ![info exists ff] {
	    set ff 19
	 }
	 set ffval 31016188
      } elseif $alt {
	 if ![info exists ff] {
	    set ff 1
	 }
	 set ffval 3825222
      } else {
	 if ![info exists ff] {
	    set ff 78
	 }
	 set ffval 168185
      }

      if {$fiducial_file == ""} {
	 set ffile "/p/mcpbase/fiducial-tables/%s.dat"
      } else {
	 set ffile $fiducial_file
      }
      if [catch {read_fiducials ffile $axis vecs header} msg] {
	 error "Failed to read $ffile for canonical fiducial: $msg"
      } else {
	 if {$ff != $header(Canonical fiducial)} {
	    error "You may only use -setCanonical $ff if $ff is the canonical fiducial in $ffile"
	 }

	 set tmp [vectorExprEval \
		      "[keylget vecs p1] if([keylget vecs findex] == $ff)"]
	 set ffval [vectorExprGet $tmp]
	 vectorExprDel $tmp; unset tmp

	 echo "Using canonical position $ffval for fiducial $ff from $ffile"

	 foreach p "findex p1 p2" {
	    vectorExprDel [keylget vecs $p]
	    keyldel vecs $p
	 }
      }
   }
   #
   # Workaround dervish bug: the -struct flag appears to fail
   #
   if [catch { schemaGetFromType $struct }] {
      set vecs [param2Vectors $dfile "" hdr]
   }
   
   set vecs [param2Vectors $dfile $names hdr -type $struct]
   if $verbose {
      echo Vectors: [keylget vecs]
   }
   keylset vecs tmp [vectorExprNew 1]
   keylset vecs tmp2 [vectorExprNew 1]
   #
   # remove vectors that weren't read
   #
   set _names $names; unset names
   foreach v $_names {
      if [keylget vecs $v foo] {
	 lappend names $v
      }
   }
   unset _names

   foreach v [keylget vecs] {
      set $v [keylget vecs $v]
   }
   #
   # Discard early data if so directed
   #
   set tmod 10000
   set tbase [vectorExprGet $tmod*int($time<0>/$tmod)]

   if {$time0 != 0 && $time0 < [vectorExprGet $time<0>]} {
      set time0 [expr $tbase + abs($time0)]
   }
   if {$time1 != 0 && $time1 < [vectorExprGet $time<0>]} {
      set time1 [expr $tbase + abs($time1)]
   }

   if {$time0 != 0 || $time1 != 0 || $index0 != 0 || $index1 != 0} {
      if {$time0 != 0 || $time1 != 0} {
	 if {$index0 != 0 || $index1 != 0} {
	    echo "Ignoring -index\[01\] in favour of -time\[01\]"
	 }

	 if {$time0 == 0} {
	    set time0 [vectorExprGet $time<0>]
	 }
	 if {$time1 == 0} {
	    set time1 [vectorExprGet $time<dimen($time)-1>]
	 }
	 
	 vectorExprSet $tmp "($time >= $time0 && $time <= $time1) ? 1 : 0"
      } else {
	 set index [vectorExprEval (0,dimen([lindex [lindex $vecs 0] 1])-1)]
	 keylset vecs index $index

	 if {$index0 < 0} {
	    set index0 0
	 }
	 
	 if {$index1 == 0 || $index1 >= [vectorExprGet dimen($time)]} {
	    set index1 [vectorExprGet dimen($time)-1]
	 }

	 vectorExprSet $tmp "($index >= $index0 && $index <= $index1) ? 1 : 0"
      }
      foreach v [keylget vecs] {
	 if ![regexp {tmp} $v] {
	    vectorExprSet [set $v] "[set $v] if($tmp)"
	 }
      }
   }
   #
   # Are there any datavalues left?
   #
   if {[vectorExprGet dimen($time)] == 0} {
      foreach v [keylget vecs] {
	 set v [keylget vecs $v]
	 vectorExprDel $v
      }
      
      error "You haven't asked for any points"
   }
   #
   # Reduce time to some readable value
   #
   vectorExprSet $time "$time - $tbase"
   #
   # Discard the non-mark rotator fiducials
   #
   if $rot {
      vectorExprSet $tmp "($fididx > 0 ? 1 : 0)"
      foreach v $names {
	 vectorExprSet [set $v] "[set $v] if($tmp)"
      }
   }

   if $verbose {
      make_fiducials_vector $fididx $tmp 0
      echo "Fiducials crossed:"; vectorExprPrint $tmp
   }
   #
   # If we want to analyse the `up' and `down' fiducials separately,
   # add $ud_delta to fididx for all crossings with -ve velocity
   #
   if $updown {
      set ud_delta [expr [vExtreme $fididx max] + 5]
      vectorExprSet $fididx "$fididx + ($velocity < 0 ? $ud_delta : 0)"
   } else {
      set ud_delta 0
   }
   #
   # Process fiducial data
   # Start by finding the names of all fiducials crossed
   #
   set fiducials [make_fiducials_vector $fididx]
   keylset vecs fiducials $fiducials
   #
   # Find the approximate position of each fiducial (in degrees)
   #
   set fiducials_deg [vectorExprEval "0*$fiducials - 1000"]
   keylset vecs fiducials_deg $fiducials_deg
   
   loop i 0 [vectorExprGet dimen($fiducials)] {
      vectorExprSet $tmp "$deg if($fididx == $fiducials<$i>)"
      if {[vectorExprGet dimen($tmp)] > 0} {
	 handleSet $fiducials_deg.vec<$i> [vectorExprGet $tmp<0>]
      }
   }

   if $verbose {
      loop i 0 [vectorExprGet dimen($fiducials)] {
	 if {[vectorExprGet $fiducials_deg<$i>] < -999} {# missing
	    continue;
	 }

	 echo [format "%3d %8.3f" \
		   [vectorExprGet $fiducials<$i>] \
		   [vectorExprGet $fiducials_deg<$i>]]
      }
   }
   #
   # Unless we just want to see the fiducial errors (-error), estimate
   # the mean of each fiducial value
   #
   foreach i "1 2" {
      set fpos$i [vectorExprEval 0*$fiducials]
      keylset vecs fpos$i [set fpos$i]
   }

   if {$error && ![regexp {^pos([12])} $yvec foo n]} {
      echo \
	  "Please specify \"-y pos\[12\]\" along with -error; ignoring -error"
      set error 0
   }
   if $error {
      #
      # Read the fiducial file if provided
      #
      if {$fiducial_file != ""} {
	 read_fiducials fiducial_file $axis vecs

	 foreach n "1 2" {
	    #
	    # Set fpos[12] from those fiducial positions
	    #
	    loop i 0 [vectorExprGet dimen($fiducials)] {
	       vectorExprSet $tmp \
		   "[keylget vecs p$n] if([keylget vecs findex] == $fiducials<$i>)"
	       if {[vectorExprGet dimen($tmp)] > 0} {
		  handleSet [set fpos$n].vec<$i> [vectorExprGet $tmp<0>]
	       }
	    }
	 }
      } else {
	 #
	 # Find the true value for each fiducial we've crossed
	 #
	 if $read_old_mcpFiducials {
	    set true1 $true
	 }
	 loop i 0 [vectorExprGet dimen($fiducials)] {
	    vectorExprSet $tmp2 "$true1 if($fididx == $fiducials<$i>)"
	    if {[vectorExprGet dimen($tmp2)] > 0} {
	       handleSet $fpos1.vec<$i> [vectorExprGet $tmp2<0>]
	    }
	 }
	 vectorExprSet $fpos2 $fpos1
      }

      if 0 {
	 loop i 0 [vectorExprGet dimen($fiducials)] {
	    echo [format "%d %d" [vectorExprGet $fiducials<$i>] \
		      [vectorExprGet [set f$yvec]<$i>]]
	 }
      }	 
   } else {
      #
      # Reset the encoders every time that they pass some `fiducial' fiducial?
      #
      if $reset {
	 foreach i "1 2" {
	    reset_fiducials $fididx $ud_delta $velocity [set pos$i] \
		[expr $i==1 ? $verbose : 0]
	 }
      }
      #
      # Calculate mean values of pos[12]
      #
      if $updown {
	 foreach j "1 2" {
	    set pos${j}0 [vectorExprEval [set pos$j]];# save pos$j
	    
	    loop i 0 [vectorExprGet dimen($fiducials)] {
	       vectorExprSet $tmp "[set pos$j] if($fididx == $fiducials<$i>)"
	       if {[vectorExprGet dimen($tmp)] > 0} {
		  handleSet [set fpos$j].vec<$i> \
		      [vectorExprGet sum($tmp)/dimen($tmp)]
	       }
	    }
	    vectorExprSet $tmp2 \
		"$fididx  + ($fididx < $ud_delta ? $ud_delta : -$ud_delta)"
	    #
	    # There's a memory management bug in dervish's vectors;
	    # the if 0 {} code triggers it.
	    #
	    vectorExprSet $tmp "[set fpos$j]<$fididx> + [set fpos$j]<$tmp2>"
	    if 0 {
	       vectorExprSet $tmp \
  "$tmp/(([set fpos$j]<$fididx> != 0 || [set fpos$j]<$tmp2> != 0) ? 1.0 : 2.0)"
	    } else {
	       vectorExprSet $tmp \
	     "$tmp/(([set fpos$j]<$fididx> != 0) + ([set fpos$j]<$tmp2> != 0))"
	    }
	    
	    vectorExprSet [set pos$j] \
		"[set pos$j] - ([set fpos$j]<$fididx> - $tmp)"
	 }
	 #
	 # Undo that +$ud_delta
	 #
	 vectorExprSet $fididx \
	     "$fididx - ($fididx > $ud_delta ? $ud_delta : 0)"
	 
	 make_fiducials_vector $fididx $fiducials
	 
	 foreach j "1 2" {
	    vectorExprSet [set fpos$j] 0*$fiducials;# resize fpos$j
	 }
      }
      #
      # (Re)calculate fpos[12] --- `Re' if $updown was true
      #
      foreach _v "fposErr nfpos" {
	 foreach i "1 2" {
	    set v ${_v}$i
	    set $v [vectorExprEval 0*$fiducials]
	    keylset vecs $v [set $v]
	 }
      }
      
      loop i 0 [vectorExprGet dimen($fiducials)] {
	 foreach j "1 2" {
	    vectorExprSet $tmp "[set pos$j] if($fididx == $fiducials<$i>)"
	    if {[vectorExprGet dimen($tmp)] == 0} {
	       handleSet [set fposErr$j].vec<$i> -9999;# disable fiducial
	    } else {
	       handleSet [set fpos$j].vec<$i> \
		   [vectorExprGet sum($tmp)/dimen($tmp)]
	       
	       handleSet [set nfpos$j].vec<$i> [vectorExprGet dimen($tmp)]
	       handleSet [set fposErr$j].vec<$i> \
		   [vectorExprGet "dimen($tmp) == 1 ? 10^10 : \
		     sqrt((sum($tmp^2)/dimen($tmp) - [set fpos$j]<$i>^2)/(dimen($tmp)-1))"]
	    }
	 }
      }
      
      if $updown {				# restore values
	 foreach j "1 2" {
	    set p0 [set pos${j}0]
	    vectorExprSet [set pos$j] $p0
	    vectorExprDel $p0
	 }
      }
   }
   if !$absolute {
      vectorExprSet $pos1 "$pos1 - $fpos1<$fididx>" 
      vectorExprSet $pos2 "$pos2 - $fpos2<$fididx>"
   }
   #
   # If the axis wraps, ensure that pairs of fiducials seen 360 degrees
   # apart are always separated by the same amount -- i.e. estimate
   # the axis' scale
   #
   if $scale {
      if ![keylget vecs index foo] {
	 set index [vectorExprEval (0,dimen($deg)-1)]
	 keylset vecs index $index
      }

      foreach n "1 2" {
	 set diff 0.0; set ndiff 0
	 loop i 0 [vectorExprGet dimen($fiducials)] {
	    if {[vectorExprGet $fiducials_deg<$i>] < -999} {# missing
	       continue;
	    }
	    
	    vectorExprSet $tmp "$fiducials if(abs($fiducials_deg - 360 - $fiducials_deg<$i>) < 1)"
	    if {[vectorExprGet dimen($tmp)] <= 0} {
	       continue;			# we were only here once
	    }
	    
	    set match($i) [vectorExprGet $tmp<0>]
	    
	    vectorExprSet $tmp "[set pos$n] if($fididx == $fiducials<$i>)"
	    if {[vectorExprGet dimen($tmp)] <= 0} {
	       continue;			# we didn't cross this fiducial
	    }
	    set p1 [vectorExprGet sum($tmp)/dimen($tmp)]
	    
	    vectorExprSet $tmp "[set pos$n] if($fididx == $match($i))"
	    if {[vectorExprGet dimen($tmp)] <= 0} {
	       continue;			# we didn't cross this fiducial
	    }
	    set p2 [vectorExprGet sum($tmp)/dimen($tmp)]
	    
	    set diff [expr $diff + ($p2 - $p1)]
	    incr ndiff
	    
	    if $verbose {
	       echo [format "%3d %8.3f %10.3f" \
			 [vectorExprGet $fiducials<$i>] \
			 [vectorExprGet $fiducials_deg<$i>] [expr $p2 - $p1]]
	    }
	 }
	 if {$ndiff == 0} {
	    if {$n == 1 && !$alt} {
	       echo "You haven't moved a full 360degrees, so I cannot find the scale"
	    }

	    loop i 0 [vectorExprGet dimen($fiducials)] {
	       if {[vectorExprGet [set nfpos$n]<$i>] > 0} {
		  set v0 [vectorExprGet [set fpos$n]<$i>]
		  set deg0 [vectorExprGet $fiducials_deg<$i>]
		  break;
	       }
	    }
	    loop i [vectorExprGet "dimen($fiducials) - 1"] -1 -1 {
	       if {[vectorExprGet [set nfpos$n]<$i>] > 0} {
		  set v1 [vectorExprGet [set fpos$n]<$i>]
		  set deg1 [vectorExprGet $fiducials_deg<$i>]
		  break;
	       }
	    }

	    set axis_scale$n [expr 1.0/($v0 - $v1)];# n.b. -ve; not a real scale
	    echo [format "$axis scale APPROX %.6f  (encoder $n)" \
		      [expr (60*60*($deg0 - $deg1))*[set axis_scale$n]]]
	 } else {
	    set diff [expr $diff/$ndiff]
	    set axis_scale$n [expr (60*60*360.0)/$diff]
	    
	    echo $axis scale = [set axis_scale$n]  (encoder $n)

	    #
	    # Force fiducials to have that scale
	    #
	    loop i 0 [vectorExprGet dimen($fiducials)] {
	       if [info exists match($i)] {
		  set mean [vectorExprGet \
				"([set fpos$n]<$i> + [set fpos$n]<$match($i)> - $diff)/2)"]
		  handleSet [set fpos$n].vec<$i> $mean
		  handleSet [set fpos$n].vec<$match($i)> [expr $mean + $diff]
	       }
	    }
	 }
      }

      echo [format "Encoder2/Encoder1 - 1 = %.6e" \
		[expr $axis_scale2/$axis_scale1 - 1]]
   }
   #
   # Fix fiducial positions to match canonical value for some fiducial?
   #
   if $canonical {
      foreach n "1 2" {
	 if [info exists fpos$n] {
	    vectorExprSet $tmp "[set fpos$n] if($fiducials == $ff)"
	    if {[vectorExprGet dimen($tmp)] == 0 || [vectorExprGet $tmp] == 0} {
	       error "You have not crossed/successfully read canonical fiducial $ff"
	    }
	    vectorExprSet [set fpos$n] \
		"[set fpos$n] + (([set nfpos$n] == 0) ? 0 : $ffval - $tmp<0>)"
	 }
      }
   }
   #
   # Print table?
   #
   if {$table_file != ""} {
      if {$table_file == "stdout"} {
	 set fd "stdout"
      } else {
	 set fd [open $table_file "w"]
      }

      # Get a CVS Name tag w/o writing it out literally.
      set doll {$}
      set cvsname "${doll}Name${doll}"

      puts $fd "#"
      puts $fd "# $axis fiducials"
      puts $fd "#"
      puts $fd "# $cvsname"
      puts $fd "#"
      puts $fd "# Creator:             [exec whoami]"
      puts $fd "# Time:                [utclock [getclock]]"
      puts $fd "# Input file:          $dfile"
      puts $fd "# Scales:              $axis_scale1  $axis_scale2"
      puts $fd "# Canonical fiducial:  $ff"
      puts $fd "# Arguments:           $sargs"
      puts $fd "#"
      puts $fd \
	  "# Fiducial Encoder1 +- error  npoint  Encoder2 +- error  npoint"
      loop i 1 [vectorExprGet dimen($fpos1)] {
	 puts -nonewline $fd [format "%-4d " [vectorExprGet $fiducials<$i>]]
	 
	 foreach n "1 2" {
	    puts -nonewline $fd [format "    %10.0f +- %5.1f %3d" \
				     [vectorExprGet [set fpos$n]<$i>] \
				     [vectorExprGet [set fposErr$n]<$i>] \
				     [vectorExprGet [set nfpos$n]<$i>]]
	 }
	 puts $fd ""
      }
      
      if {$fd != "stdout"} {
	 close $fd
      }
   }
   #
   # Make desired plot
   #
   if {$xvec != ""} {
      #
      # Create the index vector if we need it
      #
      if {$xvec == "index"} {			# plot against the index
	 if ![keylget vecs index foo] {
	    set index [vectorExprEval (0,dimen([lindex [lindex $vecs 0] 1])-1)]
	    keylset vecs index $index
	 }
      }

      if {$ms && $xvec != "time"} {
	 echo "-ms only makes sense with -xvec time; ignoring"
	 set ms 0
      }

      if {[info exists pg] && [catch {pgstateSet $pg}]} {
	 unset pg
      }

      if {$plot_file == ""} {
	 set plot_dev "/XWINDOW"
      } else {
	 if {$plot_file == "file"} {
	    set plot_file "$axis-$xvec-$yvec"
	    if $reset {
	       append plot_file "-R"
	    }
	    if $updown {
	       append plot_file "-U"
	    }
	    append plot_file ".ps"
	 }
	 set plot_dev "$plot_file/CPS"

	 if [info exists pg] {		# we need a new one attached to a file
	    pgstateDel $pg; unset pg
	 }
      }
      
      if ![info exists pg] {
	 set pg [pgstateNew];
	 pgstateSet $pg -device $plot_dev;
	 pgstateOpen $pg; pgAsk 0;
      }

      set x [set $xvec]
      set y [set $yvec]

      if $error {
	 vectorExprSet $tmp "$fpos1<$fididx> == 0 ? 0 : 1"
	 if 0 {				# XXX
	    vectorExprSet $tmp2 "($fididx == 14) + ($fididx == 16) + ($fididx == 18) + ($fididx == 42)"
	    vectorExprSet $tmp "$tmp2 ? 0 : $tmp"
	 }

	 if {$errormax > 0} {
	    vectorExprSet $tmp "$tmp && abs($y) < $errormax"
	 }

	 set xy [list x y]
	 if {$xvec != "velocity" && $yvec != "velocity"} {
	    lappend xy velocity
	 }
	 
	 foreach v $xy {
	    vectorExprSet [set $v] "[set $v] if($tmp)"
	 }
	 
	 if 0 {				# check for sticky bits
	    loop i 0 [vectorExprGet dimen($y)] {
	       echo [format "%d 0x%x" $i [vectorExprGet abs($y<$i>)]]
	    }
	 }
      }

      set xmin [vExtreme $x min]; set xmax [vExtreme $x max]
      set ymin [vExtreme $y min]; set ymax [vExtreme $y max]
      if {$xvec == "time"} {
	 if {$time0 != 0} {
	    set xmin [expr $time0-$tbase];
	 }
	 if {$time1 != 0} {
	    set xmax [expr $time1-$tbase]
	 }
      }
      
      set ops "< >="
      loop i 0 [llength $ops] {
	 if {$i == 1} {
	    pgstateSet $pg -isNewplot 0 -icMark 2
	 } else {
	    pgstateSet $pg -isNewplot 1 -icMark 3
	 }
	 
	 set op [lindex $ops $i]
	 if {[vectorExprGet dimen($velocity)] > 0} {
	    set x [vectorExprSet $tmp  "[set $xvec] if($velocity $op 0)"]
	    set y [vectorExprSet $tmp2 "[set $yvec] if($velocity $op 0)"]
	    
	    vPlot $pg $x $y \
		-ymin $ymin -ymax $ymax -xmin $xmin -xmax $xmax
	 }
      }

      if $ms {
	 plot_ms $dfile $axis $tbase $ymin $ymax
      }

      set title "$axis"
      if $reset {  append title " -reset" }
      if $updown { append title " -updown" }
      append title ".  Red: v > 0" 
      if $ms {
	 append title "  Blue: MS.ON, Cyan: MS.OFF"
      }
      if {$fiducial_file != ""} {
	 append title "  $fiducial_file"
      }
      titlePlot $title 40
      
      if {$xvec == "time" && $tbase} {
	 if $verbose {
	    echo "Initial time on plot: [utclock [expr int($tbase + $xmin)]]"
	 }
	 xlabel "time - $tbase"
      } else {
	 xlabel "$xvec"
      }
      ylabel "$yvec"

      if {$plot_file != ""} {
	 pgstateClose $pg; pgstateDel $pg; unset pg
      }
   }
   #
   # Clean up
   #
   foreach v [keylget vecs] {
      set v [keylget vecs $v]
      vectorExprDel $v
   }
}

###############################################################################
#
# Read the positions of the fiducials for AXIS into VECS findex, p1 and p2
#
# FIDUCIAL_FILE may be a filename, or a format expecting a single string
# argument (az, alt, or rot), or an MCP version (passed by reference)
#
proc read_fiducials {_fiducial_file axis _vecs {_header ""}} {
   upvar $_fiducial_file fiducial_file $_vecs vecs
   if {$_header != ""} {
      upvar $_header header
   }
   
   switch $axis {
      "azimuth" { set a "az" }
      "altitude" { set a "alt" }
      "rotator" { set a "rot" }
   }
   
   set ffile [format $fiducial_file $a]
   if [file exists $ffile] {
      set fiducial_file $ffile
   } else {
      set ffile2 [format /p/mcp/$ffile/fiducial-tables/%s.dat $a]
      if ![file exists $ffile2] {
	 error "I can find neither $ffile nor $ffile2"
      }
      set fiducial_file $ffile2
   }
   
   if [catch { set ffd [open $fiducial_file "r"] } msg] {
      error "I cannot read $fiducial_file: $msg"
   }
   while {[gets $ffd line] >= 0} {# Skip header
      if [regexp {^\# Fiducial } $line] {
	 break
      }
      if {$_header == ""} {
	 continue
      }

      if [regexp {^\#[ 	]*([^:]+):[ 	]*(.*)} $line {} var val] {
	 if {$var == {$Name}} {
	    set var Name
	    regexp {^([^ ]+)} $val {} val
	 }

	 set header($var) $val
      }
   }

   foreach p "findex p1 p2" {
      if {![info exists vecs] || ![keylget vecs $p foo]} {
	 keylset vecs $p [vectorExprNew 1]
      }
   }

   vectorsReadFromFile $ffd [list "[keylget vecs findex] 1" \
				 "[keylget vecs p1] 2" \
				 "[keylget vecs p2] 6"]
   
   close $ffd
}

#
# Reset the position vector <pos> every time it crosses the first
# fiducial in the vector fididx
#
proc reset_fiducials {fididx ud_delta velocity pos verbose} {
   #
   # Find the indices where the velocity change sign
   #
   set tmp [vectorExprEval \
		"(0,dimen($pos)) \
               if(-$velocity<0> concat $velocity)*($velocity concat -$velocity<dimen($velocity)-1>) < 0"]
   #
   # Generate a vector with the `sweep number', incremented every time
   # the velocity changes sign
   #
   loop i 0 [vectorExprGet dimen($tmp)-1] {
      if [info exists sweep] {
	 vectorExprSet $sweep "$sweep concat $i + ($tmp<$i>,$tmp<$i+1>-1)*0"
      } else {
	 set sweep [vectorExprEval "$i + ($tmp<$i>,$tmp<$i+1>-1)*0"]
      }
   }
   
   if [vectorExprGet "dimen($sweep) < dimen($fididx)"] {
      vectorExprSet $sweep \
	  "$sweep concat $i + (dimen($sweep),dimen($fididx)-1)*0"
   }   
   #
   # Choose the fiducial that we use as a standard, resetting the
   # offset to zero whenever we see it
   #
   set ff 0; set nff 0
   loop i 0 [vectorExprGet dimen($tmp)] {
      set ff  [vectorExprGet "$ff + sum($sweep == $i ? \
	  ($fididx - ($fididx > $ud_delta ? $ud_delta : 0)) : 0)"]
      set nff [vectorExprGet "$nff + sum($sweep == $i ? 1 : 0)"]
   }
   set ff [expr int(1.0*$ff/$nff + 0.5)]; set ffval 0
   if $verbose {
      echo Resetting at fiducial $ff
   }
   #
   # Find the indices where we see the $ff fiducial
   #
   # Workaround that dervish vector bug again
   #
   if 0 {
      vectorExprSet $tmp "($fididx == $ff || $fididx == $ff + $ud_delta)"
   } else {
      vectorExprSet $tmp \
	  "($fididx == $ff) + ($fididx == $ff + $ud_delta) ? 1 : 0"
   }

   vectorExprSet $tmp "(0,dimen($pos)-1) if($tmp)"
   #
   # Generate a vector of corrections; the loop count is the number
   # of fiducial $ff crossings, not the number of fiducial crossings
   #
   loop i 0 [vectorExprGet dimen($tmp)] {
      set corrections([vectorExprGet "$sweep<$tmp<$i>>"]) \
	  [vectorExprGet "$ffval - $pos<$tmp<$i>>"]
   }
   #
   # Did any sweeps miss the `canonical' fiducials?
   #
   set nsweep [vectorExprGet "$sweep<dimen($sweep)-1> + 1"]
   loop s 0 $nsweep {
      if [info exists corrections($s)] {
	 continue;			# already got it
      }
      
      loop s0 $s -1 -1 {
	 if [info exists corrections($s0)] {
	    break;
	 }
      }
      loop s1 $s $nsweep {
	 if [info exists corrections($s1)] {
	    break;
	 }
      }
      assert {$s0 >= 0 || $s1 < $nsweep}

      if {$s0 >= 0} {
	 if {$s1 < $nsweep} {		# we have two points
	    set corrections($s) \
		[expr $corrections($s0) + 1.0*($s - $s0)/($s1 - $s0)*\
		     ($corrections($s1) - $corrections($s0))]
	 } else {
	    set corrections($s) $corrections($s0)
	 }
      } else {
	 set corrections($s) $corrections($s1)
      }
   }
   #
   # Build a corrections vector the same length as e.g. $pos
   #
   set corr [vectorExprEval "0*$pos + 1.1e10"]
   foreach s [array names corrections] {
      vectorExprSet $corr "($sweep == $s) ? $corrections($s) : $corr"
   }
   #
   # Apply those corrections
   #
   vectorExprSet $pos "$pos + $corr"
   #
   # Clean up
   #
   vectorExprDel $tmp; vectorExprDel $corr; vectorExprDel $sweep

   return $pos
}

#
# Make a vector from 0 to number of fiducials that we've seen
#
proc make_fiducials_vector {fididx {fiducials ""} {extend 1}} {
   if {$fiducials == ""} {
      set fiducials [vectorExprNew 1]
   }

   set tmp [vectorExprEval sort($fididx)]
   vectorExprSet $fiducials "($tmp concat -1) \
               if($tmp<0>-1 concat $tmp) != ($tmp concat $tmp<dimen($tmp)-1>)"
   vectorExprDel $tmp; unset tmp
   #
   # Extend the fiducials vector to start at 0?
   #
   if $extend {
      vectorExprSet $fiducials "(0,$fiducials<dimen($fiducials)-1>)"
   }

   return $fiducials
}   

###############################################################################
#
# Make all desired plot files
#
lappend fiducialHelp_procs makeMcpFiducialsPlots

proc makeMcpFiducialsPlots {args} {
   set az 0; set alt 0; set rot 0;
   set postscript 0
   
   set opts \
       [list \
	    [list [info level 0] "Make all desired fiducials plots"] \
	    {-az CONSTANT 1 az "Read azimuth data"} \
	    {-alt CONSTANT 1 alt "Read altitude data"} \
	    {-rot CONSTANT 1 rot "Read rotator data"} \
	    [list -mjd INTEGER [mjd4Gang] mjd \
		 "Read mcpFiducials file for this MJD"] \
	    {-time0 DOUBLE 0 time0 \
	 "Ignore all data in the mcpFiducials file older than this timestamp;
 If less than starting time, interpret as starting time + |time0|"} \
	    {-time1 DOUBLE 0 time1 \
	 "Ignore all data in the mcpFiducials file younger than this timestamp;
 If less than starting time, interpret as starting time + |time1|"} \
	    {-postscript CONSTANT 1 postscript "Generate postscript files"}\
	    ]

   if {[shTclParseArg $args $opts [info level 0]] == 0} {
      return 
   }

   set args [list -mjd $mjd -time0 $time0 -time1 $time1]
   if $az { lappend args -az }
   if $alt { lappend args -alt }
   if $rot { lappend args -rot }
   if $postscript { lappend args -plotfile "file" }

   foreach i "1 2" {
      foreach plot [list \
			[list time velocity {}] \
			[list time pos$i {}] \
			[list time pos$i {-updown -reset}] \
			[list fididx pos$i {-updown -reset}] \
			[list deg pos$i {-updown -reset}] \
		       ] {
	 set x [lindex $plot 0]
	 set y [lindex $plot 1]
	 set extra [lindex $plot 2]

	 if {$y == "velocity" && $i == 2} {
	    continue;
	 }
			
	 puts -nonewline "$x v. $y $extra? \[ynq\] "; set ans [gets stdin]

	 switch -regexp $ans {
	    {^[nN]} { continue; }
	    {^[qQ]} { return; }
	 }
      
	 eval plotMcpFiducials $args -x $x -y $y $extra
      }
   }
}

###############################################################################
#
# Plot MS.ON information
#
proc plot_ms {dfile axis tbase ymin ymax} {
   global pg

   set chains [param2Chain $dfile hdr]

   set x [vectorExprEval 1]; set y [vectorExprEval 1]

   foreach ch $chains {
      set nelem [chainSize $ch]
      set type [exprGet $ch.type]
      if {$nelem <= 0} {
	 continue;
      }
      
      vectorExprSet $x "0*(1,$nelem)"

      if [regexp {MS_(ON|OFF)} $type] {
	 set j -1
	 loop i 0 $nelem {
	    set el [chainElementGetByPos $ch $i]
	    if [regexp "$axis" [exprGet $el.axis]] {
	       handleSet $x.vec<[incr j]> [exprGet $el.time]
	    }
	 }

	 vectorExprSet $x "$x - $tbase if($x > 0)"
	 vectorExprSet $y "0*$x + $ymin + 0.1*($ymax - $ymin)"

	 if {$type == "MS_ON"} {
	    set icMark 4
	 } else {
	    set icMark 5
	 }

	 pgstateSet $pg -isNewplot 0 -icMark $icMark
	 vPlot $pg $x $y
      }

      chainDestroy $ch genericDel
   }

   vectorExprDel $x; vectorExprDel $y
}


###############################################################################
#
# perform ftclHelpDefine's on all procs lappended to fiducialHelp_procs
#
set_ftclHelp iop fiducialHelp_procs
