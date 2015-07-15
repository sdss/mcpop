import os
import pwd
import re
import sys
import time as pyTime
from opscore.utility import astrotime
try:
    import matplotlib.pyplot as pyplot
except ImportError:
    pyplot = None

import numpy
import yanny

def getMJD():
    """Get the MJD for the current day as an int."""
    return int(astrotime.AstroTime.now().MJD())

axisAbbrevs = dict(azimuth="az", altitude="alt", rotator="rot")

#
# Reset the position vector <pos> every time it crosses the first
# fiducial in the vector fididx
#
def reset_fiducials(fididx, ud_delta, velocity, pos, verbose):
    #
    # Find the indices where the velocity changes sign
    #
    v0 = list(v for v in velocity); v0[0:0]        = [velocity[0]]; v0 = numpy.array(v0)
    v1 = list(v for v in velocity); v1[len(v1):] = [-velocity[-1]]; v1 = numpy.array(v1)
    tmp = numpy.arange(0, len(pos) + 1)[v0*v1 < 0]
    #
    # Generate a vector with the `sweep number', incremented every time
    # the velocity changes sign
    #
    sweep = []                          # vector specifying which sweep the fiducial belongs to
    for i in range(len(tmp) - 1):
        sweep += (tmp[i+1] - tmp[i])*[i]

    sweep += (len(fididx) - len(sweep))*[i] # make sweep and fididx have same length
    sweep = numpy.array(sweep)
    #
    # Choose the average fiducial as a standard (it should be in the middle of the range), resetting the
    # offset to zero whenever we see it
    #
    nff, ff = 0, 0.0
    for i in range(len(tmp)):
        tmp = fididx[numpy.where(sweep == i)]
        tmp[numpy.where(tmp > ud_delta)] -= ud_delta

        ff += sum(tmp)
        nff += len(tmp)

    ff = int(ff/nff + 0.5); ffval = 0.0
    if verbose:
        print "Resetting at fiducial %d" % ff
    #
    # Find the indices where we see the ff fiducial
    #
    tmp = numpy.arange(len(pos))[numpy.logical_or(fididx == ff, fididx == ff + ud_delta)]
    #
    # Generate a vector of corrections; the loop count is the number
    # of fiducial ff crossings, not the number of fiducial crossings
    #
    corrections = {}
    for i in range(len(tmp)):
        corrections[sweep[tmp[i]]] = ffval - pos[tmp[i]]
    #
    # Did any sweeps miss the `canonical' fiducials?
    #
    nsweep = sweep[-1] + 1
    for s in range(nsweep):
        if corrections.has_key(s):
            continue                    # already got it
        
        for s0 in range(s, -1, -1):
            if corrections.has_key(s0):
                break

        for s1 in range(s, nsweep):
            if corrections.has_key(s1):
                break
            
        assert s0 >= 0 or s1 < nsweep

        if s0 >= 0:
            if s1 < nsweep:              # we have two points
                corrections[s] = corrections[s0] + \
                    float(s - s0)/(s1 - s0)*(corrections[s1] - corrections[s0])
            else:
                corrections[s] = corrections[s0]
        else:
            corrections[s] = corrections[s1]
    #
    # Build a corrections vector the same length as e.g. $pos
    #
    corr = numpy.empty_like(pos) + 1.1e10
    for s, c in corrections.items():
        corr[sweep == s] = c
    #
    # Apply those corrections
    #
    pos += corr

    return pos

#
# Make a vector from 0 to number of fiducials that we've seen
#
def make_fiducials_vector(fididx, extend=True):
    fiducials = sorted(set(x for x in fididx))
    #
    # Extend the fiducials vector to start at 0?
    #
    if extend:
        fiducials[0:0] = range(0, fiducials[0])

    return numpy.array(fiducials, dtype=int)

