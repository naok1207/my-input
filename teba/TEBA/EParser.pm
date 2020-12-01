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

package EParser;

use Data::Dumper;
use FindBin qw($Bin);

use strict;
use warnings;

use RewriteTokens;

sub new() {
    my $self = {};
    bless $self;
    $self->{types} = "";
    return $self;
}

sub use_flat() {
    my $self = shift;
    $self->{"use_flat"} = 1;
    return $self;
}

sub add_types() {
    my $self = shift;
    $self->{types} .= join("\n", @_)."\n";
   return $self;
}

sub add_overrided_types() {
    my $self = shift;
    $self->{overrided_types} .= join("\n", @_)."\n";
   return $self;
}

sub build() {
    my $self = shift;
#    my $path = "$Bin/../TEBA";
    (my $path = $INC{__PACKAGE__ . ".pm"}) =~ s/[^\/]+$//;

    $self->{base} = RewriteTokens->seq($self->{types})
	->load("$path/expr-base.rules")
	->add_rules($self->{overrided_types});

    $self->{p01} = RewriteTokens->seq($self->{types})
	->load("$path/expr-p01.rules")
	->add_rules($self->{overrided_types});

    $self->{p02} = RewriteTokens->rep($self->{types})
	->load("$path/expr-p02.rules")
	->add_rules($self->{overrided_types});

    $self->{"p03-12"} = RewriteTokens->seq($self->{types})
	->load("$path/expr-p03-12.rules")
	->add_rules($self->{overrided_types});

    $self->{p13} = RewriteTokens->rep($self->{types})
	->load("$path/expr-p13.rules")
	->add_rules($self->{overrided_types});

    $self->{p14} = RewriteTokens->seq($self->{types})
	->load("$path/expr-p14.rules")
	->add_rules($self->{overrided_types});

#    $self->{p15}  = RewriteTokens->seq($self->{types})
#	->load("$path/expr-p15.rules");

    # cleanup; Caution: Occurrences of _[EB]_X may remain by errors.
    $self->{cleanup} = RewriteTokens->seq(
	q( { $b:_B_X } => { $b:B_P } { $b:_E_X } => { $b:E_P } ));

    if ($self->{"use_flat"}) {
	$self->{flat} = RewriteTokens->seq($self->{types})
	    ->load("$path/expr-flat.rules")
	    ->add_rules($self->{overrided_types});
    }
    return $self;
}

sub parse() {
    my ($self, $tokens) = @_;

    $self->build() if !exists $self->{base};

    $tokens = $self->{base}->rewrite($tokens);
    $tokens = $self->{p01}->rewrite($tokens);
    $tokens = $self->{p02}->rewrite($tokens);
    $tokens = $self->{"p03-12"}->rewrite($tokens);
    $tokens = $self->{"p13"}->rewrite($tokens);
    $tokens = $self->{"p14"}->rewrite($tokens);
    # Parsing comma operators may not be useful, becuase all expressions
    # separated by commas are surrounded by B_P and E_P.
#    $tokens = $self->{"p15"}->rewrite($tokens);

    $tokens = $self->{cleanup}->rewrite($tokens);

    if ($self->{"use_flat"}) {
	$tokens = $self->{flat}->rewrite($tokens);
    }

    return $tokens;
}

1;
