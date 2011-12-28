#!/usr/bin/python

from struct import pack
from io import open

outfile = open("rangetab.bin", 'wb')

for length in range(1,9):
    mask = (1<<length)-1
    for pos in range(0,8):
        outfile.write(pack("B", (mask << pos)&0xFF))
