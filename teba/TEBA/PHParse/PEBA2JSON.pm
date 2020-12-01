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

package PEBA2JSON;

use strict;
use warnings;
no warnings 'recursion';

use JSON;
use Data::Dumper;

my %optf;
sub init_opt() {
    %optf = (
	"P"   => \&opt_expr,
	"ST"  => \&opt_stmt,
	"F"   => \&opt_func,
	"ARG" => \&opt_arg,
	"CL" => \&opt_class,
	"NA" => \&opt_namespace,
	"USE" => \&opt_use,
	"FILE" => \&opt_file,
	);
}

BEGIN {
    &init_opt();
}


sub new() {
    my $self = bless {};
    $self->{coderef} = $_[1] if (defined $_[1]);
    return $self;
}

sub raw() {
    my $self = shift;
    $self->{no_opt} = 1;
    return $self;
}

sub text() {
    my $self = shift;
    my $text = shift;
    $self->{coderef} = \$text;
    return $self;
}

sub list() {
    my $self = shift;
    my @list = @_;
    $self->{coderef} = \@list;
    return $self;
}

sub json() {
    my $self = shift;
    if (ref($self->{coderef}) eq "SCALAR") {
	my @a = split("\n", ${$self->{coderef}});
	$self->{coderef} = \@a;
    }
    my $tree = &genObj($self->{coderef});
    &optimize($tree) unless $self->{no_opt};
    $self->{json} = $tree;
    return $self;
}


sub str() {
    my $self = shift;
    return $self->pretty();
}

sub pretty() {
    my $self = shift;
    return JSON->new->max_depth()->pretty->encode($self->{json});
}

sub tree() {
    my $self = shift;
    return $self->{json};
}

sub dump() {
    my $self = shift;
    return Dumper($self->{json});
}

sub set_json() {
    my $self = shift;
    my $t = shift;
    $self->{json} = JSON->new->decode(ref($t) eq "SCALAR" ? $$t : $t);
    return $self;
}

sub set_json_tree() {
    my $self = shift;
    my $t = shift;
    $self->{json} = $t;
    return $self;
}

sub teba() {
    my $self = shift;
#    return join('', map("$_\n", &getTokens($self->{json})));
    return join('', map("$_\n", &tokenize($self->{json})));
}

sub optimize() {
    my $elem = shift;

    &{$optf{$elem->{t}}}($elem) if $optf{$elem->{t}};

    map(&optimize($_), grep(&isObj($_), @{$elem->{e}}));
}

