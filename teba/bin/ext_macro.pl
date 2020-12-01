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
use lib "$Bin";
use lib "$Bin/../TEBA";
use lib "$Bin/../TEBA/ProgPattern";

use strict;
use warnings;

use ProgReg;
use ProgTrans;
use RewriteTokens;
use CParser;

my $MACRO_MASK = "__HERE_IS_MASKED_MACRO__";
my ($cmd) = ($0 =~ m|([^/]+)$|);
my $ext_mode = ($cmd =~ /^ext/);  # for ext_macro.pl

use Getopt::Std;
my %opts = ();

if (!getopts("vhdf:m:spl:rtTo:NB", \%opts)) {
    $opts{h} = 1;
}

if (!$opts{h} && !$opts{f} && !$opts{l} && !$opts{m}) {
    print "Error: no pattern is specified. Use -f, -l or -m.\n";
    $opts{h} = 1;
}

if ($opts{h}) {
    print STDERR
	"$cmd.pl [-BdhNprstTv] [-f <file>] [-l <file>] [-m <macro_def>] [-o <output_file> [<source_file>]\n",
        "  -f <file> : extracts macro definitions from <file>.\n",
        "  -l <file> : loads patterns from <file> and apply them.\n",
        "  -m <macro_def> : uses a macro definition <macro_def>.\n",
        "  -r : apply macro patterns recursively.\n",
        "  -s : allows to modify all macro definitions.\n",
        "  -t : reads source file as a token stream.\n",
        "  -T : outputs source file as a token stream.\n",
        "  -p : outputs reverse patterns of macro definitions.\n",
        "  -o <file> : outputs into <file>, instead of STDIN.\n",
        "  -B : loads patterns not as macro body when using the option -l.\n",
        "  -N : does not apply normalization of macro definitions.\n",
        "  -v : verbose mode.\n",
        "  -d : debug mode.\n",
        "  -h : help.\n";
    exit(1);
}

$opts{N} = 1 if $ext_mode;

if ($opts{o}) {
    open(STDOUT, '>', $opts{o}) || die "Can't write to $opts{o}: $!";
}

my $def_src = "";

if ($opts{f}) {
    open(my $f, '<', $opts{f}) || die "Can't open $opts{f}: $!";
    $def_src = join('', <$f>);
    close($f);
}
if ($opts{m}) {
    $def_src .= $opts{m};
}

my $all_pt;
if ($opts{l}) {
    open(my $pfile, '<', $opts{l}) || die "Can't open $opts{l}: $!";
    $all_pt = join('', <$pfile>);
    close($pfile);
}

my @defs = &get_macro_definitions($def_src);

if ($opts{p}) {
    foreach my $e (@defs) {
	my $name = Tokenizer->join_tokens($e->{name});
	my $pt = &gen_macro_reverse_pattern($e);
	print "##Name:$name\n$pt\n";
    }
    exit(0);
}

my $src = join('', <>);

$src = CParser->new()->parse($src) if !$opts{t};

if ($opts{l}) {
    foreach my $pt (&split_patterns($all_pt)) {
	if ($opts{v}) {
	    print STDERR "Macro definition: $pt->{name}\n";
	}
	my $src1 = ProgTrans->new({d => $opts{d}, m => !$opts{B}})
	    ->set_pattern($pt->{pt})->rewrite($src);
	if ($opts{v}) {
	    my ($s0, $s1) = Tokenizer->join_tokens($src, $src1);
	    print STDERR "Result: ", 
	    ($s0 eq $s1 ? "--none--" : "## modified ##"), "\n\n";
	}
	$src = $src1;
    }
    print Tokenizer->join_tokens($src);
    exit(0);
} 

my $gen_macro_pattern = 
    ($ext_mode ? \&gen_macro_extract_pattern : \&gen_macro_reverse_pattern);

