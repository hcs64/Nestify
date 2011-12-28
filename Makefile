SOURCES = \
mem.as \
test.as \
sendchr.as \
tiles.as \
lines.as

PREGEN = \
sintab.bin \
digitmap.bin

IMAGES = \
digits.bin

EXE = test.nes

$(EXE): $(SOURCES) $(IMAGES) $(PREGEN)
	neshla test.as

tell: $(SOURCES) $(IMAGES) $(PREGEN)
	neshla test.as -tell

sintab.bin: sintab.py
	./sintab.py

digitmap.bin: digitmap.py
	./digitmap.py

clean:
	rm -f test.nes $(PREGEN) log.txt sintab.bin digitmap.bin
