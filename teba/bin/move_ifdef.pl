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
use lib "$Bin/../TEBA/ProgPattern";

use strict;
use warnings;

use RewriteTokens;
use CParser;
use BeginEnd;
use BracketsID;

my $MARK = "TEBA:mark";
my $MARK_CMT = "/*$MARK*/";
my $MARK_PT = "\\/\\*\\s*$MARK\\s*\\*\\/";

# for boarder marks for removing directives
#my $REG_BEG = "TEBA:begin";
#my $REG_END = "TEBA:end";
#my $REG_BEG_CMT = "/*$REG_BEG*/";
#my $REG_END_CMT = "/*$REG_END*/";
#my $REG_BEG_PT = "\\/\\*\\s$REG_BEG\\s\\*\\/";
#my $REG_END_PT = "\\/\\*\\s$REG_END\\s\\*\\/";

my $BORDER = "(?:ST|DE|TD|FUNC)";

use Getopt::Std;
my %opts = ();

$opts{h} = 1 unless getopts("hd1aPEn:gcCx", \%opts);

if ($opts{h}) {
    print STDERR  "move_ifdef.pl [-hd1aPEgcC] [-n num] [file]\n",
    "  -1 : apply only once.\n",
    "  -n [num] : apply num times.\n",
    "  -a : apply to all ifdef/ifndef/if\n",
    "  -P : exclude unmarked 'elif's in the first targets.\n",
    "  -E : exclude 'ifdef/ifndef/if's which does not have else parts.\n",
    "  -g : treat directives in regions between _RB and _RE as targets.\n",
    "  -c : read the C source and parse it.\n",
    "  -C : outpus the modified C source.\n",
    "  -d : debug mode.\n",
    "  -h : help.\n";
#    print STDERR "  -x : print evaluation data.\n";
    exit(1);
}
$opts{n} //= 1 if $opts{1};
$| = 1 if ($opts{d} || $opts{x});

my $cparser = CParser->new();

my $filename = $ARGV[0];
my $tk = join('', <>);

if ($opts{c}) {
    $tk = $cparser->parse($tk);
}


$tk = &add_mark_in_regions($tk) if $opts{g};
$tk = &propagate_mark($tk) if !$opts{P};

my $remove_PRE = RewriteTokens->seq('{ $:/(?:_PRE_\w+|_[BE]_C)/ } => {}');
my $remove_MARK = RewriteTokens->seq('{ $:/_MARK/ } => {}');


for (my $count = 0; !$opts{n} || $count < $opts{n} ; $count++) {
    print "Loop count: $count\n" if ($opts{d} && $opts{n});
    my ($tk_idx, $ifdef_cond);
    ($tk, $tk_idx, $ifdef_cond) = &parse_ifdef_struct($tk);

    print "Finding targets....\n" if $opts{d};
    my @targets = &find_marked_target($tk);
    @targets = &select_having_else(\@targets, $tk_idx) if $opts{E};
    my %is_target = map { $_ => 1 } @targets;

    my @tk = split("\n", $tk);
    # Checks un-closed statements(or declarations)
    my $then_reg = &find_reg_then(\@tk, $tk_idx, \%is_target);
    my $else_reg = &find_reg_else(\@tk, $tk_idx, \%is_target);
    &make_reg_consistent($then_reg, $else_reg, \@tk);

    my @ex = grep(($_->[0] <= $_->[1]), values %$then_reg, values %$else_reg);
    print "Check region: ", join(", ", map("[". join(", ", @$_). "]", @ex)),
          "\n" if $opts{d};

    %is_target = map { $_ => 1 } (keys %$then_reg, keys %$else_reg);
    my $tg_num = (keys %is_target);
    if (!%is_target) {
	print STDERR join(":", "X", $filename, $count, int(@targets),
			  $tg_num, 0, int(grep /^SP_N/, @tk),
			  join("", keys %opts)), "\n" if $opts{x};
	last;
    }
    if (0 && int(keys %is_target) > 1025) {  # for avoiding out of memory.
	# the maximum number of targets in test-inttypes.c is 1024, whose
	# analysis finish normally.
	print STDERR "Error: Too many targets for $filename\n";
	last;
    }

    print "Preparing regions....\n" if $opts{d};

    # Canceled directives which overwrappes others.
    my %cancel = &cancel_inner_ifdef(\@tk, \%is_target);
    my @rm_reg = &prepare_rm_reg2(\%is_target, $then_reg, $else_reg, \%cancel,
				  $tk_idx);
    %cancel = &cancel_overwrapped_ifdef2(\@rm_reg, \@tk);
    @rm_reg = &prepare_rm_reg2(\%is_target, $then_reg, $else_reg, \%cancel,
			       $tk_idx);

#    my @rm_reg = &prepare_rm_reg(\%is_target, $then_reg, $else_reg, \%cancel);
#    %cancel = &cancel_overwrapped_ifdef(\@rm_reg, \@tk);
#    @rm_reg = &prepare_rm_reg(\%is_target, $then_reg, $else_reg, \%cancel);

    &print_targets(\@tk, \%is_target, $then_reg, $else_reg) if $opts{d};
    print STDERR join(":", "X", $filename, $count, int(@targets),
		      $tg_num, int(keys %is_target), int(grep /^SP_N/, @tk),
		      join("", keys %opts)), "\n" if $opts{x};

    print "Moving ifdefs...\n" if $opts{d};
    @tk = &move_ifdef(\@tk, $tk_idx, \%is_target, $ifdef_cond, \@rm_reg,
		      $then_reg, $else_reg);

    $tk = &reconstruct_elif(join("\n", @tk));
    $tk = $remove_PRE->rewrite($tk);
    $tk = $remove_MARK->rewrite($tk);

    print "Regenerating tokens....\n" if $opts{d};
    $tk = $cparser->parse(Tokenizer->join_tokens($tk));
}

