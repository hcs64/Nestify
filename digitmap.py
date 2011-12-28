#!/usr/bin/python

from struct import pack
from io import open

outfile = open("digitmap.bin", 'wb')

for j in range(0xFC, 0x100):
    outfile.write(pack("B", j)*64)
