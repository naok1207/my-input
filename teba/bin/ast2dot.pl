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
use Graphviz;

#use Data::Dumper;

use Getopt::Std;
my %opts = ();

if (!getopts("ph", \%opts) || $opts{h}) {
    print STDERR "ast2dot.pl [-ph] [json-based-ast-file]\n",
                 "  -p: output as PNG format.\n",
                 "  -h: help.\n";
    exit(1);
}


my $root = JSON->new->decode(join('', <>));

my $g = GraphViz->new();

&tree2dot($g, $root);

if ($opts{p}) {
    print $g->as_png;
} else {
    print $g->as_text;
}

sub tree2dot()
{
    my ($g, $el) = @_;

    my $label = &createLabel($el);
    $label =~ s/\"/\\"/g;  # GraphViz.pm has a bug escaping double quotes twice.
    $g->add_node($el->{id}, label => "$label");
    foreach my $ch (grep(&isObj($_), @{$el->{e}})) {
	&tree2dot($g, $ch);
	$g->add_edge($el->{id}, $ch->{id});
    }
    return $el;
}

sub createLabel()
{
    my $el = shift;
    if ($el->{t} =~ /^ID_/) {
	return $el->{t} . " : " . $el->{name};
    } elsif ($el->{t} =~ /^P/) {
	return "op: " . $el->{sym} if $el->{sym};
	return "call" if (exists($el->{call}));
    } if ($el->{t} =~ /^LI/) {
	return $el->{t} . " : " . $el->{value};
    }

    return $el->{t};
}

sub isObj() {
    return ref($_[0]) eq "HASH";
}
