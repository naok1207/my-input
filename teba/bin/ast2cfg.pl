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
if (!getopts("esrph", \%opts) || $opts{h}) {
    print STDERR "ast2cfg.pl [-esrph] [json-based-ast-file]\n",
	"  -e: expression level cfg (experimental function).\n",
	"  -s: shrink mode; suppressing redundant nodes.\n",
	"  -r: reverse direction.\n",
	"  -p: output as PNG format.\n",
	"  -h: help.\n";
    exit(1);
}

my $root = JSON->new->decode(join('', <>));

my @begin_node;
my @end_node;

&travarse($root);  # ignores return nodes.
#print Dumper @begin_node;

my $g = GraphViz->new();

unless ($opts{r}) {
    &cfg2dot($g, $opts{s});
} else {
    &cfg2dot_rev($g, $opts{s});
}

if ($opts{p}) {
    print $g->as_png;
} else {
    print $g->as_text;
}

sub cfg2dot()
{
    my ($g, $shrink) = @_;

    my %visit;
    my @b = @begin_node;
    while (@b) {
	my $n = shift @b;
	next if $visit{$n};
	$g->add_node($n->{id}, label => " $n->{label}");
	foreach my $next (@{$n->{next}}) {
	    my $edge_label = "";
	    if ($shrink) {
		while ($next->{label} =~ /^(ST_COMP|true|false|if: begin|while: (begin|end))$/) {
		    if ($next->{label} =~ /^(true|false)$/) {
			$edge_label = $next->{label};
		    }
		    $next = $next->{next}->[0];
		}
	    }
	    push(@b, $next);
	    $g->add_edge($n->{id}, $next->{id}, label => $edge_label);
	}
	$visit{$n} = 1;
    }
}


sub travarse()
{
    my $el = shift;
    my ($begin, $end);

    if ($el->{t} eq "FUNC") {
	my $fname = &elemToString(&getChild($el, "name"));
	$begin = &createNode("$fname: begin", $el);
	$end = &createNode("$fname: end", $el);
	my ($b, $e) = &travarse($el->{e}->[$el->{body}]);
	&connectNode($begin, $b);
	&connectNode($e, $end);
    } elsif ($el->{t} eq "ST_COMP") {
	$begin = &createNode($el->{t}, $el);;
	my $cur = $begin;
	foreach my $st (grep(&isObj($_), @{$el->{e}})) {
	    my ($b, $e) = &travarse($st);
	    next unless $b;
	    &connectNode($cur, $b);
	    $cur = $e;
	}
	$end = $cur;
    } elsif ($el->{t} eq "ST_IF") {
	$begin = &createNode("if: begin", $el);
	$end = &createNode("if: end", $el);

	my $c = &getChild($el, "cond");
	my $cond = &createNode("cond:" . &elemToString($c), $c);
	if ($opts{e}) {
	    my ($b, $e) = &travarse_expr($c);
	    &connectNode($begin, $b);
	    &connectNode($e, $cond);
	} else {
	    &connectNode($begin, $cond);
	}

	my $then = &createNode("true", &getChild($el, "then"));
	&connectNode($cond, $then);
	my ($b, $e) = &travarse($then->{node});
	&connectNode($then, $b);
	&connectNode($e, $end);
	if (exists($el->{else})) {
	    my $else = &createNode("false", &getChild($el, "else"));
	    &connectNode($cond, $else);
	    my ($b, $e) = &travarse($else->{node});
	    &connectNode($else, $b);
	    &connectNode($e, $end);
	} else {
	    my $else = &createNode("false", undef);
	    &connectNode($cond, $else);
	    &connectNode($else, $end);
	}
    } elsif ($el->{t} eq "ST_WHILE") {
	$begin = &createNode("while: begin", $el);
	$end = &createNode("while: end", $el);
	my $c = &getChild($el, "cond");
	my $cond = &createNode("cond:" . &elemToString($c), $c);
	if ($opts{e}) {
	    my ($b, $e) = &travarse_expr($c);
	    &connectNode($begin, $b);
	    &connectNode($e, $cond);
	} else {
	    &connectNode($begin, $cond);
	}
	my $false = &createNode("false", undef);
	&connectNode($cond, $false);
	&connectNode($false, $end);

	my $body = &createNode("true", &getChild($el, "body"));
	&connectNode($cond, $body);
	my ($b, $e) = &travarse($body->{node});
	&connectNode($body, $b);
	&connectNode($e, $cond);
    } elsif ($el->{t} eq "ST_EXPR") {
	$end = &createNode(&elemToString($el), $el);
	if ($opts{e}) {
	    my ($b, $e) = &travarse_expr(&getChild($el, "expr"));
	    $begin = $b;
	    &connectNode($e, $end);
	} else {
	    $begin = $end;
	}
    } elsif ($el->{t} eq "UNIT") {
	my @children = grep(&isObj($_), @{$el->{e}});
	if (grep($_->{t} =~ /^ST_/, @children)) {
	    $begin = &createNode("unit: begin", $el);
	    $end = &createNode("unit: end", $el);
	    my $last_end = $begin;
	    foreach (@children) {
		my($b, $e) = &travarse($_);
		&connectNode($last_end, $b);
		$last_end = $e;
	    }
	    &connectNode($last_end, $end);
	    push(@begin_node, $begin);
	    push(@end_node, $end);
	} else {
	    foreach (@children) {
		my ($b, $e) = &travarse($_);
		push(@begin_node, $b) if $b;
		push(@end_node, $e) if $e;
	    }
	}
    }

    return ($begin, $end);
}

