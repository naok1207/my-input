MOVEIF = move_ifdef.pl
PARSER = cparse.pl
JOIN = join-token.pl

SRC_X = ifdef-sample.c ifdef-sample2.c ifdef-sample3.c ifdef-sample4.c

SRC_A = ifdef-sample5.c ifdef-sample6.c ifdef-sample7.c ifdef-sample8.c \
	ifdef-sample9.c cancel_overwrapped-test.c

TARGET_X = $(SRC_X:.c=.x)
TARGET_A = $(SRC_A:.c=.a)
TARGET_E = $(SRC_A:.c=.E)

all: $(TARGET_X) $(TARGET_E) $(TARGET_A)

.SUFFIXES: .c .x .a .E

.c.x: 
	$(PARSER) $< | $(MOVEIF) | $(JOIN) > $@
	@echo "### diff of result ###"
	-diff -u $< $@
	diff -u $@0 $@
	@echo ""

clean::
	rm -f *.x

.c.a: 
	$(PARSER) $< | $(MOVEIF) -a | $(JOIN) > $@
	@echo "### diff of result ###"
	-diff -u $< $@
	diff -u $@0 $@
	@echo ""

clean::
	rm -f *.a

.c.E: 
	$(PARSER) $< | $(MOVEIF) -aE | $(JOIN) > $@
	@echo "### diff of result ###"
	-diff -u $< $@
	diff -u $@0 $@
	@echo ""

clean::
	rm -f *.E


