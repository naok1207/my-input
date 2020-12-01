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

package ProgReg;

use strict;
use warnings;

use ProgTrans;
use RewriteTokens;
use Tokenizer;

sub new() {
    my ($class, $opts, $pattern) = @_;
    my $self = bless {};
    $self->{opts} = $opts;
    if ($pattern) {
	$self->set($pattern);
    }
    return $self;
}

sub set() {
    my ($self, $pattern) = @_;
    my %pt_opts = ( 'e' => $self->{opts}->{e} );  # expression mode
    my $tr = ProgTrans->new(\%pt_opts);
    my $tk = $tr->gen_parser()->($pattern);
    $tk = $tr->normalize_spaces($tk);
    my @pt = $tr->gen_before_pattern($tk);
    $self->{pt} = \@pt;
    return $self;
}

sub build_search_pattern() {
    my $self = shift;
    my @b_pt = ('$[match:', q/'(?>':X/, @{$self->{pt}}, q/')':X/, '$]');
    my @a_pt = (q(''#2:M_B), '$match', q(''#2:M_E));

    my $rule = ProgTrans->gen_rules(\@b_pt, \@a_pt);
	   
    $self->{rewrite} = RewriteTokens->new()->seq()->set_rules($rule);
    return $self;
}

sub search() {
    my ($self, $tokens) = @_;
    $self->build_search_pattern();
    return $self->{rewrite}->rewrite($tokens);
}

sub build_parse_pattern() {
    my $self = shift;
    my @a_pt;
    foreach (@{$self->{pt}}) {
	next if /:SP$/;
	if (/^\$\[?(\w+):/) {
	    push(@a_pt, qq/'$1':NAME/, "\$$1");
	}
    }
    @a_pt = (q/'':M_B/, @a_pt, q/'':M_E/);
    my $rule = ProgTrans->gen_rules($self->{pt}, \@a_pt);
    my $vars = ProgTrans->default_vars();
    
    print "build_parse_pattern: $rule\n" if $self->{opts}->{d};
    $self->{rewrite} = RewriteTokens->seq($vars, $rule);
    return $self;
}

sub build_parse_tree() {
    my ($self, $tokens) = @_;
    my $in_match = 0;
    my ($name, @token);
    my $var;
    my @res;
    foreach (split(/\n/, $tokens)) {
	if (/^M_B/) {
	    $var = {};
	    $in_match = 1;
	} elsif (/^M_E/) {
	    foreach (keys %{$var}) {
		$var->{$_} = $var->{$_} ? join("\n", @{$var->{$_}})."\n" : "";
	    }
	    push(@res, $var);
	    $in_match = 0;
	} elsif ($in_match) {
	    if (/^NAME\s+<(\w+)>$/) {
		$name = $1;
		$var->{$name} = ();
	    } else {
		push(@{$var->{$name}}, $_);
	    }
	}
    }
    return @res;
}

sub parse() {
    my ($self, $tokens) = @_;
    $self->build_parse_pattern();
    $tokens = $self->{rewrite}->rewrite($tokens);
    my @res = $self->build_parse_tree($tokens);

    return @res;
}

sub strip() {  # remove unnecessary tokens
    my ($self, $tokens) = @_;
    my $rt = RewriteTokens->new()->seq()->set_rules(q(
@OUT => "(?:[^MU].*+\n)*"
{ $[e: $:M_E $| $:UNIT_BEGIN $] $any:OUT $[b: $:M_B $| $:UNIT_END $] }
=> { $e $b }
));
    return $rt->rewrite($tokens);
}

1;