sub travarse_expr()
{
    my $el = shift;
    my ($begin, $end);

    if ($el->{t} eq "P") {
	my @operand = &getChild($el, "operand");
	my $cur;
	foreach my $expr (@operand) {
	    my ($b, $e) = &travarse_expr($expr);
	    $begin = $b unless ($begin);
	    &connectNode($cur, $b) if $cur;
	    $cur = $e;
	}
	$end = &createNode($el->{sym}, $el);
	&connectNode($cur, $end);
#	print Dumper $cur;
    } elsif ($el->{t} =~ /^LI/) {
	$begin = $end = &createNode($el->{value}, $el);
    } elsif ($el->{t} =~ /^ID/) {
	$begin = $end = &createNode($el->{name}, $el);
    }

    return ($begin, $end);
}

my $_node_id;
sub createNode()
{
    my ($label, $node) = @_;
    $label =~ s/\"/\\"/g;  # GraphViz.pm has a bug escaping double quotes twice.
    my $n = { label => $label, node => $node, id => ++$_node_id };
    return $n;
}

sub connectNode()
{
    my ($src, $dst) = @_;

    push(@{$src->{next}}, $dst);
    push(@{$dst->{prev}}, $src);
}

sub isObj() {
    return ref($_[0]) eq "HASH";
}

sub getChild() {
    my ($elem, $key) = @_;
    if (ref($elem->{$key}) eq "ARRAY") {
	return map($_ >=0 ? $elem->{e}->[$_] : undef, @{$elem->{$key}});
    }
    return $elem->{e}->[$elem->{$key}];
}


sub elemToString() {
    return &join_tokens(&getTokens($_[0]));
}

sub getTokens() {
    my $elem = shift;
    return map(&isObj($_) ? &getTokens($_) : $_, @{$elem->{e}});
}

sub join_tokens() {
    my @tk = @_;
    grep(s/^\w+(?:\s+#\w+)?\s+<(.*)>$/$1/, @tk);
    return join('', map(&ev($_), @tk));
}

sub ev()
{
    my $s = shift;
    my @r;
    while ($s ne "") {
	if ($s =~ s/^[^\\]+//) { push(@r, $&); }
	if ($s =~ s/^\\n//) { push(@r, "\n"); next; }
	if ($s =~ s/^\\t//) { push(@r, "\t"); next; }
	if ($s =~ s/^\\(.)//) { push(@r, $1); }
    }
    return join('', @r);
}
