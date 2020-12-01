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
use lib "$Bin/../TEBA/";

use Getopt::Std;
use ProgTrans;

my $LIB = "$Bin/../TEBA/ProgPattern/";

my %opts;

if (!getopts("bep:rdsh", \%opts) || $opts{h}) {
    print STDERR "rewrite.pl [-dehrs] -p <pattern_file> [files...]\n",
                 "  -p <pattern_file> : specify a pattern file.\n",
                 "  -e: use branch analysis (requires -p for cparse.pl).\n",
                 "  -e: expression mode.\n",
                 "  -r: recursive transformation.\n",
                 "  -s: preserve white spaces in transformation.\n",
                 "  -d: debug mode.\n",
                 "  -h: help.\n";
    exit(1);
}

if (!$opts{p}) {
    die "no pattern specified by -p option.";
}
open(P, "<$opts{p}") || die "can't open $opts{p}.";
my $text = join('', <P>);
close(P);

my $pt = ProgTrans->new(\%opts)->set_pattern($text);

print $pt->rewrite(join('', <>))