$tk = &reconstruct_elif($tk);
$tk = $remove_PRE->rewrite($tk);
$tk = &optimize_elif($tk);
$tk = $remove_PRE->rewrite($tk);
$tk = $remove_MARK->rewrite($tk);
$tk = Tokenizer->join_tokens($tk) if $opts{C};
print $tk;

###########################################################################
sub print_targets() {
    my ($tk, $is_target, $then_reg, $else_reg) = @_;
    print "Printing all targets:\n";
    foreach my $t (keys %$is_target) {
	print "Target: $t\n";
	foreach my $k ( ["Then", $then_reg], ["Else", $else_reg]) {
	    my ($label, $regs) = @$k;
	    next if (!exists $regs->{$t});
	    print "$label: [ ", join(", ", @{$regs->{$t}}), "]\n";
	    my @slice = @$tk[ $regs->{$t}->[0] .. $regs->{$t}->[1]];
	    print "<<\n", Tokenizer->join_tokens(@slice), ">>\n" ;
	    print map("  $_\n", @slice);
	}
	print "\n";
    }
}

sub propagate_mark() {
    my $tk = shift;
    my @tk = split(/\n/, $tk);
    my @mark;
    for (my $i = 0; $i < @tk; $i++) {
	if ($tk[$i] =~ /^PRE_DIR\s+<if\w*>$/) {
	    my $has_mark = 0;
	    until ($tk[++$i] =~ /^E_DIRE/) {
		$has_mark = 1 if $tk[$i] =~ /^SP_C\s+<$MARK_PT>/;
	    }
	    push(@mark, $has_mark);
	} elsif ($tk[$i] =~ /^PRE_DIR\s+<elif>$/) {
	    my $has_mark = 0;
	    until ($tk[++$i] =~ /^E_DIRE/) {
		$has_mark = 1 if $tk[$i] =~ /^SP_C\s+<$MARK_PT>/;
	    }
	    if (!$has_mark && $mark[-1]) {  # need to add a mark
		splice(@tk, $i++, 0, "SP_B\t< >", "SP_C\t<$MARK_CMT>");
	    }
	} elsif ($tk[$i] =~ /^PRE_DIR\s+<endif>$/) {
	    pop(@mark);
	}
    }
    return join("\n", @tk);
}