def read_fiducials(fiducial_file, axis, readHeader=True):
    """
    Read the positions of the fiducials for AXIS into VECS findex, p1 and p2

    FIDUCIAL_FILE may be a filename, or a format expecting a single string
    argument (az, alt, or rot), or an MCP version (passed by reference)
    """
    ffile = fiducial_file
    if re.search(r"%s", ffile):
        ffile = ffile % axisAbbrevs[axisName]
        
    if os.path.exists(ffile):
        fiducial_file = ffile
    else:
        ffile2 = "/p/mcp/%s/fiducial-tables/%s.dat" % (ffile, axisAbbrevs[axisName])
        if not os.path.exists(ffile2):
            raise RuntimeError("I can find neither %s nor %s" % (ffile, ffile2))

        fiducial_file = ffile2

    try:
        ffd = open(fiducial_file, "r")
    except IOError, e:
        raise RuntimeError("I cannot read %s: %s" % (fiducial_file, e))

    # Read header
    header = {}
    while True:
        line = ffd.readline()
    
        if not line or re.search(r"^\# Fiducial", line):
            break

        if not readHeader:
            continue

        mat = re.search(r"^#\s*([^:]+):\s*(.*)", line)
        if mat:
            var, val = mat.group(1), mat.group(2)
            if var == "$Name":
                var = "Name"
                val = re.search(r"^([^ ]+)", val).group(1)

            if var == "Canonical fiducial":
                val = int(val)
            elif var == "Scales":
                val = [float(x) for x in val.split()]

            header[var] = val
    #
    # Done with header; read data
    #
    vecNames = [("findex", 0, int), ("p1", 1, float), ("p2", 5, float)]
    vecs = {}
    for v, col, t in vecNames:
        vecs[v] = []

    while True:
        fields = ffd.readline().split()

        if not fields:
            break
        
        for v, col, tt in vecNames:
            vecs[v].append(fields[col])

    ffd.close()
    #
    # Convert to numpy arrays
    #
    for v, col, tt in vecNames:
        vecs[v] = numpy.array(vecs[v], dtype=tt)

    return fiducial_file, vecs, header


###############################################################################
#
# Plot MS.ON information
#
def plot_ms(fig, ms_on, ms_off, axisName, tbase):
    axes = fig.get_axes()[0]
    ymin, ymax = axes.get_ylim()
    
    for ms, ctype in [(ms_on, 'blue',), (ms_off, 'cyan',)]:
        ms_time = numpy.array([t for t, a in zip(ms["time"], ms_on["axis"]) if a == axisName.upper()])
        ms_time = ms_time[ms_time > 0] - tbase
        y = numpy.zeros_like(ms_time) + ymin + 0.1*(ymax - ymin)

        axes.plot(ms_time, y, "+", color=ctype)

def foo():
    pass

