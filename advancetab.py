#!/usr/bin/python

from io import open
from struct import pack

outfile = open("advancetab.bin", 'wb')

for x in range(1,4):
    for y in range(0,256):
        val = y + x
        if val+3 > 256:
            val = 0

        outfile.write(pack("B", val))
