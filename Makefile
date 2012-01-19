SOURCES = \
mem.as \
test.as \
dlist.as \
buffer.as \
blocks.as \
vector.as

PREGEN = \
sintab.bin \
rangetab.bin \
cachemap.bin

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

cachemap.bin: cachemap.py
	./cachemap.py

clean:
	rm -f test.nes $(PREGEN) log.txt