foreach my $e (@defs) {
    if ($opts{v}) {
	my ($n, $a, $b) =
	    Tokenizer->join_tokens($e->{name}, $e->{args}, $e->{body});
	print STDERR "Macro definition: #define $n",
	exists $e->{args} ? "($a) " : " ", "$b\n";
    }
    my $pt = $gen_macro_pattern->($e);
    print "Pattern:\n$pt\n" if $opts{d};
    my $src1 = $src;
    ($src1, my $d) = &save_macro_def($src1, $e) unless $opts{s};
    $src1 = ProgTrans->new({d => $opts{d}, r => $opts{r}})
	->set_pattern($pt)->rewrite($src1);
    $src1 = &unsave_macro_def($src1, $d) unless $opts{s};
    if ($opts{v}) {
	my ($s0, $s1) = Tokenizer->join_tokens($src, $src1);
	print STDERR "Result: ", ($s0 eq $s1 ? "--none--" : "## modified ##"),
	"\n\n";
    }
    $src = $src1;
}

$src = Tokenizer->join_tokens($src) if !$opts{T};
print $src;

#########################################################################

sub save_macro_def() {
    my ($src, $e) = @_;
    my ($name) = ($e->{name} =~ m/^\w+\s+<(\w+)>$/);
    my $arg = (exists $e->{args}) ? '(${:ARGLIST})' : "";

    my @defs = map($_->{all}, ProgReg->new({d=>0})
		   ->set("\$[all: #define $name$arg \${:ANY} \$]")
		   ->parse($src));

    my $pt = sprintf("%%before\n%s\n%%after\n%s\n%%end\n",
		     "#define $name$arg \${:ANY}",
		     "#$MACRO_MASK");
    $src = ProgTrans->new()->set_pattern($pt)->rewrite($src);

    return ($src, \@defs);
}

sub unsave_macro_def() {
    my ($src, $d) = @_;
    $src =~ s/PRE_TOP\s+<#>\nPRE_DIR\s+<$MACRO_MASK>\n/shift @$d/eg;
    return $src;
}

sub get_macro_definitions() {
    my $src = shift;
    my @res;

    my @patterns = (
#	'#define ${name:ID_MC}$[:(${args:ARGLIST})$] ${body:ANY}',
	'#define ${name:ID_MC}(${args:ARGLIST}) ${body:ANY}',
	'#define ${name:ID_MC} ${body:ANY}'
	);
    my $tk = $src;
    $tk = CParser->new()->parse($tk) if !$opts{t};
    $tk = &normalize_macro_def($tk) unless $opts{N};
    foreach (@patterns) {
	my @en = ProgReg->new()->set($_)->parse($tk);
	@en = grep(!&is_simple($_->{body}), @en) unless $ext_mode;
	push(@res, @en);
    }
    return @res;
}

sub gen_macro_extract_pattern() {
    my $e = shift;

    my @args = grep(/^ID/, split(/\n/, $e->{args} || 0));
    my %refs = map { $_ => 1 } grep(/^ID/, split(/\n/, $e->{body}));

    if (@args) {
	my (@vdef, @vref);
	push(@vdef, '@SP => "(?:SP.*+\n)*"');
	foreach my $v (@args) {
	    my ($tp, $tx) = ($v =~ /^(\w+)\s+<(.*)>$/);
	    if ($tx eq "...") {
		push(@vdef, "{ \$v:/$tp//$tx/ } => { '\${__VA_ARGS__:ARGLIST}':$tp }");
		push(@vref, "{ \$v:/ID.*//__VA_ARGS__/ } => { '\${__VA_ARGS__}':$tp }");
	    } else {
		push(@vdef, "{ \$v:/$tp//$tx/ } => { '\${$tx:EXPR}':$tp }");
		push(@vref, "{ \$v:/$tp//$tx/ } => { '\${$tx}':$tp }") if $refs{$v};
	    }
	}
	$e->{args} = RewriteTokens->seq(@vdef)->rewrite($e->{args});
	$e->{body} = RewriteTokens->seq(@vref)->rewrite($e->{body});
    }

    # converts PRE_JOIN to RewriteTokens JOIN operators.
    # remove \\n and following spaces.
    $e->{body} = RewriteTokens->seq(q(
	  { $pj:PRE_JOIN } => { '$##':JOIN } { $pj:PRE_S } => { '$#':PRE_S }
          { $[: $:/SP_[BC]/ $]* $:SP_NC } => {  }
	))->rewrite($e->{body});

    my ($body, $args, $name) =
	Tokenizer->join_tokens($e->{body}, $e->{args}, $e->{name});

    my $pt = sprintf("%%ex\n%%before\n %s%s\n%%after\n %s\n%%end\n",
		     $name, (exists $e->{args} ? "($args)" : ""), $body);
    return $pt;
}

