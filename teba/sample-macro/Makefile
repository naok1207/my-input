EXT_MACRO = ext_macro.pl -r
REV_MACRO = rev_macro.pl -Nr

PARSER = cparse.pl
JOIN = join-token.pl

SRC = sample.c

TARGET_R = $(SRC:.c=.r)
TARGET_E = $(SRC:.c=.e)
TARGET_DIFF = $(SRC:.c=.diff)

.SUFFIXES: .c .r .e .diff

all: $(TARGET_DIFF) $(TARGET_R) $(TARGET_E)


.c.e:
	@echo ""
	@echo "## Extracting macros...."
	$(EXT_MACRO) -f $< $< > $@
	diff -u $@0 $@
	@echo ""
	@echo "## Differences from the original:"
	-diff -u $< $@

clean::
	rm -f *.e

.e.r:
	@echo ""
	@echo "## Replacing with macro calls...."
	$(REV_MACRO) -f $(<:.r=.c) $< > $@
	diff -u $@0 $@
	@echo ""
	@echo "## Differences from the extracted one:"
	-diff -u $< $@

clean::
	rm -f *.r

.r.diff:
	@echo ""
	@echo "## Differences from the orignal one:"
	-diff -u $(<:.r=.c) $< | tee $@

clean::
	rm -f *.diff
