# 
# Copyright (c) 2009-2020 The TEBA Project. All rights reserved.
# 
# Redistribution and use in source, with or without modification, are
# permitted provided that the following conditions are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
# 
# Author: Atsuhi Yoshida

package BracketsID;

use strict;
use warnings;

sub new() {
    my $self = {};
    bless $self;
    $self->{BID} = 0;
    $self->{PREFIX} = "#B";
    return $self;
}

sub reset() {
    my $self = shift;
    $self->{BID} = 0;
}

sub conv() {
    my ($self, $text) = @_;

    my $prefix = $self->{PREFIX};

    # define IDs for parentheses, curly braces and commas.
    my $tid;
    my @brackets;
    my @code = split(/\n/, $text);
    foreach (@code) {
	if (m/^([PCA]_(\w+))\s+(?:$prefix\w+\s+)?<(.*)>$/) {
	    my ($type, $dir, $token) = ($1, $2, $3);
	    if ($dir eq "L") {
		$tid = sprintf("%s%04d", $prefix, ++$self->{BID});
		push(@brackets, $tid);
	    } else {  # i.e. $dir eq "R"
		$tid = (@brackets > 0 ? pop(@brackets) : "");
	    }
	    $_ = "$type $tid\t<$token>";
	}
    }

#    if (@brackets > 0) {
#	die "Illegal correspondence: ". join(", ", @brackets);
#    }
    return join("\n", @code)."\n";
}

sub conv_with_ca() {  # assigning ids to commas.
    my ($self, $text) = @_;

    my $prefix = $self->{PREFIX};

    # define IDs for parentheses, curly braces and commas.
    my $tid;
    my @brackets;
    my @code = split(/\n/, $text);
    foreach (@code) {
	if (m/^([PCA]_\w+|CA)\s+(?:$prefix\w+\s+)?<(.*)>$/) {
	    my ($type, $token) = ($1, $2);
	    if ($type =~ m/^[PCA]_L$/) {
		$tid = sprintf("%s%04d", $prefix, ++$self->{BID});
		push(@brackets, $tid);
	    } elsif ($type =~ m/^[PCA]_R$/) {
		$tid = (@brackets > 0 ? pop(@brackets) : "");
	    } elsif ($type eq "CA") {
		$tid = (@brackets > 0 ? $brackets[-1] : "");
	    }
	    $_ = "$type $tid\t<$token>";
	}
    }

#    if (@brackets > 0) {
#	die "Illegal correspondence: ". join(", ", @brackets);
#    }
    return join("\n", @code)."\n";
}


sub adjust_brackets() {
    my ($self, $text) = @_;
    my @input = split("\n", $text);
    @input = &add_virtual_brackets(@input);
    return join('', map("$_\n", @input));
}

sub add_virtual_brackets() {
    # add virtual tokens of brackets when extra braket
    my @c = &add_virtual_brackets_sub(1, @_); # forward
    @c = reverse(&add_virtual_brackets_sub(-1, reverse(@c))); # backward
    return @c;
}

sub swap() {
    my ($x, $y) = @_;
    my $tmp = $$x;
    $$x = $$y;
    $$y = $tmp;
}

# add_virutual_brackets_sub requires directives.
sub add_virtual_brackets_sub() {
    my $dir = shift;
    my ($bracket_B, $bracket_E) = ("L", "R");
    my ($pre_B, $pre_E) = (qr(^PRE_DIR\s+<ifn?(?:def)?>$),
			   qr(^PRE_DIR\s+<endif>$));
    my ($macro_B, $macro_E) = (qr(^B_MCB\b), qr(^E_MCB\b));
    if ($dir < 0) {  # backword
	&swap(\$bracket_B, \$bracket_E);
	&swap(\$pre_B, \$pre_E);
	&swap(\$macro_B, \$macro_E);
    }

    my @out;
    my @brackets;        # nesting brakets.
    my $pp_level = 0;    # nest levels of preprocess directives
    my $nest_level = 0;  # nest levels of P, C and A.
    my @nest_stack;  # rembers the nest level at the top of each ifdef block.

    for (my $i = 0, ; $i < @_; $i++) {
	$_ = $_[$i];
	if (m/$macro_B/) {
	    $i = &add_virtual_brackets_in_macro($i, $macro_E,
				$bracket_B, $bracket_E, \@_, \@out);
	    next;
	}
	if (my ($sort, $dir) = (m/^([PCA])_(\w)\b/)) {
	    my $pl = $pp_level;
	    if ($dir eq $bracket_B) {
		push(@brackets, [ $sort, $pl, ++$nest_level ]);
	    } else { #  ($dir eq $bracket_E)
		if (@brackets > 0 && $brackets[-1]->[0] eq $sort) {
		    my $b = pop(@brackets);
		    $pl = $b->[1];
		} else {
		    push(@out, "${sort}_${bracket_B}\t<>");
		}
		--$nest_level;
	    }
	    push(@out, $_);
	    my @save;
	    while (@brackets > 0 && $brackets[-1]->[0] eq $sort
		   && $brackets[-1]->[1] > $pp_level) {
		my $b = pop(@brackets);
		if ($b->[2] > $nest_level) {
		    push(@out, "${sort}_${dir}\t<>");
		} else {
		    unshift(@save, $b);
		}
	    }
	    push(@brackets, @save);
	} else {
	    if (m/$pre_B/) {
		$pp_level++;
		push(@nest_stack, $nest_level);
	    } elsif (m/$pre_E/) {
		$pp_level--;
		pop(@nest_stack);
	    } elsif (m/PRE_DIR\s+<(?:else|elif)>/) {
		$nest_level = $nest_stack[-1];
	    }
	    push(@out, $_);
	}
    }
    return @out;
}

