#!/usr/bin/python

from io import open
from struct import pack

outfile = open("cachemap.bin", 'wb')
for i in range(24*21):
    cacheline=(i%31)
    outfile.write(pack("B", cacheline))
