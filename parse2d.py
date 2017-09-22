#!/usr/bin/env python3
from PIL import Image
from collections import namedtuple
from binascii import unhexlify
import sys

# parses debug output from print2d() and creates PNGs
Parsed = namedtuple("Parsed", ['w', 'h', 's'])
parsed = {}

state = None
for line in sys.stdin:
	line = line.rstrip("\r\n")
	if state is not None:
		dim, data = line.split(":")
		tmp = dim.split(",")
		w, h = int(tmp[0]), int(tmp[1])
		parsed[state] = Parsed(w, h, data)

	if line.startswith("##"):
		state = line[2:]
	else:
		state = None

for name, p in parsed.items():
	#print("len(s)=%r w*h=%d" % (len(p.s), p.w * p.h))
	img = Image.frombytes("L", (p.w, p.h), unhexlify(p.s))
	img.save(name + ".png")