sub gen_macro_reverse_pattern() {
    my $e = shift;

    my @args = grep(/^ID/, split(/\n/, $e->{args} || 0));
    my %refs = map { $_ => 1 } grep(/^ID/, split(/\n/, $e->{body}));

    if (@args) {
	my (@vref, @vdef);
	# check the identifiers following PRE_S, and connecting by PRE_JOIN
	my $pre_s = 0;
	my %idvf;
	my $last_var_id;
	foreach my $v (split("\n", $e->{body})) {
	    if ($v =~ /^PRE_S/) {
		$pre_s = 1;
	    } elsif ($v =~ /^PRE_JOIN/) {
		$pre_s = 1;
		$idvf{$last_var_id} = 1 if $last_var_id;
	    } elsif ($v =~ /^ID\w+\s+<(\w+)>$/) {
		if ($pre_s == 1) {
		    $idvf{$1} = 1;
		    $pre_s = 0;
		}
		$last_var_id = $1;
	    }
	}
	push(@vdef, '@SP => "(?:SP.*+\n)*"');
	foreach my $v (@args) {
	    my ($tp, $tx) = ($v =~ /^(\w+)\s+<(.*)>$/);
	    push(@vref, "{ \$v:/$tp//$tx/ } => { '\${$tx}':$tp }") if $refs{$v};
	    if ($tp =~ /^ID/ && $idvf{$tx}) {
		push(@vdef,
 "{ \$pj:PRE_S \$sp:SP \$v:/$tp//$tx/ } => { \$pj \$sp '\${$tx:$tp}':LIS }",
		     "{ \$v:/$tp//$tx/ } => { '\${$tx:$tp}':ID_VF }");
	    } else {
		push(@vdef, "{ \$v:/$tp//$tx/ } => { '\${$tx:EXPR}':$tp }");
	    }
	}
	$e->{args} = RewriteTokens->seq(@vref)->rewrite($e->{args});
	$e->{body} = RewriteTokens->seq(@vdef)->rewrite($e->{body});
    }

    # converts PRE_JOIN to RewriteTokens JOIN operators.
    $e->{body} = RewriteTokens->seq(
	q({ $pj:PRE_JOIN } => { '$##':JOIN } { $pj:PRE_S } => { '$#':PRE_S }))
	->rewrite($e->{body});

    my ($body, $args, $name) =
	Tokenizer->join_tokens($e->{body}, $e->{args}, $e->{name});

    my $pt = sprintf("%s\n%%before\n %s\n%%after\n %s%s\n%%end\n",
		     &is_expr($e->{body})? "%ex" : "",
		     $body, $name, (exists $e->{args} ? "($args)" : ""));
    return $pt;
}

sub is_simple() {
    my @tk = split("\n", $_[0]);
    @tk = grep(!/^([BE]_P|LI|SP_)/, @tk);
    return (@tk < 2);
}

sub is_expr() {
    my @tk = split("\n", $_[0]);
    return 1;
# For preserving B_ST and E_ST surrounding the replaced text,
# every patterns should be treated as expressions.
#    return (($tk[-1] =~ /^E_P/) || ($tk[-2] !~ /^SC/));
#    return ($tk[-1] =~ /^E_P/);
}

