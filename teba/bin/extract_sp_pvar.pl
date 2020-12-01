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

use JSON;

use FindBin qw($Bin);
use lib "$Bin/../TEBA";

use TEBA2TEXT;

use Getopt::Std;
my %opts = ();

$opts{h} = 1 unless getopts("ht", \%opts);

if ($opts{h}) {
    print STDERR " extract_sp_pvar.pl -- extract matched variables \n\n",
	" extract_sp_pvar.pl [-th] [file ...]\n",
	"  -h : Print this help.\n",
	"  -t : join tokens for each varaible.\n";
    exit(1);
}
$| = 1 if $opts{d}; # flash at error;

while (<>) {
    next unless (/^SP_PVAR\s+<(.*)>$/);
    my $json = decode_json($1);

    if ($opts{t}) {
	foreach my $v (keys %$json) {
	    my $tk = $json->{$v};
	    $json->{$v} = TEBA2TEXT->new()->set_teba(join("\n", @$tk))->text();
	    
	}
    }

    print JSON->new->utf8->pretty->encode($json);
}

