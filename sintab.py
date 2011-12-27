#!/usr/bin/python

from math import sin, cos, pi
from struct import pack
from io import open

outfile = open("sintab.bin", 'wb')

radius = 20*8/2
cx = 24*8/2
cy = 21*8/2

for i in range(256):
    angle = i * 2*pi/256
    x = round(cx + radius * cos(angle))
    outfile.write(pack("B", x))

for i in range(256):
    angle = i * 2*pi/256
    y = round(cy + radius * sin(angle))
    outfile.write(pack("B", y))