sub opt_expr() {
    my $elem = shift;

    my $top = $elem->{e}->[0];
    if (&isObj($top)) {
	if ($top->{t} eq "FC") {  # function call
	    $elem->{e} = $top->{e};
	    my @ch = &getObjIndex($elem);
	    $elem->{ref}->{call} = 0;
	    shift(@ch) if ($ch[0] == 0); # normal function call, not ID_TP
	    $elem->{ref}->{arg} = \@ch;
	    $elem->{t} = "P_FC";
	    return;
	} elsif ($top->{t} eq "CST") { # cast expression;
	    my @ch = &getObjIndex($elem);
	    my @t = grep(/^ID_TP/, @{$elem->{e}->[ $ch[0] ]->{e}});
	    $t[0] =~ s/^ID_TP\s+<(\w+)>$/$1/;
	    $elem->{at}->{op} = "($t[0])_";
	    $elem->{ref}->{operand} = [ $ch[1] ];
	    $elem->{t} = "P_CST";
	    return;
	} elsif ($top->{t} eq "LIS") { # string including variable references
	    my $el = $elem->{e} = $top->{e};
	    my $i = 0;
	    while ($i < @$el) {
		if (&isObj($el->[$i])) {
		    if ($el->[$i]->{e}->[0] =~ /^LIS/) {
			splice(@$el, $i, 1, @{$el->[$i]->{e}});
		    } else {
			push(@{$elem->{ref}->{vars}}, $i);
		    }
		}
		$i++;
	    }
	    $elem->{t} = "LIS";
	    return;
	}
    } elsif ($top) { # An empty expression has no $top.
	if ($top =~ /^(ID_\w+)\s+<(.*)>$/) {  # variable reference
	    $elem->{t} = $1;
	    $elem->{at}->{name} = $2;
	    return;
	}
	if ($top =~ /^(LI\w+)\s+<(.*)>$/) {   # literature; LIN, LIC
	    $elem->{t} = $1;
	    $elem->{at}->{value} = $2;
	    return;
	}
    }

    # expression with an operator.
    $elem->{t} = "P_OP";
    my @ch = &getObjIndex($elem);
    my (@op, @sy);
    foreach my $i (0..$#{$elem->{e}}) {
	if ($elem->{e}->[$i] =~ /^(?:OP|[AP]_|CA).*\s<(.*)>$/) {
	    push(@op, $i);
	    push(@sy, $1);
	}
    }

    if (@op == 0) { # no operator, may be an illegal expression
	return;
    }

    $elem->{at}->{op} = \@op;  # a tertiary operator has two symbols.
    if ($sy[0] eq ",") { #comma (CA)
	$elem->{at}->{sym} = "_". join("_", @sy) . "_";
    } elsif (@op == 1) {
	if (@ch == 2) {
	    $elem->{at}->{sym} = "_$sy[0]_";
	} elsif (@ch == 1) {
	    $elem->{at}->{sym} = $op[0] < $ch[0] ? "$sy[0]_" : "_$sy[0]";
	} else { # (@ch == 0) ## for operator '&'
	    $elem->{at}->{sym} = "$sy[0]_";
	}
    } else { # (@op == 2)
	if ($op[0] > 0 && @ch == 1) {  # array but no index.
	    $elem->{at}->{sym} = "_$sy[0]$sy[1]";
	} elsif ($op[0] == 0) {  # paren, anonymous array
	    $elem->{at}->{sym} = "$sy[0]_$sy[1]";
	} elsif($sy[0] eq "?") { # tertiary operator
	    $elem->{at}->{sym} = "_$sy[0]_$sy[1]_";
	} else {  # named array
	    $elem->{at}->{sym} = "_$sy[0]_$sy[1]";
	}

    }
    $elem->{ref}->{operand} = \@ch;
}

