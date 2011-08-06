SOURCES = \
mem.as \
test.as \
sendchr.as \
tiles.as

EXE = test.nes

$(EXE): $(SOURCES) $(IMAGES)
	neshla test.as

tell: $(SOURCES) $(IMAGES)
	neshla test.as -tell

clean:
	rm -f test.nes $(IMAGES) log.txt
