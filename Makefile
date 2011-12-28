SOURCES = \
mem.as \
test.as \
sendchr.as \
tiles.as \
lines.as

PREGEN = \
sintab.bin \
rangetab.bin

IMAGES =

EXE = test.nes

$(EXE): $(SOURCES) $(IMAGES) $(PREGEN)
	neshla test.as

tell: $(SOURCES) $(IMAGES) $(PREGEN)
	neshla test.as -tell

sintab.bin: sintab.py
	./sintab.py

rangetab.bin: rangetab.py
	./rangetab.py

clean:
	rm -f test.nes $(PREGEN) log.txt
