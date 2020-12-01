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


use FindBin qw($Bin);
use lib "$Bin/../TEBA";

use RewriteTokens;
use strict;
use warnings;

use Getopt::Std;
my %opts = ();

if (!getopts("df:p:", \%opts) || $opts{h}) {
    print STDERR "rewrite_token.pl [-dh] [-f <pattern_file>] [-p <pattern>] [files...]\n",
                 "  -f <pattern_file> : specify a pattern file.\n",
                 "  -p <pattern> : specify a pattern.\n",
                 "  -d: debug mode.\n",
                 "  -h: help.\n";
    exit(1);
}

my $debug = 1 if ($opts{"d"});
my $rule = qq(\@"token-patterns.def"\n);
if ($opts{"f"}) {
    open(F, "<$opts{f}") || die "can't open file: $opts{f}.";
    $rule .= join('', <F>). "\n";
    close(F);
}
$rule .= $opts{"p"}."\n" if ($opts{"p"});

my $rt = RewriteTokens->new();
$rt->set_rules($rule);

if ($debug) {
    print "Rules:\n$rule\n";
    print "Deump:\n". $rt->dump()."\n";
}

print $rt->rewrite(join('', <>));
