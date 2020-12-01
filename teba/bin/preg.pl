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

use ProgTrans;
use RewriteTokens;
use Tokenizer;
use CParser;

use JSON;

use Getopt::Std;
my %opts = ();

$opts{h} = 1 unless getopts("havtTef:p:l:b:s:drucj", \%opts);
if ($opts{h}) {
    print STDERR " preg.pl -- program pattern searcher\n\n",
    " pgrep.pl [-adehrtTv] [-f file] [-lbs num] [-p] [pattern] [file ...]\n",
    "  -a : Print all of the program text.\n",
    "  -c : Search in the matched regions. The input should be the output of the tool with -ta option.\n",
    "  -d : Debug mode.\n",
    "  -e : Expression mode.\n",
    "  -r : Remove matched patterns from matched token sequences.\n",
    "  -t : Print token sequences instead of program texts.\n",
    "  -T : Read inputs as token sequences.\n",
    "  -u : Remove virtual tokens inserted by this tool before starting matching.\n",
    "  -v : Colored output with ANSI escape sequences.\n",
    "  -f : Read pattern from file.\n",
    "  -l : Number of lines of context.\n",
    "  -b : Number of parent blocks of context.\n",
    "  -s : Number of siblings of context.\n",
    "  -p : Specify a pattern, when a pattern begins with a dash.\n",
    "  -j : Insert json data of the matched variables\n",
    "  -h : Print help.\n",
    "\n";
    exit(1);
}
$| = 1 if $opts{d};

my $pattern = "";
if ($opts{f}) {
    die "Both -f and -p are specified." if ($opts{p});
    open(my $f, '<', $opts{f}) || die "can't open file: $opts{f}.";
    $pattern = join('', <$f>). "\n";
    close($f);
} else {
    $pattern = $opts{p} // shift @ARGV;
}
die "no pattern specified." if (!$pattern);

my $vt_remover;
if ($opts{u}) {
    $vt_remover = RewriteTokens->seq('{$:/_[RM][BE]/} => {}');
}

my @ptrs = split("%%---\n", $pattern);

