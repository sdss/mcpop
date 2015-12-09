#!/usr/bin/env python
"""Test that plotMcpFiducials output matches old fiducial tables."""

import unittest
import numpy as np

import plotMcpFiducials

def read_fiducials(infile):
    types= ('i4', 'i8', 'S3', 'f8', 'i4', 'i8', '|S2', 'f8', 'i4')
    names = ('fiducial', 'Encoder1', '', 'error1', 'npoint1', 'Encoder2', '', 'error2', 'npoint2')
    return np.loadtxt(infile,np.dtype(zip(names,types)))

class Test_plotMcpFiducials(unittest.TestCase):
    def _compare(self, fiducials, fpos, fposErr, nfpos, expect):
        np.testing.assert_array_equal(fiducials[1:], expect['fiducial'])
        np.testing.assert_array_equal(fpos['pos1'][1:],expect['Encoder1'])
        np.testing.assert_array_equal(fpos['pos2'][1:],expect['Encoder2'])
        np.testing.assert_array_equal(fposErr['pos1'][1:],expect['error1'])
        np.testing.assert_array_equal(fposErr['pos2'][1:],expect['error2'])
        np.testing.assert_array_equal(nfpos['pos1'][1:],expect['npoint1'])
        np.testing.assert_array_equal(nfpos['pos2'][1:],expect['npoint2'])

    def _call_and_test(self, args):
        args += ' -noplot'
        fiducials, fpos, fposErr, nfpos = plotMcpFiducials.main(args.split())
        self._compare(fiducials, fpos, fposErr, nfpos, self.expect)


class Test_plotMcpFiducials_az(Test_plotMcpFiducials):
    def setUp(self):
        self.expect = read_fiducials('data/v1_118/az.dat')

    def test_table_file_args(self):
        args = '-dir data/57253 -fiducialFile=data/v1_117/%s.dat -mjd 57253 -az -time0 1439993145 -time1 1439995864 -canon -reset -scale -table az.dat'
        # args = '-dir data/57253 -fiducialFile=data/v1_117/%s.dat -mjd 57253 -az -time0 1439993145 -time1 1439995864 -canon -reset -table az.dat'
        self._call_and_test(args)

class Test_plotMcpFiducials_alt(Test_plotMcpFiducials):
    def setUp(self):
        self.expect = read_fiducials('data/v1_118/alt.dat')

    def test_table_file_args(self):
        args = '-dir data/57253 -fiducialFile=data/v1_117/%s.dat -mjd 57253 -alt -time0 1439996040 -time1 1439996726 -canon -reset -scale -table alt.dat'
        self._call_and_test(args)


class Test_plotMcpFiducials_rot(Test_plotMcpFiducials):
    def setUp(self):
        self.expect = read_fiducials('data/v1_118/rot.dat')

    def test_table_file_args(self):
        args = '-dir data/57253 -fiducialFile=data/v1_117/%s.dat -mjd 57253 -rot -time0 1439997030 -time1 1439999319 -canon -reset -scale -table rot.dat'
        # args = '-dir data/57253 -fiducialFile=data/v1_117/%s.dat -mjd 57253 -az -time0 1439993145 -time1 1439995864 -canon -reset -table az.dat'
        self._call_and_test(args)


if __name__ == '__main__':
    unittest.main()
