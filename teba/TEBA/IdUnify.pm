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

package IdUnify;
use strict;
#use warnings;
#### *** Note: id duplication occurs.

# Id Unifier for TEBA.

# IdUnify unifies IDs in two token sequences, A and B.
# All IDs in B corresponding to IDs in A will be converted into ones in A.
# No-corresponding IDs in both A and B will be added 'X[AB]' at the end.

use Algorithm::Diff;

sub new() {
    my $self = {};
    bless $self;

    $self->{match} = sub {
	my $ta = $self->{a}->[ $self->{pfx} + $_[0] ];
	my $tb = $self->{b}->[ $self->{pfx} + $_[1] ];
#	print "Match: $ta <=> $tb\n";
	my @tka = &split_token($ta);
	my @tkb = &split_token($tb);
	if ($tka[1] =~ /^%/ && $tkb[1] =~ /^%/) {
#	    print "Pair: ($tka[1], $tkb[1])\n";
	    push(@{$self->{pair}}, "$tka[1], $tkb[1]");
	}
    };

    return $self;
}

sub keygen() {
    my $t = shift;
    if ( $t =~ /<\$\{(\w+)(\:\w+)?\}>/ ){  # pattern variables
	return $1;
    }
    my @tk = &split_token($t);
    $tk[1] =~ s/\%\w+//g;
    return join('', @tk);
}

my $debug_on = 0;
sub debug_on()
{
    my $self = shift;
    $debug_on = 1;
    return $self;
}

sub split_token()
{
    my $t = shift;
    if ($t =~ /^(\w+\s+)([#%]\w+)?(.*)$/) {
	return ($1, $2, $3); # (type, id, text)
    }
    return ($t);
}

sub escape_id() {
    my $t = shift;
    my @tk = &split_token($t);
    $tk[1] =~ s/#/%/g;               # % is not used in ID, I belive.
    return join('', @tk);
}

sub unescape_id() {
    my ($t, $mark) = @_;
    my @tk = &split_token($t);
    $tk[1] =~ s/%(\w+)/#${1}$mark/g;     # the format of unmatched IDs
    return join('', @tk);
}

sub set() {  # set token sequences A and B.
    my $self = shift;
    ($self->{a}, $self->{b}) = @_;  # should be reference of array.
    return $self;
}

sub get_a() {
    my $self = shift;
    return @{$self->{a}};
}

sub get_b() {
    my $self = shift;
    return @{$self->{b}};
}

sub fix_id() {
    my ($self, $FRQ) = @_;

    if ($debug_on) {
	my $pcount = (defined($self->{pair}) ? int(@{$self->{pair}}) : 0);
	print STDERR "FRQ$FRQ: counting pairs ($pcount)\n";
    }

    my (%pairs, %repA, %repB);
    foreach (@{$self->{pair}}) { $pairs{$_}++; }

    foreach (@{$self->{pair}}) {
	next if ($pairs{$_} < $FRQ);
	m/^(%\w+), (%\w+)/;
	my ($id1, $id2) = ($1, $2);
	next if ($repA{$id1} || $repB{$id2});
	$repA{$id1} = $repB{$id2} = $id1;
    }

    printf STDERR "FRQ$FRQ: replacing %d ids\n", int(keys %repA) if $debug_on;

    for (my $i = $self->{pfx}; $i < @{$self->{a}}; $i++) {
	my @tk = &split_token($self->{a}->[$i]);
	next if (!$repA{$tk[1]});
	$tk[1] = $repA{$tk[1]};
	$tk[1] =~ s/^%/#/;
	$self->{a}->[$i] = join('', @tk);
    }
    for (my $i = $self->{pfx}; $i < @{$self->{b}}; $i++) {
	my @tk = &split_token($self->{b}->[$i]);
	next if (!$repB{$tk[1]});
	$tk[1] = $repB{$tk[1]};
	$tk[1] =~ s/^%/#/;
	$self->{b}->[$i] = join('', @tk);
    }
}


sub unify() {    # quick version: but may be a little low accuracy.
    my $self = shift;

    my $FRQ = 2;  # The minimum number of occurences of a pair for unification.
    # All pairs whose number is larger equal than $FRQ becomes unified pairs.

    print STDERR "Escaping ids...\n" if $debug_on;
    foreach (@{$self->{a}}) { $_ = &escape_id($_); }
    foreach (@{$self->{b}}) { $_ = &escape_id($_); }

    # find the same prefix sequence for skipping the later phase.
    print STDERR "Finding the first candidate ids in prefix ...\n" if $debug_on;
    $self->{pair} = undef;
    my $pfx;
    for ($pfx = 0; $pfx < @{$self->{a}} && $pfx < @{$self->{b}}; $pfx++) {
	my ($ta, $tb) = ($self->{a}->[$pfx], $self->{b}->[$pfx]);
	last if $ta ne $tb;
	my @tka = &split_token($ta);
	my @tkb = &split_token($tb);
	if ($tka[1] =~ /^%/ && $tkb[1] =~ /^%/) {
#	    print "Pair: ($tka[1], $tkb[1])\n";
	    push(@{$self->{pair}}, "$tka[1], $tkb[1]");
	}
    }
    print STDERR "Prefix sequence is 0..$pfx\n" if $debug_on;
    $self->fix_id(0);
    $self->{pfx} = $pfx;

    do {
	$self->{pair} = undef;
	my @a = @{$self->{a}}[$pfx..$#{$self->{a}}];
	my @b = @{$self->{b}}[$pfx..$#{$self->{b}}];

	print STDERR "FRQ$FRQ: traversing sequences ",
	   sprintf("%d x %d = %d (original: %d x %d = %d)", 
		   int(@a), int(@b), @a * @b,
		   int(@{$self->{a}}), int(@{$self->{b}}),
		   @{$self->{a}} * @{$self->{b}}), "\n" if $debug_on;
	Algorithm::Diff::traverse_sequences(\@a, \@b,
					    { MATCH => $self->{match} },
					    \&keygen);
	$self->fix_id($FRQ--);
    } while (@{$self->{pair}});

    print STDERR "Unescaping remained ids....\n" if $debug_on;
    foreach (@{$self->{a}}) { $_ = &unescape_id($_, "XA"); }
    foreach (@{$self->{b}}) { $_ = &unescape_id($_, "XB"); }
}

1;
