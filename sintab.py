#!/usr/bin/python

from struct import pack
from io import open
import math

outfile = open("sintab.bin", 'wb')

for a in range(0,160):
    sin = math.sin(a*math.pi/64)
    outfile.write(pack("B", (sin+1)*25))
