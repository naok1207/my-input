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

use CParser;

use Carp qw( confess);


use Getopt::Std;
my %opts = ();


if (!getopts("EfthpmjJgS:d", \%opts) || $opts{h}) {
    print STDERR "cparser.pl [-EfthpmjJ] [-g global_symbol_file ] [files...]\n",
                 "  -f: flatten expressions.\n",
                 "  -t: test mode.\n",
                 "  -E: disable analysis of expressions.\n",
                 "  -p: analyze preprocessor branch directives.\n",
                 "  -m: unifying macro identifiers.\n",
                 "  -j: output in JSON format.\n",
                 "  -J: output in raw JSON format.\n",
	         "  -g [ global_symbol_file ]: use the file as a predefined global symbol table.",
                 "  -S: disable generation of symbol table.\n",
                 "  -h: help.\n";
    exit(1);
}

$| = 1;

my $cp = CParser->new();
if ($opts{E}) {
    $cp->disable_expr();
}
if ($opts{f}) {
    $cp->use_flat_expr();
}
if ($opts{p}) {
    $cp->use_prep_branch();
}

if ($opts{j}) {
    $cp = $cp->as_json();
} elsif ($opts{J}) {
    $cp = $cp->as_raw_json();
}

if ($opts{g}) {
    $cp = $cp->set_global_symbol_table($opts{g});
}

unless ($opts{S}) {
    $cp = $cp->with_symboltable();
}

my $t = $cp->parse(join('', <>));

if ($opts{t}) {
#    $t .= $cp->check_validity($t);
    $cp->check_validity($t);
}

if ($opts{m}) {
    $t = NameSpaces->mc_fix($t);
}

if ($opts{d}) {
    $SIG{__DIE__} = \&confess;
}


print $t;