sub propagate_mark_from_endif() {
    my $tk = shift;

    my @tk = split(/\n/, $tk);
    my @mark;
    for (my $i = $#tk; $i >= 0; $i--) {
	if ($tk[$i] =~ /^PRE_DIR\s+<endif>$/) {
	    my $has_mark = 0;
	    if ($tk[$i-1] =~ /_MARK/) {
		$i--;
		splice(@tk, $i, 1); # remove _MARK
		$has_mark = 1;
	    }
	    push(@mark, $has_mark);
	} elsif ($tk[$i] =~ /^PRE_DIR\s+<if\w*>$/) {
	    my $has_mark = pop(@mark);
	    if ($has_mark && $tk[$i-1] !~ /_MARK/) {
		splice(@tk, $i, 0, "_NEW_MARK\t<>"); # add _MARK
	    }
	}
     }
    $tk = join("\n", @tk);
    $tk = RewriteTokens->seq(q(
     { $bd#1:B_DIRE $pt:PRE_TOP $[sp: $:/SP_N?[BC]/ $]*
       $:_MARK $pd:PRE_DIR/if\w*/ $[cond: $:/\w+/ $]*? $ed#1:E_DIRE }
       => { $bd $pt $sp $pd $cond ' ':SP_B ').$MARK_CMT.q(':SP_C $ed }
    ))->rewrite($tk);

    return $tk;
}

sub add_mark_in_regions() {
    my $tk = shift;
    my @tk;
    my $in_reg = 0;
    foreach (split("\n", $tk)) {
	if (/^_RB/) {
	    $in_reg = 1;
	} elsif (/^_RE/) {
	    $in_reg = 0;
	} elsif ($in_reg && /^E_DIRE/) {
	    push(@tk, "_TGT\t<>");
	}
	push(@tk, $_);
    }
    $tk = join("\n", @tk);
    $tk = RewriteTokens->seq(q(
     { $bd#1:B_DIRE $pt:PRE_TOP $[sp: $:/SP_N?[BC]/ $]*
       $pd:PRE_DIR/(?:if\w*|endif)/ $[cond: $:/\w+/ $]*? $:_TGT $ed#1:E_DIRE }
       => { $bd $pt $sp '':_MARK $pd $cond $ed }
     { $:_TGT } => {}
    ))->rewrite($tk);
    
    $tk = &propagate_mark_from_endif($tk);
    return $tk;
}

#############################################################################

my $mark_rule;
sub parse_ifdef_struct()
{
    my $tk = shift;

    if (!$mark_rule) {
	my $templ = q(
          { $bd#1:B_DIRE $pt:PRE_TOP $[sp1: $:/SP_N?[BC]/ $]* $pd:PRE_DIR/%s/
            $[sp2: $:/SP_N?[BC]/ $]* $[cond: $:/\w+/ $]* $ed#1:E_DIRE }
           => { '':_PRE_%s $bd $pt $sp1 $pd $sp2 '':_B_C $cond '':_E_C $ed });
	$mark_rule = RewriteTokens->seq(
	    sprintf($templ, "if(?:def)?", "IFDEF"),
	    sprintf($templ, "ifndef", "IFNDEF"),
	    sprintf($templ, "else", "ELSE"),
	    sprintf($templ, "elif", "ELIF"),
	    sprintf($templ, "endif", "ENDIF"),
	    '{$[sp2: $:/SP_N?[BC]/ $]+ $ec:_E_C}=>{$ec $sp2}'); # strip spaces
    }
    $tk = $mark_rule->rewrite($tk); # mark the targets

    # Assigns IDs to _PRE_(IFDEF|ELSE|ENDIF)s.
    my (@ids, %idx, %cond);
    my $ref;
    my @tk = split("\n", $tk);
    for (my $i = 0; $i < @tk; $i++) {
	if (my ($type) = ($tk[$i] =~ /^_PRE_(\w+)/)) {
#	    print "ST: ", join(" ", @ids), "\n";
	    if ($type eq "IFDEF" || $type eq "IFNDEF") {
		$ref = &gen_prepid("IF");
		push(@ids, $ref);
		$cond{$ref} = "_COND_$type\t<>\n";
		$type = "IFDEF";
		$tk[$i] =~ s/^_PRE_IFNDEF/_PRE_$type/;
	    } elsif ($type eq "ELSE") {
		$ref = $ids[-1];
	    } elsif ($type eq "ELIF") {
		$i = &insert_elif_dire(\@tk, \%idx, $i, "ELSE", $ids[-1]);
		$ref = &gen_prepid("EI");
		push(@ids, $ref);
		$type = "IFDEF";
		$tk[$i] =~ s/^_PRE_ELIF/_PRE_$type/;
	    } elsif ($type eq "ENDIF") {
		if (!@ids) {
		    &dump_code(\@tk) if $opts{d};
		    die "Unbalanced IFDEF-ENDIF";
		}
		while (($ref = pop(@ids)) =~ /^#EI/) {
		    $i = &insert_elif_dire(\@tk, \%idx, $i, "ENDIF", $ref);
		}
	    } else { die "Unknown type: $type\n"; }
#	    print "Check: $type, $ref\n";
	    $tk[$i] =~ s/^_PRE_(\w+)/_PRE_$1 $ref/;
	    $idx{"$type $ref"} = $i;
	} elsif ($tk[$i] =~ /^_B_C/) {
	    $cond{$ref} .= $tk[$i]."\n" until $tk[++$i] =~ /^_E_C/;
	}
	$tk[$i] =~ s/^PRE_DIR\s+<elif>$/PRE_DIR\t<if>/;
    }

    foreach my $k (keys %cond) {
	$cond{$k} = &normalize_cond($cond{$k});
    }
    return (join("\n", @tk)."\n", \%idx, \%cond);
}

my $_preid = 0;
sub gen_prepid() {
    my $prefix = shift;
    return sprintf("#%s%04d", $prefix, ++$_preid);
}

sub insert_elif_dire() {
    my ($tk, $idx, $i, $type, $ref) = @_;
    my $l_type = lc($type);
    my @d = ("_PRE_$type $ref\t<elif>", q(B_DIRE <>), q(PRE_TOP <#>),
	     qq(PRE_DIR <$l_type>), q(E_DIRE <>), q(SP_NL <\n>));
    splice(@$tk, $i, 0, @d);
    $idx->{"$type $ref"} = $i;
    return $i + @d;
}

my $norm_cond_rule;
sub normalize_cond() {
    my $cond = shift;
    $norm_cond_rule //= RewriteTokens->seq(q(
      @ANY => "(.*\n)*"
      # ifdef: adds 'defined'
      { $:_COND_IFDEF $b:B_P $m:ID_MC $e:E_P }
      => { ''#1:B_P 'defined':OP $b $m $e ''#1:E_P }

      # ifdef: adds 'defined' and makes negative.
      { $:_COND_IFNDEF $b:B_P $m:ID_MC $e:E_P }
      => { '':_NOT ''#1:B_P 'defined':OP $b $m $e ''#1:E_P }

      # Generates negative expressions.
      { $:_NOT $b#1:B_P $any:ANY $e#1:E_P }
      => { ''#1:B_P '!':OP $b $any $e ''#1:E_P }

      # Removes successive nagative operators.
      { $#1:B_P $:OP/!/ $#2:B_P $:OP/!/ $b#3:B_P $any:ANY
        $e#3:E_P $#2:E_P $#1:E_P } =>> { $b $any $e }

      # Removes white spaces.
      { $:/SP_\w+/ } => {}

      # Removes parentheses surrounding arguments of 'defined's.
      { $def:OP/defined/ $b#1:B_P $pl#2:P_L $any:ANY $pr#2:P_R $e#1:E_P }
        => { $def $any }

      # Insert a space after each 'defined'.
      { $def:OP/defined/ $b:B_P } => { $def ' ':SP_B $b } ));

    $cond = $norm_cond_rule->rewrite($cond);
    $cond = BeginEnd->new()->conv($cond);
    return $cond;
}

sub negative_cond() {
    return &normalize_cond("_NOT\t<>\n$_[0]"); # _NOT is used for normalize.
}

my $rule_rest_elif;
sub reconstruct_elif() {
    my $tk = shift;
    $rule_rest_elif //= RewriteTokens->seq(q(
       { $:_PRE_ELSE/elif/ $:B_DIRE $:PRE_TOP $:PRE_DIR $:E_DIRE $:SP_NL
         $x:_PRE_IFDEF $b:B_DIRE $pt:PRE_TOP $[sp: $:/SP_N?[BC]/ $]*
         $pd:PRE_DIR } => { $x:_PRE_RM $b $pt $sp 'elif':PRE_DIR }
       @ANY => "((?:.+\n)*?)"
      { $#1:_PRE_RM '(?>':X $any:ANY $#1:_PRE_ENDIF ')':X
        $:B_DIRE $:PRE_TOP $:PRE_DIR  $:E_DIRE $:SP_NL } =>> { $any }));

    return $rule_rest_elif->rewrite($tk);
}

my $add_mark;
sub add_mark_to_target() {
    my $tk = shift;
    $add_mark //= RewriteTokens->seq(
	($opts{a}) ? q( { $pi:_PRE_IFDEF } => { '':_MARK $pi })
	: q( { $pi:_PRE_IFDEF $bd#1:B_DIRE $pt:PRE_TOP $[sp: $:/SP_N?[BC]/ $]*
             $pd:PRE_DIR/if(?:n?def)?/ $[any: $:/(?:[^S]|SC|SP_N?[BC])\w*/ $]*
             $mark:SP_C/).$MARK_PT.q(/ $ed#1:E_DIRE }
             => { '':_MARK $pi $bd $pt $sp $pd $any $mark $ed }));
    return $add_mark->rewrite($tk);
}

sub find_marked_target() {
    my $tk = shift;
    $tk = &add_mark_to_target($tk);
    return ($tk =~ m/(?<=\n)_MARK\s+<>\n_PRE_IFDEF\s+(#\w+)\s+<>\n/sg);
}

sub select_having_else() {
    my ($targets, $idx) = @_;
    return grep (exists $idx->{"ELSE $_"}, @$targets);
}

###########################################################################

sub find_reg_then() {
    my ($tk, $tk_idx, $is_target) = @_;
    my %then_reg;
    for (my $i = @$tk-1; $i >= 0; $i--) { # searching backward.
	my ($t, $id) = ($tk->[$i] =~ /^_PRE_ENDIF(\s+(#\w+).*)$/);
	next unless ($id && $is_target->{$id});
#	print "Target: $id\n";
	my ($el, $th) = map($tk_idx->{"$_ $id"}, ("ELSE", "IFDEF"));
	if (!$th) {
	    &dump_code($tk);
	    die "Can't find IFDEF for $id.";
	}
	my $tail = $th - 1; # "- 1" is for skipping _PRE_IFDEF
	my $edge = &get_outer_edge_in($tk, ($el // $i), $th);
	if (!$edge) {
	    $then_reg{$id} = [ $tail+1, $tail, $id ];
	    next;
	}
	my $top = &find_outer_edge($tail, $edge, $tk, -1);
	--$top while ($tk->[$top-1] =~ /^SP_[BC]/); # skips spaces
	$then_reg{$id} = [ $top, $tail, $id ];
    }
    return \%then_reg;
}

sub find_reg_else() {
    my ($tk, $tk_idx, $is_target) = @_;
    my %else_reg;
    for (my $i = 0; $i < @$tk; $i++) {
	my ($t, $id) = ($tk->[$i] =~ /^_PRE_IFDEF(\s+(#\w+).*)$/);
	next unless ($id && $is_target->{$id});
#	print "Target: $id\n";
	my ($el, $en) = map($tk_idx->{"$_ $id"}, ("ELSE", "ENDIF"));
	if (!$en) {
	    &dump_code($tk);
	    die "Can't find ENDIF for $id.";
	}
	my $top = $en + 1;
	1 until ($tk->[$top++] =~ /^SP_NL/);  # jump to the end of the directive
	my $edge = &get_outer_edge_in($tk, ($el // $i), $en);
	if (!$edge) {
	    $else_reg{$id} = [ $top, $top-1, $id ];
	    next;
	}
	my $tail = &find_outer_edge($top, $edge, $tk, 1);
	if ($tk->[$tail] =~ /^_PRE_ENDIF/) {
	    ++$tail until ($tk->[$tail] =~ /^SP_NL/);
	} else {
	    # jump to the end of line or another concrete token.
	    ++$tail while ($tk->[$tail+1] =~ /^(SP_[BC]|E_)/);
	    ++$tail if ($tk->[$tail+1] =~ /^SP_NL/);
	}
	$else_reg{$id} = [ $top, $tail, $id ];
    }
    return \%else_reg;
}

sub get_outer_edge_in() {
    my ($tk, $start, $end) = @_;
    my ($in, $out, $delta) = $start < $end ? ('B', 'E', 1) : ('E', 'B', -1);
    my @border;
    my $has_border;
    my $has_out_border = 0;
#    print "DEBUG: [$start, $end]\n";
#    print "dump:", map(" - $_\n", $start < $end ? @$tk[ $start .. $end ]
#		       : @$tk[ $end .. $start ]), "\n";
    for (my $i = $start; $i != $end; $i += $delta) {
	if ($tk->[$i] =~ /^${in}_DIRE/) { # skip directives
	    $i += $delta until ($tk->[$i] =~ /^${out}_DIRE/);
	    next;
	}
	next if ($tk->[$i] =~ /^(?:SP_|_PRE_)/);
#	print "Checking: $tk->[$i]\n";
	my ($dir, $id) = ($tk->[$i] =~ /^([BE])_$BORDER\s+(\#\w+)/);
	if (!$dir) { # some tokens may exist out of statements.
	    $has_out_border = 1 unless (@border);
	    next;
	}
	if ($dir eq $in) {
	    push(@border, $id);
	} elsif (@border) {
	    &check_combination($id, pop(@border), $tk);
	} else {  # enverything may be inside of a statement.
	    $has_out_border = 0;
	}
#	print "Border: ", join(", ", @border), "\n";
    }
#    print "has_out_border? $has_out_border\n";
#    print "border? $border[0]\n";
    return $border[0] if (@border);

    return undef unless $has_out_border;

    # has something out of border.
#    print "Search outside\n";
    for (my $i = $end; 0 <= $i && $i < @$tk; $i += $delta) {
	my ($dir, $id) = ($tk->[$i] =~ /^([BE])_$BORDER\s+(\#\w+)/);
#	print "Checking: $tk->[$i]\n";
	next unless ($dir);
	if ($dir eq $in) {
	    push(@border, $id);
	} else { # i.e. $dir is "in"
#	    print "found: $id\n" if (!@border);
	    return $id if (!@border);
	    &check_combination($id, pop(@border), $tk);
	}
    }
#    print "Not found border\n";
    return undef;
}

sub check_combination() {
    my ($a, $b, $tk) = @_;
    if ($a ne $b) {
	&dump_code($tk) if $opts{d};
	die "Illegal combination: $a and $b";
    }
}

sub find_outer_edge() {
    my ($start, $edge, $tk, $dir) = @_;
    my ($in, $out, $st, $delta) = $dir > 0 ? ("IFDEF", "ENDIF", "E", 1)
	                              : ("ENDIF", "IFDEF", "B", -1);

    my $pre_level = 0;
    my $j;

    # looking for the outer [BE]_$BORDER.
    for ($j = $start; 0 <= $j && $j < @$tk; $j += $delta) {
	if ($tk->[$j] =~ /^_PRE_$in/) { $pre_level++; next; }
	if ($pre_level > 0 && $tk->[$j] =~ /^_PRE_$out/) { $pre_level--; next; }
	last if ($tk->[$j] =~ /^${st}_$BORDER\s+$edge\s/);
    }

    # looking for the outer IFDEF/ENDIF if need.
    for ($j += $delta; $pre_level > 0 && 0 <= $j && $j < @$tk ; $j += $delta) {
	if ($tk->[$j] =~ /^_PRE_$in/) { $pre_level++; next; }
	if ($tk->[$j] =~ /^_PRE_$out/) { $pre_level--; next; }
    }

    die join("\n", @$tk)."\nNo pair of B_$BORDER exists for $edge."
	if ($j < 0 || @$tk <= $j);
    return $j - $delta;
}

###########################################################################

sub move_ifdef() {
    my ($tk, $tk_idx, $is_target, $cond, $rm_reg,
	$then_reg, $else_reg) = @_;
    my @res;

    for (my $i = 0; $i < @$tk; $i++) {
	if (@$rm_reg) {
	    my ($b, $e, $target) = @{$rm_reg->[0]};
	    next if ($b <= $i && $i <= $e);
	    shift(@$rm_reg) if ($i > $e);
	}
	if ((my ($type , $id) = ($tk->[$i] =~ /^_PRE_(\w+)\s+(#\w+)/))
	    && $is_target->{$2}) {
	    $tk->[$i] =~ s/^(_PRE_\w+\s+#\w+\s+)<elif>/$1<>/;
	    push(@res, "SP_NL\t<\\n>") unless $res[-1] =~ /^SP_NL/;
	    if ($type eq "IFDEF") {
		do { push(@res, $tk->[$i]); } until ($tk->[$i++] =~ /SP_NL/);
		$i--;
		push(@res, &mk_clone_true($tk, $then_reg, $id, $cond));
	    } elsif ($type eq "ELSE") {
		push(@res, &mk_clone_true($tk, $else_reg, $id, $cond));
		push(@res, "SP_NL\t<\\n>") unless $res[-1] =~ /^SP_NL/;
		do { push(@res, $tk->[$i]); } until ($tk->[$i++] =~ /SP_NL/);
		$i--;
		push(@res, &mk_clone_false($tk, $then_reg, $id, $cond));
	    } elsif ($type eq "ENDIF") {
		(my $el = $tk->[$i]) =~ s/^_PRE_ENDIF/_PRE_ELSE/;
		if (!exists $tk_idx->{"ELSE $id"}) { # no else part
		    push(@res, &mk_clone_true($tk, $else_reg, $id, $cond));
		    push(@res, "SP_NL\t<\\n>") unless $res[-1] =~ /^SP_NL/;
		    push(@res, "B_DIRE\t<>", "PRE_TOP\t<#>", "PRE_DIR\t<else>",
			 "E_DIRE\t<>", "SP_NL\t<\\n>");
		    push(@res, &mk_clone_false($tk, $then_reg, $id, $cond));
		}
		push(@res, &mk_clone_false($tk, $else_reg, $id, $cond));
		push(@res, "SP_NL\t<\\n>") unless $res[-1] =~ /^SP_NL/;
		push(@res, $tk->[$i]);
	    } else { die "Unknown type: $type\n"; }
	} else {
	    push(@res, $tk->[$i]);
	}
    }
    return @res;
}

sub mk_clone_true() {
    my ($tk, $reg, $target, $cond) = @_;
    return &mk_clone(@_, $cond->{$target}, &negative_cond($cond->{$target}));
}

sub mk_clone_false() {
    my ($tk, $reg, $target, $cond) = @_;
    return &mk_clone(@_, &negative_cond($cond->{$target}), $cond->{$target});
}

sub mk_clone()
{
    my ($tk, $reg, $target, $cond, $tg_ct, $tg_cf) = @_;
    return () if !exists $reg->{$target};

    my ($b, $e) = @{$reg->{$target}};
    my @res;
    for (my $i = $b; $i <= $e; $i++) {
	if (my ($type, $id)  = ($tk->[$i] =~ /^_PRE_(\w+)\s+(#\w+)/)) {
	    if ($cond->{$id} eq $tg_ct || $cond->{$id} eq $tg_cf) {
		my $ignore = ($cond->{$id} eq $tg_ct) ? "ELSE" : "IFDEF";
		if ($type eq $ignore) { # ignore all to the next
		    $i++ until $tk->[$i+1] =~ /^_PRE_\w+\s+$id/;
		} else { # ignore the directive
		    $i++ until $tk->[$i] =~ /^E_DIRE/;
		}
		$i++ if $tk->[$i+1] =~ /^SP_NL/; # skip a tail new line.
		next;
	    }
	}
	push(@res, $tk->[$i]);
    }
    return @res;
}

sub cancel_inner_ifdef() { # cancels ifdefs inside the targets.
    my ($tk, $is_target) = @_;
    my $depth = 0;
    my %cancel;
    for (my $i = 0; $i < @$tk; $i++) {
	my ($type, $id) = ($tk->[$i] =~ m/_PRE_(\w+)\s+(#\w+)/);
	next if (!$id);
	if ($type eq "IFDEF" && $is_target->{$id}) {
	    $cancel{$id} = 1 if ($depth > 0);
	    $depth++;
	} elsif ($type eq "ENDIF" && $is_target->{$id}) {
	    $depth--;
	}
    }
#    print "canceled inner ifdefs: ", join(", ", keys %cancel), "\n";
    return %cancel;
}

sub prepare_rm_reg() {
    my ($is_target, $then_reg, $else_reg, $cancel) = @_;
    delete @$is_target{keys %$cancel};
    delete @$then_reg{keys %$cancel};
    delete @$else_reg{keys %$cancel};

    my @rm_reg = (values %$then_reg, values %$else_reg);
    @rm_reg = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @rm_reg;
    return @rm_reg;
}

sub cancel_overwrapped_ifdef() { # cancels ifdefs whose regions overwrap others.
    my ($reg, $tk) = @_;

    my %cancel;
    my ($b0, $e0) = (0, 0); # dummy;
    foreach (@$reg) {
	my ($b, $e, $id) = @$_;
	if ($e0 > $b) { # the region overwraps to the former.
	    $cancel{$id} = 1;
	} elsif (!$cancel{$id}) {  # not overwrapped.
	    # There some cases the regions do not overwrap each other,
            # but each ifdef exists in the other region.
	    map {/^_PRE_\w+\s+(#\w+)/ && ($cancel{$1} = 1)} @{$tk}[$b .. $e];
	    ($b0, $e0) = ($b, $e);
	}
    }
#    print "canceled overwrapped ifdefs: ", join(", ", keys %cancel), "\n";
    return %cancel;
}

sub prepare_rm_reg2() {
    my ($is_target, $then_reg, $else_reg, $cancel, $idx) = @_;
    delete @$is_target{keys %$cancel};
    delete @$then_reg{keys %$cancel};
    delete @$else_reg{keys %$cancel};
    my @rm_reg = (values %$then_reg, values %$else_reg);
    @rm_reg = sort {$idx->{"IFDEF $a->[2]"} <=> $idx->{"IFDEF $b->[2]"}} @rm_reg;
#    print map("[".join(", ", @$_)."]", @rm_reg), "\n";# die;
    return @rm_reg;
}

sub cancel_overwrapped_ifdef2() { # cancels ifdefs whose regions overwrap others.
    my ($reg, $tk) = @_;

    my %cancel;
    my @checked_reg = @$reg;
    foreach my $r1 (@$reg) {
	my ($b1, $e1, $id1) = @$r1;
	my @cr;
	next if $cancel{$id1};
	foreach my $r2 (@checked_reg) {
	    my ($b2, $e2, $id2) = @$r2;
	    next if $cancel{$id2};  # cancelled unwrapped regions.
	    if ($id1 ne $id2 && $b1 <= $e2 && $e1 >= $b2) {
		$cancel{$id2} = 1;  # $r1 and $r2 is wrapped
	    } else {
		push(@cr, $r2);
	    }
	}
	@checked_reg = @cr;
        # There some cases the regions do not overwrap each other,
        # but each ifdef exists in the other region.
	map {/^_PRE_\w+\s+(#\w+)/ && ($cancel{$1} = 1)} @{$tk}[$b1 .. $e1];
    }
#    print "canceled overwrapped ifdefs: ", join(", ", keys %cancel), "\n";
    return %cancel;
}



###########################################################################
sub optimize_elif() {
    my $tk = shift;
    ($tk) = &parse_ifdef_struct($tk);
    $tk = &reconstruct_elif($tk); # recover non target elif.
    $tk = &add_mark_to_target($tk);
    $tk = RewriteTokens->rep(q(
    @ANY => "(?:.*\n)*?"
    # endif and else only.
    @DIRE => "(?:(?:PRE_\w+|_[BE]_C|SP_[BC]).*\n)+"

    # move marks to '#else'.
    { $m:_MARK '(?>':X $if#1:_PRE_IFDEF $any:ANY $el#1:_PRE_ELSE ')':X }
    =>> { $if $any $m $el  }

    # convert "<mark>#else #if ... #endif #endif" to "<mark>#if ... #endif"
    { $m:_MARK $#t:_PRE_ELSE $#1:B_DIRE $:DIRE $#1:E_DIRE  $:SP_NL
      $if#2:_PRE_IFDEF '(?>':X $any:ANY $en#2:_PRE_ENDIF ')':X
      $b#3:B_DIRE $endif:DIRE $e#3:E_DIRE $:SP_NL
      $#t:_PRE_ENDIF $#4:B_DIRE $:DIRE $#4:E_DIRE }
    =>> { $m $if:_PRE_ELIF $any $en $b $endif $e }

    # convert "<mark>#if" to "<mark>#elif"
    { $m:_MARK $ei#1:_PRE_ELIF $b:B_DIRE $pt:PRE_TOP $[sp: $:/SP_N?[BC]/ $]*
     $pd:PRE_DIR/if/ }
    => { $m $ei:_PRE_IFDEF $b $pt $sp 'elif':PRE_DIR }
    { $m:_MARK $ei#1:_PRE_ELIF $b:B_DIRE $pt:PRE_TOP $[sp: $:/SP_N?[BC]/ $]*
     $pd:PRE_DIR/ifdef/ }
    => { $m $ei:_PRE_IFDEF $b $pt $sp 'elif':PRE_DIR ' ':SP_B 'defined':OP }
    { $m:_MARK $ei#1:_PRE_ELIF $b:B_DIRE $pt:PRE_TOP $[sp: $:/SP_N?[BC]/ $]*
    $pd:PRE_DIR/ifndef/ }
    => { $m $ei:_PRE_IFDEF $b $pt $sp 'elif':PRE_DIR ' ':SP_B
         '!':OP 'defined':OP }
          ))->rewrite($tk);

    return $tk;
}

sub make_reg_consistent() {
    my ($then_reg, $else_reg, $tk) = @_;

    foreach my $id (keys %$then_reg) {
#	print "Check consistecy for $id\n";
	die "lack of reg: $id" if !exists $else_reg->{$id};
	if (($then_reg->{$id}->[0] > $then_reg->{$id}->[1])
	    && ($else_reg->{$id}->[0] > $else_reg->{$id}->[1])) {
	    delete $then_reg->{$id};
	    delete $else_reg->{$id};
	    next;
	}
	my $ifdef = &find_unpair_dire($then_reg->{$id}, "ENDIF", "IFDEF", $tk);
	my $endif = &find_unpair_dire($else_reg->{$id}, "IFDEF", "ENDIF", $tk);
	if ($ifdef) {
#	    print "Find unpair ifdef in then part: $ifdef\n";
	    $else_reg->{$id} = &extend_reg($else_reg->{$id}, $ifdef, $tk, 1);
	}
	if ($endif) {
#	    print "Find unpair endif in else part: $endif\n";
	    $then_reg->{$id} = &extend_reg($then_reg->{$id}, $endif, $tk, -1);
	}
    }
}

sub find_unpair_dire() {
    my ($reg, $in, $out, $tk) = @_;
    my ($start, $end, $id) = @$reg;

    return undef if ($start > $end);

    my $delta = 1;
    if ($in eq "ENDIF") {
	($end, $start) = ($start, $end);
	$delta = -1;
    }

    my $prep_level = 0;
    my @res;
    for (my $i = $start; $i != $end; $i += $delta) {
	my ($type, $id) = ($tk->[$i] =~ /^_PRE_(\w+)\s+(#\w+)/);
	next if (!$type);
	if ($type eq $in) { ++$prep_level; }
	elsif ($type eq $out) {
	    if ($prep_level > 0) { --$prep_level; } else { push(@res, $id) }
	}
    }
    return $res[-1];
}

sub extend_reg() {
    my ($reg, $target, $tk, $dir) = @_;
    my ($start, $end, $id) = @$reg;
    my $delta = 1;
    if ($dir < 0) { # then part
	($start, $end) = ($end, $start);
	$delta = -1;
    }

    for (my $i = $end+1; 0 <= $i && $i < @$tk; $i += $delta) {
	my ($type, $id) = ($tk->[$i] =~ /^_PRE_(\w+)\s+(#\w+)/);
	next if (!$type);
	if ($type =~ /IFDEF|ENDIF/ && $id eq $target) {
#	    print "Found a new end, and change to $i from $end.\n";
	    $end = $i;
	    last;
	}
    }
    if ($dir < 0) { # then part
	($start, $end) = ($end, $start);
    } else { # else parth
	++$end until $tk->[$end] =~ /^SP_NL/;
    }
    return [$start, $end, $id];
}

#####
sub dump_code()
{
    my $tk = shift;
    print "Dump <Dump:\\n>\n". join("\n", @$tk)."\n";
}
