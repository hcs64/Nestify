#!/usr/bin/python

from struct import pack
from io import open

outfile = open("updaterange.bin", 'wb')

lengths = []
starts = []
# convert sparse to solid ranges
for bf in range(0,256):
    first = 0
    for i in range(0,8):
        if bf&(1<<i):
            first = i
            break

    last = -1
    for i in range(7,-1,-1):
        if bf&(1<<i):
            last = i
            break

    length = 1+last-first
    lengths.append(length)
    starts.append(first)
    #mask = (1<<length)-1
    #outfile.write(pack("B", (mask << first)&0xFF))

# 000-0ff: lengths
for i in range(0,256):
    outfile.write(pack("B", lengths[i]))

# 100-1ff: starts (from right)
for i in range(0,256):
    outfile.write(pack("B", starts[i]))
