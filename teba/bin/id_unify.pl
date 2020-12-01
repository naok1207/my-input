#!/usr/bin/env perl
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

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../TEBA";

use IdUnify;

use Getopt::Std;
my %opts = ();
getopts("d", \%opts);

die "specify two file names." if (@ARGV < 2);

open(F, $ARGV[0]) || die "can't open file: $ARGV[0].";
my @a = <F>;
close(F);

open(F, $ARGV[1]) || die "can't open file: $ARGV[1].";
my @b = <F>;
close(F);

my $iu = IdUnify->new();
$iu->debug_on() if ($opts{d});
$iu->set(\@a, \@b);
$iu->unify();
#print map("$_\n", $iu->get_b());

open(W, ">$ARGV[0].unified") || die "can't open file for writing: $ARGV[0].unified.";
print W map("$_\n", $iu->get_a());
close(W);

open(W, ">$ARGV[1].unified") || die "can't open file for writing: $ARGV[1].unified.";
print W map("$_\n", $iu->get_b());
close(W);
