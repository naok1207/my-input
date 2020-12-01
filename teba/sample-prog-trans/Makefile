.SUFFIXES: .c .x

SRC = add-debug.c extract-decl.c for-while.c ifdef-curly-refact.c \
      iff.c if-exit.c init-decl.c swap-decl.c struct-path.c

TARGET = $(SRC:.c=.x) $(SRC:.c=.t)

all: $(TARGET) comb

.c.x:
	cparse.pl -p $< | rewrite.pl -b -p $*.pt | tee $*.t | join-token.pl > $@
	diff -u $@0 $@
	@echo ""
	@echo "=== Rewriting rule: $*.pt ==="
	@cat $*.pt
	@echo "=== Original: $< ==="
	@cat $<
	@echo "=== Result: $@ ==="
	@cat $@
#	@echo "=== Differences: ==="
#	@-diff -u $< $@
	@echo "---"
	@echo ""

clean:
	rm -f $(TARGET) comb.x

comb:
	cparse.pl -p init-decl.c | rewrite.pl -p init-decl.pt |\
	  rewrite.pl -p swap-decl.pt | join-token.pl > comb.x
	diff -u comb.x0 comb.x
	@echo ""
	@echo "Combination of patterns"
	@echo "=== Rewriting rule: init-decl.pt ==="
	@cat init-decl.pt
	@echo "=== Rewriting rule: swap-decl.pt ==="
	@cat swap-decl.pt
	@echo "=== Original: $< ==="
	@cat init-decl.c
	@echo "=== Result: $@ ==="
	@cat comb.x
#	@echo "=== Differences: ==="
#	@-diff -u init-decl.c comb.x
	@echo "---"
	@echo ""