sub opt_stmt() {
    my $elem = shift;
    my $top = $elem->{e}->[0];

    my @ch = &getObjIndex($elem);

    if (!&isObj($elem->{e}->[-1]) &&  $elem->{e}->[-1] =~ /^SC\b/) {
	if ($top =~ /^CMD/) {
	    $elem->{t} = "ST_CMD";
	    $elem->{ref}->{args} = \@ch;
	} elsif ($top =~ /^RE_JP/) {
	    $elem->{t} = "ST_JUMP";
	    $elem->{ref}->{args} = \@ch;
	} else {
	    $elem->{t} = "ST_EXPR";
	    $elem->{ref}->{expr} = 0;
	}
	return;
    }

    if (&isObj($top)) {
	print Dumper $elem;
	die "illegal format of statement." ;
    }

    if (my ($tp, $tk) = ($top =~ /^CT_(IF|BE)\s+<(\w+)>/)) {
	if ($tp eq "IF") {
	    $elem->{t} = "ST_IF";
	} else {
	    $elem->{t} = "ST_" . uc($tk);
	}
	return unless ($ch[0]);
	if ($elem->{t} eq "ST_FOR") {
	    @ch = ();
	    my $has_expr = 0;
	    for (my $j = $ch[0]; $j < @{$elem->{e}}; $j++) {
		if ($elem->{e}->[$j] =~ /^(?:SC|P_R)/) {
		    push(@ch, -1) unless ($has_expr);
		    $has_expr = 0;
		} elsif (&isObj($elem->{e}->[$j])) {
		    push(@ch, $j);
		    $has_expr = 1;
		}
	    }
	    $elem->{ref}->{body} = pop(@ch);
	    $elem->{ref}->{cond} = \@ch;
	} elsif ($elem->{t} eq "ST_IF") {
	    while (@ch) {
		my $b = {};
		$b->{cond} = shift @ch if @ch > 1;
		$b->{body} = shift @ch;
		push(@{$elem->{ref}->{block}}, $b);
	    }
	} elsif ($elem->{t} =~ /^ST_(WHILE|SWITCH)/) {
	    $elem->{ref}->{cond} = $ch[0];
	    $elem->{ref}->{body} = $ch[1];
	}
    } elsif ($top =~ /^CT_DO/) {
	$elem->{t} = "ST_DO";
	if ($ch[1]) {
	    my $c = $elem->{e}->[$ch[1]]->{e};
	    my $j = 0;
	    $j++ while (!&isObj($c->[$j]) && $j < @$c);
	    $elem->{ref}->{cond} = $ch[1] + $j if $j < @$c;
	    splice(@{$elem->{e}}, $ch[1], 1, @$c);
	}
    } elsif ($top =~ /^CT_TRY/) {
	$elem->{t} = "ST_TRY";
	$elem->{ref}->{body} = shift @ch;
	while (@ch > 1) {
	    my $c = { type => shift @ch, var => shift @ch, body => shift @ch };
	    push(@{$elem->{ref}->{catch}}, $c);
	}
	push(@{$elem->{ref}->{finally}}, shift @ch) if (@ch);

	# flatten types and variables.
	foreach (@{$elem->{ref}->{catch}}) {
	    splice(@{$elem->{e}}, $_->{type}, 1,
		   @{$elem->{e}->[$_->{type}]->{e}});
	    splice(@{$elem->{e}}, $_->{var}, 1,
		   @{$elem->{e}->[$_->{var}]->{e}});
	}
    } elsif ($top =~ /^C_L/) {
	$elem->{t} = "ST_COMP";
	$elem->{ref}->{stmt} = \@ch;
    } elsif ($top =~ /^ID_L\s<(.*)>$/) { # goto label
	$elem->{t} = "ST_LABEL";
	$elem->{ref}->{label} = 0;
	$elem->{at}->{label} = $1;
	$elem->{ref}->{body} = $ch[0];
    } elsif ($top =~ /^RE_LC/) { # case label
	$elem->{t} = "ST_CASE";
	$elem->{ref}->{label} = $ch[0];
	$elem->{ref}->{body} = $ch[1];
    } elsif ($top =~ /^RE_LD/) { # default label
	$elem->{t} = "ST_DEFAULT";
	$elem->{ref}->{body} = $ch[0];
    } # else { it may be unterminated statement, but do nothing for it; }
}

sub opt_func() {
    my $elem = shift;
    my $el = $elem->{e};

    my $i = 0;
    while ($i < @$el) {
	if ($el->[$i] =~ /^ID_C\s+<(\w+)>$/) {
	    $elem->{at}->{name} = $1;
	    # Should the attribute hold the index number of funciton name?
	} elsif ($el->[$i] =~ /^ID_TP\s+<(\w+)>$/) {
	    $elem->{at}->{type} = $1;
	} elsif ($el->[$i] =~ /^OP\s+<&>$/) {
	    $elem->{at}->{return_ref} = $i;
	} elsif (&isObj($el->[$i])) {
	    if ($el->[$i]->{t} eq "ARG") {
		push(@{$elem->{ref}->{arg}}, $i);
	    } else {
		$elem->{ref}->{body} = $i;
	    }
	}
	$i++;
    }
}

