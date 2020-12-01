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

package TEBA2TEXT;

use strict;
use warnings;

use Data::Dumper;

sub new() {
    my $self = bless {};
    if (defined $_[1]) {
	my $opts = $_[1];
	$self->{opt_d} = $opts->{d};
	$self->{opt_e} = $opts->{d} && !$opts->{E};
	$self->{opt_de} = $opts->{d} && $opts->{e};
    }
    return $self;
}

sub set_teba() {
    my $self = shift;
    my $text = shift;
    if (ref($text) eq "ARRAY") {
	$self->{coderef} = $text;
    } else { # should be ARRAY
	$self->{coderef} = [ split("\n", $text) ];
    }
    return $self;
}

sub text() {
    my $self = shift;
    my @res;

    foreach (@{$self->{coderef}}) {
	chomp;
	next unless (/^(\w+)(?:\s+(#\w+))?\s+<(.*)>$/);
	my ($t, $i, $s) = ($1, $2 || "", $3);
	$s = &ev($s);
	if ($t =~ /^B_[XP]/) {
	    if ($self->{opt_e}) {
		if ($self->{opt_de}) {
		    push(@res, $s);
		    push(@res, "\033[4;35m:$t$i\033[m") if $self->{opt_d};
		} else {
		    push(@res, "\033[0;35m{\033[m");
		}
	    }
	} elsif ($t =~ /^E_[XP]/) {
	    if ($self->{opt_e}) {
		if ($self->{opt_de}) {
		    push(@res, $s);
		    push(@res, "\033[4;35m:$t$i\033[m") if $self->{opt_d};
		} else {
		    push(@res, "\033[0;35m}\033[m");
		}
	    }
	} elsif ($t =~ /^[BE]_/) {
	    push(@res, $s);
	    push(@res, "\033[4;36m:$t$i\033[m") if $self->{opt_d};
	} elsif ($t =~ /^(P_|CA|SC)/) {
	    push(@res, $s);
	    push(@res, "\033[4;36m:$t$i\033[m") if $self->{opt_d};
	} elsif ($t =~ /^(SP|LIS)/) {
	    push(@res, $s);
	} elsif ($t !~ /^(RE_\w+)$/) {
	    push(@res, "".$s);
	    push(@res, qq(\033[4;32m:$t$i\033[m)) if $self->{opt_d};
	} else {
	    push(@res, $s) if $s;
	}
    }
    push(@res, "\n") if $self->{opt_d};

    return join("", @res);
}

sub ev()
{
    my $s = shift;
    my @r;
    while ($s ne "") {
	if ($s =~ s/^[^\\]+//) { push(@r, $&); }
	if ($s =~ s/^\\n//) { push(@r, "\n"); next; }
	if ($s =~ s/^\\t//) { push(@r, "\t"); next; }
	if ($s =~ s/^\\(.)//) { push(@r, $1); }
    }
    return join('', @r);
}

1;
