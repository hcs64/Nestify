SOURCES = \
mem.as \
test.as \
sendchr.as \
tiles.as \
lines.as

IMAGES = \
sintab.bin

EXE = test.nes

$(EXE): $(SOURCES) $(IMAGES)
	neshla test.as

tell: $(SOURCES) $(IMAGES)
	neshla test.as -tell

sintab.bin: sintab.py
	./sintab.py

clean:
	rm -f test.nes $(IMAGES) log.txt sintab.bin