sub split_patterns()
{
    my $all = shift;
    my @res;

    my @pts = split(/^##Name:/m, $all);
    shift(@pts);  # ignore an empty element.
    foreach (@pts) {
	s/^(\w+)\n//;
	my $name = $1;
	my %e = ( name => $name, pt => $_ );
	push(@res, \%e);
    }
    return @res;
}

use BeginEnd;
use BracketsID;

sub normalize_macro_def() {
    my $tk = shift;
    my $vars = q!## Types for Pattern Variables
##
## Note: The following definitions are still experimental.
##       Please feed back to the auther if you modify and add definitions.

# ANY: any tokens
@ANY => "(?:.*+\n)*?"

# SP: spaces, newlines and comments
@_SP =>"SP.*+\n"
@SP  => "(?:@_SP)*?"

# Identifier
@ID => "ID.*+\n"
@VAR => "ID_(?:VF|MB|MC).*+\n"
@FNAME => "(?:IDN|ID_VF).*\n(?:@SP(?:PRE_JOIN.*\n)@SP(?:IDN|ID_VF|ID_TP).*\n)*+"

# EXPR: an expression
@_STRUCT_REF => "(?:B_(?:SUE|SCT|UN|EN).*+\n(?>(?:@ANY)E_(?:SUE|SCT|UN|EN).*+\n))"

@_EXPR => "(?:ID|OP|[PA]_|CA|LI|[BE]_(?:FR|CAST|P)).*+\n|@_STRUCT_REF"
@EXPR => "(?:(?:@_EXPR)(?:@_EXPR|@_SP)*?)?"

# DECR: a declarator
@_DECR => "@_EXPR|(?:C_|[BE]_CP).*+\n"
#@DECR => "(?:@_DECR)(?:(?:@_SP)*(?:@_DECR))*"
@DECR => "(?:@_DECR)(?:@_DECR|@_SP)*"

# _STMT: elements of statements
@_STMT => "@_DECR|(?:SC|B|E|ATTR|RE|CT).*+\n"

@STMT => "B_ST\s+(?<#_ST>#\w+)\s.*+\n(?>(?:@ANY)E_ST\s+\k<#_ST>\s.*+\n)"
@DECL => "B_DE\s+(?<#_DE>#\w+)\s.*+\n(?>(?:@ANY)E_DE\s+\k<#_DE>\s.*+\n)"
@FUNCDEF => "B_FUNC\s+(?<#_FU>#\w+)\s.*+\n(?>(?:@ANY)E_FUNC\s+\k<#_FU>\s.*+\n)"
#@STMT => "B_ST\s+(#\w+)\s.*+\n(?>(?:@_STMT|@_SP)*?E_ST\s+\g{-1}\s.*+\n)"
#@DECL => "B_DE\s+(#\w+)\s.*+\n(?>(?:@_STMT|@_SP)*E_DE\s+\g{-1}\s.*+\n)"

# TYPE: token sequences of a type (not supporting enum and union)
@_TYPE => "(?:(?:ID_(?:TP|TAG)|[BE]_SCT).*?\n|RE_SUE\s+<struct>\n)"
@TYPE => "@_TYPE(?:(?:SP.*?\n)*@_TYPE)*"

# Argument List
@ARGLIST => "@EXPR"

@_DIRE => "B_DIRE.*+\n(?>(?:@ANY)E_DIRE).*+\n"
@DIRE => "@_DIRE"
!;
    my $pt;
    my $be = BeginEnd->new();
    my $bi = BracketsID->new();

    $pt = q@{
 $t01#E0012:B_DIRE $t02:PRE_TOP/#/ $t03:SP $t04:PRE_DIR/define/ $t05:SP $t06#E0013:B_P $t07#E0014:B_FR $t08#E0015:B_P $name:ID_MC/\w+/ $t09#E0015:E_P $t10:SP $t11#B0001:P_L/\(/ $t12:SP $args:ARGLIST $t13:SP $t14#B0001:P_R/\)/ $t15#E0014:E_FR $t16#E0013:E_P $t17:SP $t18#E0016:B_MCB $t19#E0017:B_ST $t20:CT_DO/do/ $t21:SP $body:STMT $t22:SP $t23:CT_BE/while/ $t24:SP $t25#E0018:B_P $t26#B0002:P_L/\(/ $t27:SP $t28#E0019:B_P $t29:LIN/0/ $t30#E0019:E_P $t31:SP $t32#B0002:P_R/\)/ $t33#E0018:E_P $t34#E0017:E_ST $t35#E0016:E_MCB $t36:SP $t37#E0012:E_DIRE
} => {
 '':B_DIRE '#':PRE_TOP 'define':PRE_DIR ' ':SP_B '':B_P '':B_FR '':B_P $name '':E_P '(':P_L $args ')':P_R '':E_FR '':E_P ' ':SP_B '':B_MCB $body '':E_MCB '':E_DIRE
}
@;
    $tk = RewriteTokens->seq($vars, $pt)->rewrite($tk);
    $tk = $be->conv($bi->conv($tk));


    $pt = q@{
 $t01#E0009:B_DIRE $t02:PRE_TOP/#/ $t03:SP $t04:PRE_DIR/define/ $t05:SP $t06#E0010:B_P $name:ID_MC/\w+/ $t07#E0010:E_P $t08:SP $t09#E0011:B_MCB $t10#E0012:B_ST $t11:CT_DO/do/ $t12:SP $body:STMT $t13:SP $t14:CT_BE/while/ $t15:SP $t16#E0013:B_P $t17#B0001:P_L/\(/ $t18:SP $t19#E0014:B_P $t20:LIN/0/ $t21#E0014:E_P $t22:SP $t23#B0001:P_R/\)/ $t24#E0013:E_P $t25#E0012:E_ST $t26#E0011:E_MCB $t27:SP $t28#E0009:E_DIRE
} => {
 '':B_DIRE '#':PRE_TOP 'define':PRE_DIR ' ':SP_B '':B_P $name '':E_P ' ':SP_B '':B_MCB $body '':E_MCB '':E_DIRE
}
@;
    $tk = RewriteTokens->seq($vars, $pt)->rewrite($tk);
    $tk = $be->conv($bi->conv($tk));


    $pt = q@{
 $t01#E0008:B_DIRE $t02:PRE_TOP/#/ $t03:SP $t04:PRE_DIR/define/ $t05:SP $t06#E0009:B_P $t07#E0010:B_FR $t08#E0011:B_P $name:ID_MC/\w+/ $t09#E0011:E_P $t10:SP $t11#B0001:P_L/\(/ $t12:SP $args:ARGLIST $t13:SP $t14#B0001:P_R/\)/ $t15#E0010:E_FR $t16#E0009:E_P $t17:SP $t18#E0012:B_MCB $t19#E0013:B_ST $t20#B0002:C_L/{/ $t21:SP $body:ANY $t22:SP $t23#B0002:C_R/}/ $t24#E0013:E_ST $t25#E0012:E_MCB $t26:SP $t27#E0008:E_DIRE
} => {
 '':B_DIRE '#':PRE_TOP 'define':PRE_DIR ' ':SP_B '':B_P '':B_FR '':B_P $name '':E_P '(':P_L $args ')':P_R '':E_FR '':E_P ' ':SP_B '':B_MCB $body '':E_MCB '':E_DIRE
}
@;
    $tk = RewriteTokens->seq($vars, $pt)->rewrite($tk);
    $tk = $be->conv($bi->conv($tk));


    $pt = q@{
 $t01#E0005:B_DIRE $t02:PRE_TOP/#/ $t03:SP $t04:PRE_DIR/define/ $t05:SP $t06#E0006:B_P $name:ID_MC/\w+/ $t07#E0006:E_P $t08:SP $t09#E0007:B_MCB $t10#E0008:B_ST $t11#B0001:C_L/{/ $t12:SP $body:ANY $t13:SP $t14#B0001:C_R/}/ $t15#E0008:E_ST $t16#E0007:E_MCB $t17:SP $t18#E0005:E_DIRE
} => {
 '':B_DIRE '#':PRE_TOP 'define':PRE_DIR ' ':SP_B '':B_P $name '':E_P ' ':SP_B '':B_MCB $body '':E_MCB '':E_DIRE
}
@;
    $tk = RewriteTokens->seq($vars, $pt)->rewrite($tk);
    $tk = $be->conv($bi->conv($tk));


    $pt = q@{
 $t01#E0008:B_DIRE $t02:PRE_TOP/#/ $t03:SP $t04:PRE_DIR/define/ $t05:SP $t06#E0009:B_P $t07#E0010:B_FR $t08#E0011:B_P $name:ID_MC/\w+/ $t09#E0011:E_P $t10:SP $t11#B0001:P_L/\(/ $t12:SP $args:ARGLIST $t13:SP $t14#B0001:P_R/\)/ $t15#E0010:E_FR $t16#E0009:E_P $t17:SP $t18#E0012:B_MCB $t19#E0013:B_P $t20#B0002:P_L/\(/ $t21:SP $body:ANY $t22:SP $t23#B0002:P_R/\)/ $t24#E0013:E_P $t25#E0012:E_MCB $t26:SP $t27#E0008:E_DIRE
} => {
 '':B_DIRE '#':PRE_TOP 'define':PRE_DIR ' ':SP_B '':B_P '':B_FR '':B_P $name '':E_P '(':P_L $args ')':P_R '':E_FR '':E_P ' ':SP_B '':B_MCB $body '':E_MCB '':E_DIRE
}
@;
    $tk = RewriteTokens->seq($vars, $pt)->rewrite($tk);
    $tk = $be->conv($bi->conv($tk));


    $pt = q@{
 $t01#E0005:B_DIRE $t02:PRE_TOP/#/ $t03:SP $t04:PRE_DIR/define/ $t05:SP $t06#E0006:B_P $name:ID_MC/\w+/ $t07#E0006:E_P $t08:SP $t09#E0007:B_MCB $t10#E0008:B_P $t11#B0001:P_L/\(/ $t12:SP $body:ANY $t13:SP $t14#B0001:P_R/\)/ $t15#E0008:E_P $t16#E0007:E_MCB $t17:SP $t18#E0005:E_DIRE
} => {
 '':B_DIRE '#':PRE_TOP 'define':PRE_DIR ' ':SP_B '':B_P $name '':E_P ' ':SP_B '':B_MCB $body '':E_MCB '':E_DIRE
}
@;
    $tk = RewriteTokens->seq($vars, $pt)->rewrite($tk);
    $tk = $be->conv($bi->conv($tk));


    $pt = q@
{ $ct:/CT_(?:BE|IF)/ $sp:SP $bp:B_P $pl#1:P_L $e:ANY $pr#1:P_R } 
=> {$ct $sp $bp '('#1:_XP_L $e ')'#1:_XP_R }
@;
    $tk = RewriteTokens->seq($vars, $pt)->rewrite($tk);
    $tk = $be->conv($bi->conv($tk));


    $pt = q@{
 $t01#E0004:B_P $t02#B0001:P_L/\(/ $t03:SP $t04#E0005:B_P $v:ID_VF/\w+/ $t05#E0005:E_P $t06:SP $t07#B0001:P_R/\)/ $t08#E0004:E_P
} => {
 '':B_P $v '':E_P
}
@;
    $tk = RewriteTokens->seq($vars, $pt)->rewrite($tk);
    $tk = $be->conv($bi->conv($tk));


    $pt = q@
{ $ct:/CT_(?:BE|IF)/ $sp:SP $bp:B_P $pl#1:_XP_L $e:ANY $pr#1:_XP_R } 
=> {$ct $sp $bp '('#1:P_L $e ')'#1:P_R}
@;
    $tk = RewriteTokens->seq($vars, $pt)->rewrite($tk);
    $tk = $be->conv($bi->conv($tk));


    $pt = q@
{ $:/ID.*//__VA_ARGS__/ } => { '${__VA_ARGS__:ARGLIST}':ID_VF }
{ $:ID_VF/\.\.\./ } => { '${__VA_ARGS__:ARGLIST}':ID_VF }
@;
    $tk = RewriteTokens->seq($vars, $pt)->rewrite($tk);
    $tk = $be->conv($bi->conv($tk));

    return $tk;
}