if __name__ == "__main__":
    import argparse

    """Read and analyze an mcpFiducials file
    e.g.
    plotMcpFiducials -mjd 51799 --alt -y pos1 -x time -reset -canon -updown -table stdout
    """

    argv = " ".join(sys.argv)

    parser = argparse.ArgumentParser("plotMcpFiducials")
    parser.add_argument("fileName", type=str, nargs="?", help="The mcpFiducials file to read")
    parser.add_argument("-azimuth", action="store_true", #variable="azimuth",
                        default=False, help = "Read azimuth data")
    parser.add_argument("-altitude", action="store_true", default=False, help = "Read altitude data")
    parser.add_argument("-rotator", action="store_true", default=False, help = "Read rotator data")

    parser.add_argument("-mjd", default=getMJD(), type=int, help="Read mcpFiducials file for this MJD")
    parser.add_argument("-dir", default="/mcptpm/%d", dest="mjd_dir_fmt",
                        help="Directory to search for file, maybe taking MJD as an argument");

    parser.add_argument("-index0", default=0, type=int,
                        help="Ignore all data in the mcpFiducials file with index < index0")
    parser.add_argument("-index1", default=0, type=int,
                        help="Ignore all data in the mcpFiducials file with index > index0")

    parser.add_argument("-time0", type=int, default=0,
                        help="""Ignore all data in the mcpFiducials file older than this timestamp;
 If less than starting time, interpret as starting time + |time0|.
 See also -index0""")
    parser.add_argument("-time1", type=int, default=0,
                        help="""Ignore all data in the mcpFiducials file younger than this timestamp;
 If less than starting time, interpret as starting time + |time1|.
 See also -index1""")

    parser.add_argument("-canonical", action="store_true", default=False, 
                        help="Set the `canonical' fiducial to its canonical value")
    parser.add_argument("-setCanonical", type=str,
                          help="""Specify the canonical fiducial and optionally position,
     e.g. -setCanonical 78
          -setCanonical 78:168185
 """)
    parser.add_argument("-error", action="store_true", default=False,
                        help="Plot error between true and observed fiducial positions")
    parser.add_argument("-errormax", type=float, default=0.0,
                        help="Ignore errors between true and observed fiducial positions larger than <max>")
    parser.add_argument("-reset", action="store_true", default=False,
                        help="Reset fiducials every time we recross the first one in the file?")
    parser.add_argument("-scale", action="store_true", default=False,
                        help="Calculate the scale and ensure that it's the same for all fiducial pairs?")
    parser.add_argument("-absolute", action="store_true", default=False,
                        help="Plot the values of the encoder, not the scatter about the mean")
    parser.add_argument("-updown", action="store_true", default=False,
                        help="Analyze the `up' and `down' crossings separately")
    
    parser.add_argument("-xvec", type=str, help="Vector to use on x-axis (no plot if omitted)")
    parser.add_argument("-yvec", type=str, help="Vector to use on y-axis")
    parser.add_argument("-fiducialFile", type=str, default="",
                        help="""Read true positions of fiducials from this file rather
 than using the values in the mcpFiducials file.
 Filename may be a format, in which case %%s will be replaced by e.g. \"rot\".
 If you prefer, you may simple specify an MCP version number.\
 """)
    parser.add_argument("-ms", action="store_true", default=False,
                        help="Show MS actions (must have -xvec time)")
    parser.add_argument("-plotFile", type=str, help="""Write plot to this file.
 If the filename is given as "file", a name will be chosen for you.""")
    parser.add_argument("-tableFile", type=str,
                        help="Write fiducials table to this file (may be \"stdout\", or \"-\")")
    parser.add_argument("-verbose", action="store_true", default=False,
                        help="Be chatty?")

    parser.add_argument("-read_old_mcpFiducials", action="store_true", default=False,
                        help="Read old mcpFiducial files (without encoder2 info)?")

    args = parser.parse_args()
    #
    # Check that flags make sense
    #
    if args.error:
        if args.canonical:
            print >> sys.stderr, "Please don't specify -canonical with -error"
            sys.exit(1)
        if args.reset:
            print >> sys.stderr, "Please don't specify -reset with -error"
            sys.exit(1)
        if args.updown:
            print >> sys.stderr, "Please don't specify -updown with -error"
            sys.exit(1)
        if args.tableFile != "":
            print >> sys.stderr, "Please don't specify e.g. -table with -error"
            sys.exit(1)
    else:
       if args.fiducialFile and args.setCanonical:
           print >> sys.stderr, "-fiducialFile only makes sense with -error or without -setCanonical"
           sys.exit(1)

    if args.setCanonical:
        mat = re.search(r"^([0-9]+)(\:([0-9]+))?$", args.setCanonical)

        if not mat:
            print >> sys.stderr, "Invalid -setCanonical argument: %s" % args.setCanonical
            sys.exit(1)
            
        ff, ffval = mat.groups()[1:3]
    else:
        ff, ffval = None, None

    if args.scale:
        if not args.absolute:
            if args.verbose:
                print "-scale only makes sense with -absolute; I'll set it for you"
            args.absolute = True

    if args.xvec and not pyplot:
        print >> sys.stderr, "I am unable to plot as I failed to import matplotlib"
        args.xvec = None

    if args.ms and args.xvec != "time":
        print >> sys.stderr, "-ms only makes sense with -xvec time; ignoring"
        args.ms = False
    #
    # Which axis are we interested in?
    #
    naxis = args.azimuth + args.altitude + args.rotator
          
    if not naxis:
        print >> sys.stderr, "Please specify an axis"
        sys.exit(1)
    elif naxis > 1:
        print >> sys.stderr, "Please specify only one axis"
        sys.exit(1)
   
    axis_scale1 = 0; axis_scale2 = 0
    if args.altitude:
        axisName = "altitude"
        struct = "ALT_FIDUCIAL"
        names = ["time", "fididx", "pos1", "pos2", "deg", "alt_pos", "velocity"]
    if args.azimuth:
        axisName = "azimuth"
        struct = "AZ_FIDUCIAL"
        names = ["time", "fididx", "pos1", "pos2", "deg", "velocity"]
    if args.rotator:
        axisName = "rotator"
        struct = "ROT_FIDUCIAL"
        names ["time", "fididx", "pos1", "pos2", "deg", "latch", "velocity"]

    if args.read_old_mcpFiducials:
        names.append("true")
    else:
        names.append("true1")
        names.append("true2")
