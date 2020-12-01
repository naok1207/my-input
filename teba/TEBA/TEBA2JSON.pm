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

package TEBA2JSON;

use strict;
use warnings;
no warnings 'recursion';

use JSON;
use Data::Dumper;

use Carp qw( confess);

my %optf;
sub init_opt() {
    %optf = ( "FUNC" => \&opt_func,
	      "ST"   => \&opt_stmt,
	      "DE"   => \&opt_decl,
	      "P"    => \&opt_expr,
	      "TD"   => \&opt_decl, # almost same with DE
	      "DIRE" => \&opt_dire,
	);
}


BEGIN {
    &init_opt();
    $SIG{__DIE__} = \&confess;
    $SIG{__WARN__} = \&confess;
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


########################################################################

sub optimize() {
    my $elem = shift;

    &{$optf{$elem->{t}}}($elem) if $optf{$elem->{t}};

    map(&optimize($_), grep(&isObj($_), @{$elem->{e}}));
}

sub opt_expr() {
    my $elem = shift;

    my $top = $elem->{e}->[0];
    return unless defined $top;  # empty expression
    if (&isObj($top)) {
	if ($top->{t} eq "FR") {  # function call
	    $elem->{e} = $top->{e};
	    my @ch = &getObjIndex($elem);
	    $elem->{call} = shift(@ch);
	    $elem->{arg} = \@ch;
	    return;
	} elsif ($top->{t} eq "CAST") { # cast expression;
	    my @ch = &getObjIndex($elem);
	    $elem->{sym} = "T_";
	    $elem->{op} = $ch[0];
	    $elem->{operand} = [ $ch[1] ];
	    return;
	} elsif ($top->{t} eq "CP") { # initializer list
	    $elem->{e} = $top->{e};
	    $elem->{t} = "CP";
	    return;
	}
    } else {
	if ($top =~ /^(ID_\w+)\s+<(.*)>$/) {  # variable reference
	    $elem->{t} = $1;
	    $elem->{name} = $2;
	    return;
	}
	if ($top =~ /^(LI\w+)\s+<(.*)>$/) {   # literature
	    $elem->{t} = $1;
	    $elem->{value} = $2;
	    return;
	}
    }


    # expression with an operator.
    my @ch = &getObjIndex($elem);
    if (!&isObj($top) && $top =~ /^P_L/) {  # parentheses
	if (@ch > 1) { # has objects spearated by commas
	    my ($head, $tail) = (1, $#{$elem->{e}}-1);
	    ++$head while ($elem->{e}->[$head] =~ /^SP/);
	    --$tail while ($elem->{e}->[$tail] =~ /^SP/);
	    my $obj = &createObj();  # generage a comma expression.
	    $obj->{t} = "P";
	    push(@{$obj->{e}},
		 splice(@{$elem->{e}}, $head, $tail-$head+1, $obj));
	    @ch = &getObjIndex($elem);
	}
    }

    my (@op, @sy);
    foreach my $i (0..$#{$elem->{e}}) {
	my $t = $elem->{e}->[$i];
	if (&isObj($t)) {
	    push(@sy, "_");
	} elsif ($t =~ /^(?:OP|[AP]_|CA).*\s<(.*)>$/) {
	    push(@op, $i);
	    push(@sy, $1);
	} elsif ($t =~ /^SP/) {
	    # do nothing
	} else {
	    # something wrong. Illegal expression.
	    # Ex. typedef int T; f((T)); #expression (T) has no operator
	    return;
	}
    }

    if (@op == 0) { # no operator, may be an illegal expression
	return;
    }

    $elem->{op} = \@op;  # a tertiary operator has two symbols.
    $elem->{sym} = join("", @sy);
    if (0) {
    if (@op == 1) {
	if (@ch == 2) {
	    $elem->{sym} = "_$sy[0]_";
	} else {  # (@ch == 1)
	    $elem->{sym} = $op[0] < $ch[0] ? "$sy[0]_" : "_$sy[0]";
	}
    } else { # (@op == 2)
	if ($sy[0] eq '[' && @ch == 1) {  # array but no index.
	    $elem->{sym} = "_$sy[0]$sy[1]";
	} elsif ($sy[0] eq '(' && @ch == 0) {
	    # typedef int T; f((T)); #expression (T) has no operator
	    # this is an illegal case.
	} elsif (@ch == 1 && @op == 2) {  # paren
	    $elem->{sym} = "$sy[0]_$sy[1]";
	} elsif (@ch == 2) {  # array
	    $elem->{sym} = "_$sy[0]_$sy[1]";
	} else { # (@ch >= 3),  tertiary operator or multiple commas
	    $elem->{sym} = "_" . join("_", @sy) ."_";
	}
    }
    }
    $elem->{operand} = \@ch;
}

sub opt_stmt() {
    my $elem = shift;
    my $top = $elem->{e}->[0];

    my @ch = &getObjIndex($elem);

    if (!&isObj($top) && (my ($tp, $tk) = ($top =~ /^CT_(IF|BE)\s+<(\w+)>/))) {
	if ($tp eq "IF") {
	    $elem->{t} = "ST_IF";
	} else {
	    $elem->{t} = "ST_" . uc($tk);
	}
	if (defined $ch[0]) {
	    my $c = $elem->{e}->[$ch[0]]->{e};
	    my $cond_len = @{$c} - 1;
	    splice(@{$elem->{e}}, $ch[0], 1, @$c);

	    if ($elem->{t} eq "ST_FOR") {
		&split_list_by($elem, 0, "SC");
		foreach (@{$elem->{e}}) {
		    $_->{t} = "DE" if (&isObj($_) && defined $_->{e}->[0] && $_->{e}->[0] =~ /ID_TP/);
		}
		@ch = &getObjIndex($elem);
		$elem->{body} = pop(@ch);
		$elem->{cond} = \@ch;
	    } else {
		my $j;
		for ($j = 0; !&isObj($c->[$j]) && $j < @$c; $j++) {}
		if ($elem->{t} eq "ST_IF") {
		    $elem->{cond} = $ch[0] + $j if $j <@$c;
		    $elem->{then} = $ch[1] + $cond_len if defined $ch[1];
		    $elem->{else} = $ch[2] + $cond_len if defined $ch[2];
		} elsif ($elem->{t} =~ /^ST_(WHILE|SWITCH)/) {
		    $elem->{cond} = $ch[0] + $j if $j <@$c;
		    $elem->{body} = $ch[1] + $cond_len;
		}
	    }
	}
    } elsif (!&isObj($top) && $top =~ /^CT_DO/) {
	$elem->{t} = "ST_DO";
	if (defined $ch[0]) {
	    $elem->{body} = $ch[0];
	}
	if (defined $ch[1]) {
	    my $c = $elem->{e}->[$ch[1]]->{e};
	    my $len = @{$c} - 1;
	    my $j;
	    for ($j = 0; !&isObj($c->[$j]) && $j < @$c; $j++) {}
	    $elem->{cond} = $ch[1] + $j if $j < @$c;
	    splice(@{$elem->{e}}, $ch[1], 1, @$c);
	}
    } elsif (&isObj($top) && $top->{t} eq "LB") {
	$elem->{t} = "ST_LABELED";
	my $label = $elem->{e}->[$ch[0]]->{e};
	my $label_len = @{$label} - 1;
	splice(@{$elem->{e}}, $ch[0], 1, @$label);
	$elem->{label} = $ch[0];
	if ($label->[0] =~ /^RE_LC/) { # case label
	    my $j;
	    for ($j = 0; !&isObj($label->[$j]) && $j <@$label; $j++) {};
	    $elem->{label} += $j;
	}
	$elem->{body} = $ch[1] + $label_len;
    } elsif (!&isObj($top) && $top =~ /^C_L/) {
	$elem->{t} = "ST_COMP";
	$elem->{stmt} = \@ch;
    } elsif (!&isObj($top) && $top =~ /^RE_JP/) {
	$elem->{t} = "ST_JUMP";
	$elem->{value} = $ch[0] if defined $ch[0];;
    } elsif (!&isObj($elem->{e}->[-1]) && $elem->{e}->[-1] =~ /^SC\b/) {
	$elem->{t} = "ST_EXPR";
	if (@ch > 1) { # has objects spearated by commas
	    my ($head, $tail) = (0, $#{$elem->{e}}-1);
	    ++$head while ($elem->{e}->[$head] =~ /^SP/);
	    --$tail while ($elem->{e}->[$tail] =~ /^SP/);
	    my $obj = &createObj();  # generage a comma expression.
	    $obj->{t} = "P";
	    push(@{$obj->{e}},
		 splice(@{$elem->{e}}, $head, $tail-$head+1, $obj));
	    $elem->{expr} = $head;
	} elsif (defined $ch[0]) {
	    $elem->{expr} = $ch[0];
	}
    } # else { it may be unterminated statement, but do nothing for it; }
}

sub opt_decl() {
    my $elem = shift;

    my @ch = &getObjIndex($elem);
    my @tp = @{$elem->{e}};
    @tp = grep(s/^ID_TP.*<(\w+)>$/$1/, @tp);

    $elem->{type} = \@tp;
    $elem->{decr} = \@ch;
}

sub opt_func() {
    my $elem = shift;
    my $el = $elem->{e};

    # flatten FD
    splice(@{$el}, 0, 1, @{$el->[0]->{e}});

    my $i = 0;

    # type
    while ($i < @$el) {
	$i++ while ($el->[$i] =~ /^SP/);

	if ($el->[$i] =~ /^ID_TP.*<(\w+)>$/) {
	    push(@{$elem->{type}}, $1);
	} elsif ($el->[$i] =~ /^ATTR.*<(\w+)>$/) {
	    push(@{$elem->{type}}, $1);
	    do { $i++; } while ($el->[$i] =~ /^SP/);
            #skip expression for attribute
	    ++$i if (&isObj($el->[$i]) && $el->[$i]->{t} eq "P");
	} elsif ($el->[$i] =~ /<(.*?)>$/) {
	    push(@{$elem->{type}}, $1);
	} elsif ($el->[$i]->{t} eq "SCT") {
	    my @t = grep(/^ID_TAG/, @{$el->[$i]->{e}});
	    if ($t[0] =~ /^ID_TAG.*<(\w+)>/) {
		push(@{$elem->{type}}, "struct $1");
	    }
	} elsif ($el->[$i]->{e}->[0] =~ /^OP_U\s+<(.*)>$/) {
	    push(@{$elem->{type}}, $1);
	    splice(@{$el}, $i, 1, @{$el->[$i]->{e}});
	} elsif ($el->[$i]->{t} eq "P") { # flatten P
	    splice(@{$el}, $i, 1, @{$el->[$i]->{e}});
	    next;
	} elsif ($el->[$i]->{t} eq "FR") {
	    last;
	}
	$i++;
    }
    return if $i >= @$el;  # give up optimizing

    # flatten FR;
    splice(@{$el}, $i, 1, @{$el->[$i]->{e}}) if exists $el->[$i]->{e};

    # function name, which is an expression element.
    $elem->{name} = $i++;

    &split_list_by($elem, $i, "CA");
    my $arg_body = [];
    foreach (my $j = $i; $j < @$el; $j++) {
	next unless &isObj($el->[$j]);
	push(@$arg_body, $j);
    }
    $elem->{body} = pop(@$arg_body);
    $elem->{arg} = $arg_body;
    $el->[$_]->{t} = "DE" foreach (@$arg_body);
}

sub opt_dire {
    my $elem = shift;
    my $el = $elem->{e};

    foreach my $i (0..$#{$el}) {
	if ($el->[$i] =~ /^PRE_DIR\s+<(\w+)>/) {
	    $elem->{t} = "DIRE_".uc($1);
	    last;
	}
    }
    my @ch = &getObjIndex($elem);
    if ($elem->{t} eq "DIRE_DEFINE") {
	$elem->{mc} = shift @ch if @ch > 0;
	$elem->{def} = shift @ch if @ch > 0;
	splice(@{$el}, $elem->{mc}, 1, @{$el->[$elem->{mc}]->{e}})
	    if (&isObj($el->[$elem->{mc}]->{e}->[0])); # macro with arguments
	my $fr = $el->[$elem->{mc}];
	if (&isObj($fr) && $fr->{t} eq "FR") {
	    my @ch = &getObjIndex($fr);
	    $fr->{name} = shift(@ch);
	    foreach (@ch) {
		my $obj = &createObj();
		$obj->{t} = "DE";
		push(@{$obj ->{e}}, $fr->{e}->[$_]);
		$fr->{e}->[$_] = $obj;
	    }
	}
    } else {
	$elem->{cond} = $ch[0];
    }
}


########################################################################

sub split_list_by {
    my ($elem, $j, $sep) = @_;
    my @ind;
    for (; $j < @{$elem->{e}}; $j++) {
	push(@ind, $j) if ($elem->{e}->[$j] =~ /^(P_[LR]|$sep)/);
    }
    for (my $j = $#ind; $j > 0; $j--) {
	my $s = $ind[$j-1] + 1;
	my $e = $ind[$j] - 1;
	next unless ($s<=$e);
	$s++ while ($s <= $e && $elem->{e}->[$s] =~ /^SP/);
	$e-- while ($s <= $e && $elem->{e}->[$e] =~ /^SP/);
	next if $s == $e;  # exists only one element.

	my $obj = &createObj();
	$obj->{t} = "P";
	push(@{$obj->{e}},
	     splice(@{$elem->{e}}, $s, $e-$s+1, $obj));
    }
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

sub createTagObj() {
    my ($tk, $tag) = @_;
    return { t => 'TAG', e => [ $tk ], id => "", tag => $tag };
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
    do  {
	if ($tk->[0] =~ /^B_/) {
	    push(@{$obj->{e}}, &genObj($tk));
	} else {
	    $t = shift @$tk;
	    if ($t =~ /^SP_TAG\t<(.*)>$/) {
		push(@{$obj->{e}}, &createTagObj($t, $1));
	    } else {
		push(@{$obj->{e}}, $t);
	    }
	}
    } while (@$tk && $tk->[0] !~ /^(E_|UNIT_)/);
    $t = shift(@$tk);
    return $obj;
}

sub getTokens() {
    my $elem = shift;
    return map(&isObj($_) ? &getTokens($_) : $_, @{$elem->{e}});
}

sub tokenize {
    my $el = shift;
    my $be; my $en;
    if ($el->{t} eq "UNIT") {
	$be = "UNIT_BEGIN\t<>";
	$en = "UNIT_END\t<>";
    } elsif (&isObj($el)) {
	my $bid = sprintf("#%04d", $el->{id});
	$be = "B_$el->{t} $bid\t<>";
	$en = "E_$el->{t} $bid\t<>";
    }
    return ($be, map(&isObj($_) ? &tokenize($_) : $_, @{$el->{e}}), $en);
}


1;
