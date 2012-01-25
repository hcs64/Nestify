SOURCES = \
mem.as \
test.as \
newdlist.as \
buffer.as \
vector.as

PREGEN = \
advancetab.bin \
rangetab.bin \
updaterange.bin \
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

rangetab.bin: rangetab.py
	$(PYTHON) rangetab.py

updaterange.bin: updaterange.py
	$(PYTHON) updaterange.py

codegen.as: codegen.py
	$(PYTHON) codegen.py > codegen.as

clean:
	rm -f test.nes $(PREGEN) log.txt
