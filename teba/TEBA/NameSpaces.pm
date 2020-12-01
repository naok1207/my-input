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

package NameSpaces;

use strict;
use warnings;

# This is an experimental filter. Ideally, filters in this package should be defined
# by token based rules, or generated from specialized rewriting rules.

sub new()
{
    my $self = {};
    bless $self;
    return $self;
}


# Rule: converts IDN to ID_MB in struct/union member declarations.
#
#{
#  $begin#1:B_SCT $struct:'struct' $tag:ANYEXPR $cl#2:C_L
#    $any1:ANYDECL
#      $var:ID_VF
#    $any2:ANYDECL
#    $cr#2:C_R
#  $end#1:E_SCT
#} => {
# $begin $struct $tag $cl
#    $any1
#      $var:ID_MB
#    $any2
#    $cr
#  $end
#}
# This rule takes an awful lot of time to match the token sequence.
# The following filter is optimzed version of this rule.
# It avoids to convert identifers in array size declarators.
sub id_member()
{
    my ($self, $code) = @_;
    my @struct_stack = ();
    my $arr = 0;
    my @code = split(/\n/, $code);
    foreach (@code) {
	if (/^B_SUE\s+(\#\w+)\s+<>/) {
	    push(@struct_stack, $1);
	} elsif (/^E_SUE/) {
	    pop(@struct_stack);
	} elsif (/^A_L/) {
	    $arr++;
	} elsif (/^A_R/) {
	    $arr--;
	} elsif (!$arr && @struct_stack > 0) {
	    $_ =~ s/^ID_VF\b/ID_MB/;
	}
    }
    return join("\n", @code);
}

sub id_fix()
{
    my ($self, $code) = @_;

    my $target = qr/^ID(?:N|_TP|_VFT?|_MC)\b/;

    my @code = split(/\n/, $code);

    my %type; my %name;
    foreach (grep(/$target/, @code)) {
	m/^(\w+)\s+<(.*)>$/;
	my ($tk_t, $tk) = ($1, $2);
	$tk_t =~ s/ID_VFT/ID_TP/; # A typedef-ed type will be ID_TP.
	$type{$tk_t}->{$tk}++;
	$name{$tk}++;
    }

    my %ident;
    foreach (keys %name) {
	if (0) {
	    my $n = $_;
	    my @msg;
	    push(@msg, "NameSpaces:", $n);
	    foreach my $t ("ID_VF", "ID_TP", "ID_MC") {
		push(@msg, ($type{$t}->{$_} // 0));
	    }
	    print STDERR join(" ", @msg), "\n";
	}
	$ident{$_} = ($type{"ID_VF"}->{$_} ? "ID_VF" :
		      $type{"ID_TP"}->{$_} ? "ID_TP" :
		      $type{"ID_MC"}->{$_} ? "ID_MC" : "ID_VF");
    }

    foreach (@code) {
	s/^IDN\s+<(.*)>/$ident{$1}\t<$1>/;
    }

    return join("\n", @code);
}

sub mc_fix {
    my ($self, $code) = @_;

    my @code = split(/\n/, $code);
    my %macro;

    foreach (@code) {
	if (/^ID_MC\s+<(\w+)>$/) {
	    $macro{$1} = 1;
	} elsif (/^ID_\w+\s+<(\w+)>$/) {
	    if ($macro{$1}) {
		$_ = "ID_MC\t<$1>";
	    }
	}
    }
    return join("\n", @code);

}

1;