# 170
    #
    # Find the desired file
    #
    if not args.fileName:
        args.fileName = "mcpFiducials-%d.dat" % (args.mjd)
    else:
        if args.mjd != getMJD():
            print >> sys.stderr, "You may not specify both [fileName] and -mjd"
            sys.exit(1)
   
    if args.fileName and os.path.exists(args.fileName):
        dfile = args.fileName
    else:
        if re.search(r"%d", args.mjd_dir_fmt): # need the MJD
            mat = re.search(r"mcpFiducials-([0-9]+).dat", args.fileName)
            if not mat:
                print >> sys.stderr, "I cannot find a file called %s, and I cannot parse it for an mjd" % \
                    args.fileName
                sys.exit(1)
                
            mjd = mat.group(1)
      
        dirName = args.mjd_dir_fmt % args.mjd

        dfile = os.path.join(dirName, args.fileName)
        if not os.path.exists(dfile):
            print >> sys.stderr, "I cannot find %s in . or %s" % (args.fileName, dirName)
            sys.exit(1)

        args.fileName = dfile
        
    if args.verbose:
        print "File: %s" % args.fileName
#L202
    #
    # Check that the requested vectors exist
    #
    xvec, yvec = args.xvec, args.yvec

    if xvec and not yvec:
        yvec = "pos1"

    if xvec and names.count(xvec) == 0:
        if xvec == "i":                 # plot against the index
            xvec = "index"

        if xvec != "index":
            raise RuntimeError("There is no vector %s in the file" % xvec)
    if yvec and names.count(yvec) == 0:
        raise RuntimeError("There is no vector %s in the file" % yvec)
    #
    # What are the canonical values of the fiducials?  We get them from a pre-existing fiducials file
    #
    if ffval is None:                # not specified via -setCanonical
        if args.azimuth:
            if ff is None:
                ff = 19
            ffval = 31016188
        elif args.altitude:
            if ff is None:
                ff = 1
            ffval = 3825222
        else:
            if ff is None:
                ff = 78
            ffval = 168185

        if not args.fiducialFile:
            ffile = "/p/mcpbase/fiducial-tables/%s.dat"
        else:
            ffile = args.fiducialFile

        try:
            ffile, vecs, header = read_fiducials(ffile, axisName)
        except Exception, e:
            raise RuntimeError("Failed to read %s for canonical fiducial: %s" % (ffile, e))

        if ff != header["Canonical fiducial"]:
            raise RuntimeError("You may only use -setCanonical %d if %d is the canonical fiducial in %s" %
                               (ff, ff, ffile))

        ffval = vecs["p1"][vecs["findex"] == ff][0]

        print "Using canonical position %d for fiducial %d from %s" % (ffval, ff , ffile)
        del vecs
    #
    pars = yanny.read_yanny(dfile)
    vecs = pars[struct]
    if args.ms:
        ms_on =  pars["MS_ON"]
        ms_off = pars["MS_OFF"]

    if args.verbose:
        print "Vectors: %s" % ", ".join(vecs.keys())

    for k, v in vecs.items():
        vecs[k] = numpy.array(v, dtype=int if k in("fididx",) else float)
    #
    # remove vectors that weren't read
    #
    names = [n for n in names if vecs.get(n) is not None]
    #
    # Unpack vectors for syntactic convenience.  N.b. these are just new names for the same data
    time = vecs["time"]
    deg = vecs["deg"]
    fididx = vecs["fididx"]
    velocity = vecs["velocity"]
    pos = {}
    for i in (1, 2,):
        pos[i] = vecs["pos%d" % i]
    #
    # Discard early data if so directed
    #
    time0, time1 = args.time0, args.time1
    index0, index1 = args.index0, args.index1
    tmod = 10000
    tbase = tmod*int(time[0]/tmod)

    if time0 != 0 and time0 < time[0]:
        time0 = tbase + abs(time0)

    if time1 != 0 and time1 < time[0]:
        time1 = tbase + abs(time1)

    if time0 != 0 or time1 != 0 or index0 != 0 or index1 != 0:
        if time0 != 0 or time1 != 0:
            if index0 != 0 or index1 != 0:
                print >> sys.stderr, "Ignoring index[01] in favour of time[01]"

            if time0 == 0:
                time0 = time[0]
            if time1 == 0:
                time1 = time[-1]
            
            tmp  = time >= time0 and time <= time1
        else:
            index = range(0, time)

            if index0 < 0:
                index0 = 0            
            if index1 == 0 or index1 >= len(time):
                index1 = len(time) - 1

            tmp = index >= index0 and index <= index1

        for v in names:
            vecs[v] = vecs[v][tmp]
    #
    # Are there any datavalues left?
    #
    if len(time) == 0:
        raise RuntimeError("You haven't asked for any points")
    #
    # Reduce time to some readable value
    #
    time -= tbase
    #
    # Discard the non-mark rotator fiducials
    #
    if args.rotator:
        tmp  = fididx > 0
        for v in vecs.values():
            c = v[tmp]

    if args.verbose:
        fiducials = make_fiducials_vector(fididx, False)
        print "Fiducials crossed: %s" % ", ".join(str(x) for x in fiducials)
    #
    # If we want to analyse the `up' and `down' fiducials separately,
    # add ud_delta to fididx for all crossings with -ve velocity
    #
    if args.updown:
        ud_delta = max(fididx) + 5
        fididx[velocity < 0] += ud_delta
    else:
        ud_delta = 0
    #
    # Process fiducial data
    # Start by finding the names of all fiducials crossed
    #
    fiducials = make_fiducials_vector(fididx)
    #
    # Find the approximate position of each fiducial (in degrees)
    #
    fiducials_deg = numpy.empty_like(fiducials) + numpy.nan
    
    for i in range(len(fiducials)):
        fiducials_deg[i] = numpy.mean(deg[fididx == fiducials[i]])

    if args.verbose:
        for i in range(len(fiducials)):
            if not numpy.isfinite(fiducials_deg[i]):
                continue

            print "%3d %8.3f" % (fiducials[i], fiducials_deg[i])