sub opt_arg() {
    my $elem = shift;
    my $el = $elem->{e};

    my $i = 0;
    while ($i < @$el) {
	if (&isObj($el->[$i]) && $el->[$i]->{t} eq "P") {
	    # for passing a variable by reference, using & operator.
	    splice(@$el, $i, 1, @{$el->[$i]->{e}});
	    $elem->{at}->{by_reference} = $i;
	} elsif ($el->[$i] =~ /^ID_TP\s+<(\w+)>$/) {
	    $elem->{at}->{type} = $1; # No need?
	    $elem->{ref}->{type} = $i;
	} elsif ($el->[$i] =~ /^ID_V\s+<(\S+)>$/) {
	    $elem->{at}->{var} = $1; # No need?
	    $elem->{ref}->{var} = $i;
	}
	$i++;
    }
}

sub opt_class() {
    my $elem = shift;
    my $el = $elem->{e};

    my $met_extends = 0;
    my $i = 0;
    while ($i < @$el) {
	if ($el->[$i] =~ /^RE_EX\s/) {
	    $met_extends = 1;
	} elsif ($el->[$i] =~ /^ID_C\s+<(\w+)>$/) {
	    if ($met_extends) {
		$elem->{at}->{extends} = $1;
		$elem->{ref}->{extends} = $i;
	    } else {
		$elem->{at}->{name} = $1;
		$elem->{ref}->{name} = $i;
	    }
	} elsif (&isObj($el->[$i])) {
	    if ($el->[$i]->{t} eq "CP") {
		push(@{$elem->{ref}->{proparty}}, $i);
	    } elsif ($el->[$i]->{t} eq "F") {
		push(@{$elem->{ref}->{function}}, $i);
	    }
	}
	$i++;
    }
}

sub opt_namespace() {
    my $elem = shift;
    my $el = $elem->{e};

    my $i = 0;
    while ($i < @$el) {
	if ($el->[$i] =~ /^ID_C\s+<(\w+)>$/) {
	    $elem->{at}->{name} = $1;
	    $elem->{ref}->{name} = $i;
	} elsif (&isObj($el->[$i])) {  # something exists in the namespace
	    push(@{$elem->{ref}->{item}}, $i);
	}
	$i++;
    }
}

sub opt_use() {
    my $elem = shift;
    my $el = $elem->{e};

    for (my $i = 0; $i < @$el; $i++) {
	my $ch = $el->[$i];
	next unless (&isObj($ch));
	if ($ch->{e}->[0] =~ /^C_L/) {
	    $elem->{ref}->{conf} = $i;
	} else {
	    push(@{$elem->{ref}->{expr}}, $i);
	}
	$i++;
    }


}
# Types of 'use'
# - 'use' for including namespaces
# - 'use' for including trait in a class
# - 'use' for a closure

sub opt_file() {
    my $elem = shift;
    my @e = @{$elem->{e}};
    @{$elem->{ref}->{obj}} = grep(&isObj($e[$_]), 0..$#e);
}

sub isObj() {
    return ref($_[0]) eq "HASH";
}

sub getObjIndex() {
    my $elem = shift;
    return grep(&isObj($elem->{e}->[$_]), 0..($#{$elem->{e}}));
}

my $_objid;
sub createObj() {
    return { t => '', e => [ ], id => ++$_objid };
}

sub genObj() {
    my $tk = shift;
    my $tp;
    my $t = shift @$tk;
    if ($t =~ /^B_(\w+)/) {
	$tp = $1;
    } elsif ($t =~ /^UNIT_BEGIN/) {
	$tp = "UNIT";
    } else {
	die "Illegal block begin.: $tk->[0]";
    }
    my $obj = &createObj();
    $obj->{t} = $tp;
    while (@$tk && $tk->[0] !~ /^(E_|UNIT_)/) {
	if ($tk->[0] =~ /^B_/) {
	    push(@{$obj->{e}}, &genObj($tk));
	} else {
	    $t = shift @$tk;
	    push(@{$obj->{e}}, $t);
	}
    }
    $t = shift(@$tk);
    return $obj;
}

1;

    