my $tr = ProgTrans->new({ e => $opts{e} });
my $tr_parser = $tr->gen_parser();
my @srch;
foreach my $p (@ptrs) {
    my $tk = $tr_parser->($p);
    $tk = $tr->normalize_spaces($tk);
    my @pt = $tr->gen_before_pattern($tk);
    my (@b_pt, @a_pt);
    unless ($opts{r}) {
	# q/'(?!_ME)':X/ in @b_pt is to avoid inifinit rewrting.
	@b_pt = ('$[match:', q/'(?>':X/, @pt, q/')':X/, q/'(?!_ME)':X/, '$]');
	@a_pt = (q(''#1:_RB), q(''#2:_MB), '$match', q(''#2:_ME), q(''#1:_RE));
	splice(@a_pt, 2, 0, &gen_pattern_variable_list(@pt)) if $opts{j};
    } else {
	@b_pt = ('$#1:_RB', '$#2:_MB', '$[match:',
		 q/'(?>':X/, @pt, q/')':X/, '$]', '$#2:_ME', '$#1:_RE');
	@a_pt = ('$match');
    }
    my $rule = $tr->gen_rules(\@b_pt, \@a_pt);
    print "Generated rules:\n$rule\n" if $opts{d};
    push(@srch, RewriteTokens->seq($tr->default_vars(),
				   q(@_SP =>"(?:SP|_[MR][BE]).*+\n"), $rule));
    #print $srch[-1]->dump() if $opts{d};
}

my $cparser = CParser->new();
$cparser->use_prep_branch();

my $cleanup = RewriteTokens->seq(q(
  @ANY => "(?:.*\n)*?"
  { $#r1:_RB $#m1:_MB $rb#r2:_RB $mb#m2:_MB $any:ANY
    $me#m2:_ME $re#r2:_RE $#m1:_ME $#r1:_RE } =>> { $rb $mb $any $me $re }
));

my @files = @ARGV;
push(@files, "-") if !@files;

foreach my $file (@files) {
    my $tokens;
    if ($file eq "-") {
	$tokens .= join('', <STDIN>);
    } else {
	$tokens = "FILENAME <$file>\n";
	print "Target: $file\n" if $opts{d};
	open(my $f, '<', $file) || die "Can't open $file: $!";
	my $t = join('', <$f>);
	close($f);
	$t = $cparser->parse($t) unless $opts{T};
	$tokens .= $t;
    }

    my @ctk = ($opts{c} ? &split_context($tokens) : ("", $tokens));
    if ($vt_remover) {
	@ctk = map($vt_remover->rewrite($_), @ctk);
    }

    for (my $i = 1; $i < @ctk; $i += 2) {
	foreach my $rt (@srch) {
	    my $t;
	    do {
		$t = $ctk[$i];
		$ctk[$i] = $rt->rewrite($ctk[$i]);
		$ctk[$i] = &encode_pvar_seq($ctk[$i]);
	    } while ($t ne $ctk[$i]);
	}
    }
    $tokens = join("", @ctk);

    $tokens = $cleanup->rewrite($tokens);

    $tokens = &expand_lines($tokens, $opts{l}) if ($opts{l});
    $tokens = &expand_block($tokens, $opts{b}) if ($opts{b});;
    $tokens = &expand_sibling($tokens, $opts{s}) if ($opts{s});;
    print &join_tokens($tokens, \%opts);
}

###########################################################################
sub split_context() {
    my $tk = shift;
    my @chunk = map("$_\n", split(/\n(?=_RB)|\n(?=_RE)/, $tk));
    push(@chunk, "") if (@chunk == 1);
    return @chunk;
}

###########################################################################

sub expand_lines() {
    my ($tk, $num) = @_;
    my $rt = RewriteTokens->seq()->set_rules(q(
@NONL => "(?:(?:[^S]|SP_[BC]|SC).*+\n)*"
@NL => "SP_N[LC].*+\n"

{ $[top: $:NL $| $:UNIT_BEGIN $] $sp:NONL $r:_RB } => { $top $r $sp }
{ $r:_RE $sp:NONL $[tail: $:NL $| $:UNIT_END $] } => { $sp $r $tail }
));
    $tk = $rt->rewrite($tk);
    my $rt2 = RewriteTokens->seq()->set_rules(q(
@NONL => "(?:(?:[^S]|SP_[BC]|SC).*+\n)*"
@NL => "SP_N[LC].*+\n"

{ $[top: $:NL $| $:UNIT_BEGIN $] $sp:NONL $nl:NL $r:_RB } => { $top $r $sp $nl }
{ $r:_RE $nl:NL $sp:NONL $[tail: $:NL $| $:UNIT_END $] } => { $nl $sp $r $tail }
));

    $tk = $rt2->rewrite($tk) foreach (1..$num);
    return $tk;
}

sub align_R_block() {
    my ($tk, $num, $BORDER, $dir) = @_;
    my @tk = split("\n", $tk);
    my @border;

    my ($start, $delta, $in, $out) = $dir eq 'B' ?
	(0, 1, 'B', 'E') : ($#tk, -1, 'E', 'B');
    for (my $i = $start; 0 <= $i && $i < @tk; $i += $delta) {
	if ($tk[$i] =~ /^${in}_$BORDER/) {
	    push(@border, $i);
	} elsif ($tk[$i] =~ /^${out}_$BORDER/) {
	    pop(@border);
	} elsif ($tk[$i] =~ /^_R${in}/) {
	    next if (!@border);
	    my $n = $num;
	    --$n if $tk[$i+$delta*2] =~ /^${in}_$BORDER/; # on the border
	    next if $n < 1;
	    $n = 0 if @border <= $n;
	    my $rb = splice(@tk, $i, 1);  # remove _R[BE]
	    splice(@tk, $border[0-$n], 0, $rb); # insert _R[BE]
	}
    }

    return join("\n", @tk);
}

my $move_RE_to_tail;
sub expand_block() {
    my ($tk, $num) = @_;
    my $BORDER = "(?:ST|DE|TD|FUNC|DIRE)";

    $tk = &align_R_block($tk, $num, $BORDER, 'B');
    $tk = &align_R_block($tk, $num, $BORDER, 'E');

    $move_RE_to_tail //= RewriteTokens->seq(q(
@ANY => "(?:.+\n)*?"
{ $rb#r:_RB $[: $mb:_MB $]? $bb#b:/B_).$BORDER.q(/
  '(?>':X $any1:ANY $re#r:_RE ')':X $any2:ANY $be#b:/E_).$BORDER.q(/ }
  =>> { $rb $mb $bb $any1 $any2 $be $re }
{ $bb#b:/B_).$BORDER.q(/ '(?>':X $any1:ANY $rb#r:_RB ')':X
  '(?>':X $any2:ANY $be#b:/E_).$BORDER.q(/ $[: $me:_ME $]? $re#r:_RE ')':X }
  =>> { $rb: $bb $any1 $any2 $be $me $re }

# for readability
{ $sp:/SP_[BC]/ $r:_RB } =>> { $r $sp }
));
    $tk = $move_RE_to_tail->rewrite($tk);
    return $tk;
}

sub move_mark_to_sibling() {
    my ($tk, $num, $dir) = @_;
    my ($st, $delta) = ($dir eq 'B' ? (0, 1) : (int(@$tk)-1, -1));
    for (my $i = $st; 0 <= $i && $i < @$tk; $i += $delta) {
	next unless ($tk->[$i] =~ /^_R$dir/);
	my $top;
	my $n = $num;
	for ($top = $i - $delta; 0 <= $top && $top < @$tk; $top -= $delta) {
	    last if ($tk->[$top] =~ /[BE]_(FUNC|UNIT)\s/);
	    last if ($tk->[$top] =~ /^${dir}_(ST|DE|DIRE)\s/ && --$n == 0);
	}
	--$top if ($top == @$tk);
	my $rb = splice(@$tk, $i, 1);  # remove _RB
	splice(@$tk, $top, 0, $rb); # insert _RB
    }
}

sub expand_sibling() {
    my ($tk, $num) = @_;
    my @tk = split("\n", $tk);

    &move_mark_to_sibling(\@tk, $num, 'B');
    &move_mark_to_sibling(\@tk, $num, 'E');

    return join("\n", @tk);
}

sub join_tokens() {
    my ($tk, $mode) = @_;

    my @res = ();
    my $fname = "stdin";
    my $line = 1;
    my $in_match = 0;
    my $last_token = "";
    foreach (split("\n", $tk)) {
	my ($t, $i, $s) = /^(\w+)(?:\s+(#\w+))?\s+<(.*)>$/;
	next unless $t;
	$s = Tokenizer->unescape($s);
	if ($t eq "FILENAME") {
	    $fname = $s;
	    next;
	} elsif ($t =~ /^SP_N[LC]/) {
	    $line++;
	} elsif ($t eq "SP_C") {
	    $line += ((my $c = $s) =~ s/\n//g);
	} elsif ($t eq "_RB") {
	    $in_match++;
	    if (!$mode->{a} && $in_match == 1) {
		push(@res, "\033[4;36m") if ($mode->{v});
		if ($mode->{t}) {
		    push(@res, "SP_MATCH_BEGIN <\\n### $fname, $line ###\\n>\n");
		} else {
		    push(@res, "### $fname, $line ###\n");
		}
		push(@res, "\033[m") if ($mode->{v});
	    }
	} elsif ($t eq "_RE") {
	    $in_match--;
	    if (!$mode->{a} && $in_match == 0) {
		if ($mode->{t}) {
		    push(@res, "$_\n");
		    push(@res, "SP_MATCH_END <\\n>\n");
		} else {
		    push(@res, "\n");
		}
	    }
	} elsif ($t eq "_MB") {
	    if ($mode->{v}) {
		push(@res, "\033[4;35m{<\033[m")
	    } elsif (!$mode->{t}) {
		push(@res, "{<");
	    }
	} elsif ($t eq "_ME") {
	    if ($mode->{v}) {
		push(@res, "\033[4;35m>}\033[m");
	    } elsif (!$mode->{t}) {
		push(@res, ">}");
	    }
	}
	push(@res, ($mode->{t} ? "$_\n" : $s)) if ($mode->{a} || $in_match);
	$last_token = $_;
    }
    return join("", @res);
}

##  ========

sub gen_pattern_variable_list() {
    my @res;
    foreach (@_) {
	next unless /^\$\[?([a-zA-Z]\w*)/;
	push(@res, qq('$1':_VNAME), "\$$1");
    }
    return (q('#pvar{\n':_PVAR_B), @res, q('}\n':_PVAR_E));
}

sub encode_pvar_seq() {
    my @res;
    my $in_seq = 0;
    my $pvar = {};
    my $name;
    foreach (split("\n", $_[0])) {
	if (/^_PVAR_B/) {
	    $in_seq = 1;
	    next;
	}

	unless ($in_seq) {
	    push(@res, $_);
	    next;
	}

	if (/^_VNAME\s+<(\w+)>/) {
	    $name = $1;
	    $pvar->{$name} = ();
	    next;
	}

	if (/^_PVAR_E/) {
	    my $json = encode_json( $pvar );
	    push(@res, "SP_PVAR\t\<$json>");
	    $in_seq = 0;
	    next;
	}

	push(@{$pvar->{$name}}, $_);
    }
    return join("", map("$_\n", @res));

}
