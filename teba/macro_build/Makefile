GEN = mk_normalize_rules.pl
SRC = macro_tmpl.pl $(SUB)
SUB = normalize_macro_def.sub

TARGET_REV = rev_macro.pl
TARGET_EXT = ext_macro.pl
TARGET = $(TARGET_REV) $(TARGET_EXT)

all: $(TARGET)

$(TARGET_REV): $(SRC)
	cat $(SRC) > $@
	chmod a+x $@

$(TARGET_EXT): $(TARGET_REV)
	ln -s $(TARGET_REV) $@

clean::
	rm -f $(TARGET) 

$(SUB): $(GEN)
	./$(GEN) > $@

clean::
	rm -f $(SUB)

install:
	cp -a $(TARGET) ../bin
