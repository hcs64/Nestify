SOURCES = \
mem.as \
test.as \
newdlist.as \
buffer.as \
vector.as

PREGEN = \
advancetab.bin \
codegen.as

IMAGES =

NESHLA = neshla
PYTHON = python

EXE = test.nes

$(EXE): $(SOURCES) $(IMAGES) $(PREGEN)
	$(NESHLA) test.as

tell: $(SOURCES) $(IMAGES) $(PREGEN)
	$(NESHLA) test.as -tell

advancetab.bin: advancetab.py
	$(PYTHON) advancetab.py

codegen.as: codegen.py
	$(PYTHON) codegen.py > codegen.as

clean:
	rm -f test.nes $(PREGEN) log.txt
