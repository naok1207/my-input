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

package PrepBranch;

use strict;
use warnings;

use RewriteTokens;

my $opts;

sub new() {
    my $self = shift;
    $opts = shift;
    return bless {};
}

sub parse()
{
    my ($self, $tk) = @_;

    # clean up: removing old PRE_BRs
    $tk = RewriteTokens->seq(q({ $:PRE_BR } => {}))->rewrite($tk);

    my $templ = q(
          { $bd#1:B_DIRE $[sp0: $:SP_B $]* $pt:PRE_TOP
            $[sp1: $:/SP_N?[BC]/ $]* $pd:PRE_DIR/%s/ }
           => { $bd '':_PRE_%s $sp0 $pt $sp1 $pd });
    my $mark_rule = RewriteTokens->seq(
	    sprintf($templ, "ifn?(?:def)?", "IF"),
	    sprintf($templ, "else|elif", "ELSE"),
	    sprintf($templ, "endif", "END"));
    $tk = $mark_rule->rewrite($tk); # mark the targets

    my (@ids, %idx, %cond);
    my $ref;
    my @tk = split("\n", $tk);
    for (my $i = 0; $i < @tk; $i++) {
	if (my ($type) = ($tk[$i] =~ /^_PRE_(\w+)/)) {
#	    print "ST: ", join(" ", @ids), "\n";
	    if ($type eq "IF") {
		$ref = &gen_prepid();
		push(@ids, $ref);
	    } elsif ($type eq "ELSE") {
		$ref = $ids[-1];
		if (!@ids) {
		    &dump_code(\@tk) if $opts->{d};
		    die "Unbalanced IFDEF-ELSE";
		}
	    } elsif ($type eq "END") {
		if (!@ids) {
		    &dump_code(\@tk) if $opts->{d};
		    die "Unbalanced IFDEF-ENDIF";
		}
		$ref = pop(@ids);
	    } else { die "Unknown type: $type\n"; }
	    $tk[$i] = "PRE_BR $ref\t<>";
	}
    }
    return join("\n", @tk)."\n";
}

my $_preid = 0;
sub gen_prepid() {
    return sprintf("#P%04d", ++$_preid);
}


sub test_main() {
    my $tk = join('', <>);
    print PrepBranch->new()->parse($tk);
}

sub dump_code()
{
    my $tk = shift;
    print "Dump <Dump:\\n>\n". join("\n", @$tk)."\n";
}

1;