#L409
    #
    # Unless we just want to see the fiducial errors (-error), estimate
    # the mean of each fiducial value
    #
    fpos = {}
    for i in (1, 2,):
        fpos[i] = numpy.zeros_like(fiducials)

    mat = re.search(r"^pos([12])", yvec) if yvec else None
    if args.error and not mat:
        print >> sys.stdout, "Please specify \"-y pos\[12\]\" along with -error; ignoring -error"
        args.error = False

    if args.error:
        #
        # Read the fiducial file if provided
        #
        if fiducial_file:
            vecs = read_fiducials(fiducial_file, axisName, False)[1] # just vecs

            for n in (1, 2,):
                #
                # Set fpos[12] from those fiducial positions
                #
                for i in range(len(fiducials)):
                    fpos[n][i] = numpy.mean(pos[n][findex == fiducials[i]])
        else:
            #
            # Find the true value for each fiducial we've crossed
            #
            if args.read_old_mcpFiducials:
                true1 = true

            for i in range(len(fiducials)):
                fpos[1][i] = numpy.mean(true1[fididx == fiducials[i]])

            fpos[2] = fpos[1]

        if False:
            for i in range(len(fiducials)):
                print "%d %d" % (fiducials[i], fpos[1][i])
    else:
        #
        # Reset the encoders every time that they pass some `fiducial' fiducial?
        #
        if args.reset:
            for i in (1, 2,):
                reset_fiducials(fididx, ud_delta, velocity, pos[i], args.verbose if i == 1 else 0)
        #
        # Calculate mean values of pos[12]
        #
        if args.updown:
            pos0 = {}
            for j in (1, 2,):
                pos0[j] = pos[j]       # save pos[j]
                
                for i in range(len(fiducials)):
                    fpos[j][i] = numpy.mean(pos[j][fididx == fiducials[i]])

                down = numpy.where(fididx < ud_delta)
                tmp2 = fididx
                tmp2[down] += ud_delta; tmp[numpy.logical_not(down)] -= ud_delta

                tmp = fpos[j][fididx] + fpos[j][tmp2]
                tmp = tmp/((fpos[j][fididx] != 0) + (fpos[j][tmp2] != 0))
                
                pos[j] -= fpos[j][fididx] - tmp
            #
            # Undo that +$ud_delta
            #
            fididx[fididx > ud_delta] -= ud_delta
            
            fiducials = make_fiducials_vector(fididx)
            
            for j in (1, 2,):
                fpos[j] = numpy.zeros_like(fiducials)
        #
        # (Re)calculate fpos[12] --- `Re' if args.updown was true
        #
        fposErr = {}; nfpos = {}
        for i in (1, 2,):
            nfpos[i] = numpy.empty_like(fiducials)
            fposErr[i] = numpy.empty_like(fiducials)
        
        for i in range(len(fiducials)):
            for j in (1, 2,):
                tmp =  pos[j][fididx == fiducials[i]]
                if len(tmp) == 0:
                    fposErr[j][i] = -9999 # disable fiducial
                else:
                    fpos[j][i] = numpy.mean(tmp)
                    
                    nfpos[j][i] = len(tmp)
                    fposErr[j][i] = 1e10 if len(tmp) == 1 else numpy.std(tmp)
        
        if args.updown:                                        # restore values
            for j in (1, 2,):
                pos[j] = pos0[j]

    if not args.absolute:
        for j in (1, 2,):
            pos[j] = pos[j] - fpos[j][fididx]
    #
    # If the axis wraps, ensure that pairs of fiducials seen 360 degrees
    # apart are always separated by the same amount -- i.e. estimate
    # the axis' scale
    #
    if args.scale:
        index = numpy.arange(len(deg))
        axis_scale = {}

        match = {}
        for n in (1, 2,):
            ndiff, diff = 0, 0.0
            for i in range(len(fiducials)):
                if fiducials_deg[i] < -999: # missing
                    continue
                
                tmp = fiducials[numpy.abs(fiducials_deg - 360 - fiducials_deg[i]) < 1]
                if len(tmp) == 0:
                    continue            # we were only here once
                
                match[i] = tmp[0]

                tmp = pos[n][fididx == fiducials[i]]
                if len(tmp) == 0:
                    continue            # we didn't cross this fiducial
                p1 = numpy.mean(tmp)
                
                tmp = pos[n][fididx == match[i]]
                if len(tmp) == 0:
                    continue                                # we didn't cross this fiducial
                p2 = numpy.mean(tmp)
                
                diff += p2 - p1
                ndiff += 1
                
                if args.verbose:
                    print "%3d %8.3f %10.3f" % (fiducials[i], fiducials_deg[i], p2 - p1)

            if ndiff == 0:
                if n == 1 and not args.altitude:
                    print >> sys.stderr, "You haven't moved a full 360degrees, so I cannot find the scale"

                for i in range(len(fiducials)):
                    if nfpos[n][i] > 0:
                        v0 = fpos[n][i]
                        deg0 = fiducials_deg[i]
                        break

                for i in range(len(fiducials) - 1, -1, -1):
                    if nfpos[n][i] > 0:
                        v1 = fpos[n][i]
                        deg1 = fiducials_deg[i]
                        break

                axis_scale[n] = 1.0/(v0 - v1) # n.b. -ve; not a real scale
                print >> sys.stderr, "%s scale APPROX %.6f  (encoder $n)"%\
                    (axisName, 60*60*(deg0 - deg1)*axis_scale[n], n)
            else:
                diff /= ndiff
                axis_scale[n] = 60*60*360.0/diff
                
                print "%s scale = %.6f  (encoder %d)" % (axisName, axis_scale[n], n)
                #
                # Force fiducials to have that scale
                #
                for i in range(len(fiducials)):
                    if match.get(i):
                        mean = (fpos[n][i] + fpos[n][match[i]] - diff)/2.0
                        fpos[n][i] = mean
                        fpos[n][match[i]] = mean + diff

        print "Encoder2/Encoder1 - 1 = %.6e" % (axis_scale[2]/axis_scale[1] - 1)
    #
    # Fix fiducial positions to match canonical value for some fiducial?
    #
    if args.canonical:
        for n in (1, 2,):
            if fpos.has_key(n):
                tmp  = fpos[n][fiducials == ff]
                tmp = tmp[tmp != 0]     # valid crossings aren't == 0
                if len(tmp) == 0:
                    raise RuntimeError("You have not crossed/successfully read canonical fiducial %d" % ff)

                fpos[n][nfpos[n] > 0] += ffval - numpy.mean(tmp)
    #
    # Print table?
    #
    if args.tableFile is not None:
        if args.tableFile in ("stdout", "-",):
            fd = sys.stdout
        else:
            fd = open(args.tableFile, "w")

        # Get a CVS Name tag w/o writing it out literally.
        cvsname = "".join(["$", "Name", "$"])

        print >> fd, """#
# %s fiducials
#
# %s
#
# Creator:                 %s
# Time:                    %s
# Input file:              %s
# Scales:                  %.6f %.6f
# Canonical fiducial:      %d
# Arguments:               %s
#
# Fiducial Encoder1 +- error  npoint  Encoder2 +- error  npoint
""" % (axisName, cvsname, pwd.getpwuid(os.geteuid())[0],
       pyTime.time(), dfile, axis_scale[1], axis_scale[2], ff, argv),

        for i in range(1, len(fpos[1])):
            print >> fd, "%-4d " % fiducials[i],
            
            for n in (1, 2,):
                print >> fd, "   %10.0f +- %5.1f %3d" % (fpos[n][i], fposErr[n][i], nfpos[n][i]),
            print >> fd, ""
        
        if fd != sys.stdout:
            fd.close()
    #
    # Make desired plot
    #
    if xvec:
        #
        # Create the index vector if we need it
        #
        if xvec == "index":             # plot against the index
            index = numpy.arange(0, len(pos[1]))

        if args.plotFile:
            if args.plotFile == "file":
                args.plotFile = "%s-%s-%s" % (axisName, xvec, yvec)
                if args.reset:
                    args.plotFile += "-R"
                if args.updown:
                    args.plotFile += "-U"
                args.plotFile += ".png"

        nameToVec = dict(index=index, time=time, pos1=pos[1], pos2=pos[2])
        x = nameToVec.get(xvec)         # xvec is a name; x is a numpy array
        y = nameToVec.get(yvec)

        if x is None:
            raise RuntimeError("Invalid x-vector: %s" % xvec)
        if y is None:
            raise RuntimeError("Invalid y-vector: %s" % yvec)

        if args.error:
            haveValue = numpy.where(fpos[1][fididx] != 0) # we have a measurement of this fiducial
            if args.errormax > 0:
                haveValue = numpy.logical_and(haveValue, abs(y) < args.errormax)

            x = x[haveValue]
            y = y[haveValue]
            if xvec != "velocity" and yvec != "velocity":
                velocity = velocity[haveValue]

        fig = pyplot.figure()
        axes = fig.add_axes((0.1, 0.1, 0.85, 0.80));

        xmin = min(x); xmax = max(x)
        ymin = min(y); ymax = max(y)

        if xvec == "time":
            if args.time0 != 0:
                xmin = time0 - tbase
            if args.time1 != 0:
                xmax = time1 - tbase

        axes.set_xlim(xmin, xmax)
        axes.set_ylim(ymin, ymax)

        l = velocity >= 0
        axes.plot(x[l], y[l], "r.")
        l = velocity < 0
        axes.plot(x[l], y[l], "g.")


        if args.ms:
            plot_ms(fig, ms_on, ms_off, axisName, tbase)

        title = axisName
        if args.reset:
            title += " -reset"
        if args.updown:
            title += " -updown"
        title += ".  Red: v > 0" 

        if args.ms:
            title += "  Blue: MS.ON, Cyan: MS.OFF"

        if args.fiducialFile:
            title += "  %s" % args.fiducialFile
        axes.set_title(title)

        if xvec == "time" and tbase:
            if args.verbose:
                print "Initial time on plot: [utclock [expr int($tbase + $xmin)]]"
            axes.set_xlabel("time - %s" % tbase)
        else:
            axes.set_xlabel(xvec)

        axes.set_ylabel(yvec)

        fig.show()

        if args.plotFile:
            fig.savefig(args.plotFile)

        raw_input("Continue? ")

    0
