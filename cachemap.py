#!/usr/bin/python

from io import open
from struct import pack
from math import sqrt, atan2, pi

outfile = open("cachemap.bin", 'wb')
for x in range(24):
    for y in range(21):
        screenx = (x/2)+(x%2)*12
        screeny = y

        relx = (screenx-12)
        rely = (screeny-10.5)
        angle = atan2(rely, relx)
        dist = sqrt(relx*relx+rely*rely)

        cacheline = int((angle + pi)/(2*pi) * 15)

        outfile.write(pack("B", cacheline))
