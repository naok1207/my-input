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

package CoarseGrainedParser;

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../TEBA";

use RewriteTokens;

sub new() {
    my $self = {};
    bless $self;
    $self->{types} = "";
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
    
    (my $path = $INC{__PACKAGE__ . ".pm"}) =~ s/[^\/]+$//;

    $self->{st1} = RewriteTokens->seq($self->{types})
	->load("$path/parser-stage1.rules")
	->add_rules($self->{overrided_types});
    $self->{st2} = RewriteTokens->seq($self->{types})
	->load("$path/parser-stage2.rules")
	->add_rules($self->{overrided_types});
    $self->{cs} = RewriteTokens->rep($self->{types})
	->load("$path/parser-condstmt.rules")
	->add_rules($self->{overrided_types});
    $self->{st3} = RewriteTokens->seq($self->{types})
	->load("$path/parser-stage3.rules")
	->add_rules($self->{overrided_types});
    return $self;
}

sub parse() {
    my ($self, $text) = @_;
    
    $self->build() if (!exists $self->{st1});

    $text = $self->{st1}->rewrite($text);
    $text = $self->{st2}->rewrite($text);
    $text = $self->{cs}->rewrite($text);
    $text = $self->{st3}->rewrite($text);
    return $text;
}

1;