# add_virutual_brackets_sub requires directives.
sub Xadd_virtual_brackets_sub() {  # old version.
    my $dir = shift;
    my ($bracket_B, $bracket_E) = ("L", "R");
    my ($pre_B, $pre_E) = (qr(^PRE_DIR\s+<ifn?(?:def)?>$),
			   qr(^PRE_DIR\s+<endif>$));
    my ($macro_B, $macro_E) = (qr(^B_MCB\b), qr(^E_MCB\b));
    if ($dir < 0) {  # backword
	&swap(\$bracket_B, \$bracket_E);
	&swap(\$pre_B, \$pre_E);
	&swap(\$macro_B, \$macro_E);
    }
    my @out;
    my @pp_bracket;
    my @bracket_sort;
    my $pp_level = 0;
    for (my $i = 0, ; $i < @_; $i++) {
	$_ = $_[$i];
	if (m/$macro_B/) {
	    $i = &add_virtual_brackets_in_macro($i, $macro_E, 
				$bracket_B, $bracket_E, \@_, \@out);
	    next;
	}
	if (my ($sort, $dir) = (m/^([PCA])_(\w)\b/)) {
	    my $pl = $pp_level;
	    if ($dir eq $bracket_B) {
		push(@pp_bracket, $pp_level);
		push(@bracket_sort, $sort);
	    } else { #  ($dir eq $bracket_E)
		$pl = (@pp_bracket > 0 ? pop(@pp_bracket) : 0);
		my $s = (@bracket_sort > 0 ? pop(@bracket_sort) : "");
		if ($s ne $sort) {
		    push(@pp_bracket, $pl);
		    push(@bracket_sort, $s);
		    push(@out, "${sort}_${bracket_B}\t<>");
		}

	    }
	    push(@out, $_);
	    for ( ; $pl > $pp_level; $pl--) {
		pop(@pp_bracket);
		push(@out, "${sort}_${dir}\t<>");
	    }
	} else {
	    if (m/$pre_B/) {
		$pp_level++;
	    } elsif (m/$pre_E/) {
		$pp_level--;
	    }
	    push(@out, $_);
	}
    }
    return @out;
}

sub add_virtual_brackets_in_macro() {
    my ($i, $macro_E, $bracket_B, $bracket_E, $seq, $out) = @_;
    my @bracket_sort;
    for ( ; ($_ = $seq->[$i]) !~ m/$macro_E/; ++$i) {
	if (m/^([PCA])_(\w)\b/) {
	    my ($sort, $dir) = ($1, $2);
	    if ($dir eq $bracket_B) {
		push(@bracket_sort, $sort);
	    } elsif ($dir eq $bracket_E && @bracket_sort > 0) {
		if ($bracket_sort[-1] eq $sort) {
		    pop(@bracket_sort);
		} else {
		    push(@$out, qq(${sort}\_${bracket_B}\t<>));
		}
	    }
	}
	push(@$out, $_);
    }
    while (@bracket_sort > 0) {
	my $s = pop(@bracket_sort);
	push(@$out, "${s}_${bracket_E}\t<>");
    }
    push(@$out, $seq->[$i]);  # begin/end of macro_body
    return $i;
}


1;

