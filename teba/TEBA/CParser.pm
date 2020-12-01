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

package CParser;

use strict;
use warnings;

use Tokenizer;
use BracketsID;
use CoarseGrainedParser;
use RewriteTokens;
use FixCma;
use EParser;
use BeginEnd;
use PrepBranch;
use TEBA2JSON;
use SymbolTable;
use JSON;

#use Data::Dumper;

my $LIB;

BEGIN {
    ($LIB = $INC{__PACKAGE__ . ".pm"}) =~ s/[^\/]+$//;
}

sub new()
{
    my $self = bless {};

    $self->{overrided_types} = "";
    $self->{token_definitions} = &read_file("token.def");

    return $self;
}

sub append_token_def() {
    my ($self, $def) = @_;
    $self->{token_definitions} .= "\n" . $def;
}

sub insert_token_def() {
    my ($self, $def) = @_;
    $self->{token_definitions} = $def . "\n" . $self->{token_definitions};
}

sub add_types()
{
    my ($self, $types) = @_;
    $self->{overrided_types} = $types;
    $self->build() if ($self->{build});  # rebuild
    return $self;
}

sub read_file() {
    my $name = shift;
    open(my $f, '<', "$LIB/$name") || die "Can't open $name: $!";
    my $t = join('', <$f>);
    close($f);
    return $t;
}

sub build()
{
    my $self = shift;

    $self->{Tokenizer} = Tokenizer->new()->set_def($self->{token_definitions});
    $self->{BracketsID} = BracketsID->new();

    $self->{Prep} = RewriteTokens->seq(&read_file("prep-token-pattern.def"),
	       &read_file("prep.rules"), $self->{overrided_types});

    my @types = (&read_file("token-patterns.def"), $self->{overrided_types});
    my $types = &read_file("token-patterns.def");

    $self->{CoarseGrainedParser} = CoarseGrainedParser->new()
	->add_types(@types)->add_overrided_types($self->{overrided_types});

    $self->{NameSpaceRules} =
	RewriteTokens->seq($types, &read_file("namespace.rules"),
			   $self->{overrided_types});
    $self->{MacroStmt} =
	RewriteTokens->seq($types, &read_file("macro-stmt.rules"),
			   $self->{overrided_types});

    $self->{EParser} = EParser->new()->add_types(@types)
	->add_overrided_types($self->{overrided_types});
    $self->{EParser}->use_flat() if ($self->{"use_flat_expr"});

    $self->{Adjust} =
	RewriteTokens->seq($types, &read_file("parser-adjust.rules"),
			   $self->{overrided_types});

    $self->{build} = 1;
    return $self;
}

sub disable_expr()
{
    my $self = shift;
    $self->{FixCma} = FixCma->new();
    delete $self->{Eparser};
    return $self;
}

sub use_flat_expr()
{
    my $self = shift;
    $self->{"use_flat_expr"} = 1;
    return $self;
}

sub use_prep_branch()
{
    my $self = shift;
    $self->{PrepBranch} = PrepBranch->new();
    return $self;
}

sub as_json() {
    my $self = shift;
    $self->{as_json} = 1;
    return $self;
}

sub as_raw_json() {
    my $self = shift;
    $self->{as_json} = 1;
    $self->{as_raw_json} = 1;
    return $self;
}

sub as_json_tree() {
    my $self = shift;
    $self->{as_json} = 1;
    $self->{as_json_tree} = 1;
    return $self;
}

sub  with_symboltable {
    my $self = shift;
    $self->{with_symboltable} = 1;
    return $self;
}

sub set_global_symbol_table {
    my ($self, $gfile) = @_;
    open(my $gf, "<", $gfile) || die "Can't open $gfile.";
    $self->{global_symbol_table} = JSON->new->decode(join('', <$gf>));
    close($gf);
    return $self;
}

sub parse()
{
    my ($self, $text) = @_;

    $self->build() unless $self->{build};
    $text = $self->{Tokenizer}->parse($text);
    $text = $self->parse_tokens($text);

#    $text = BeginEnd->new()->conv($text); # normalize for debug

    if ($self->{as_json}) {
	my $t2j = TEBA2JSON->new(\$text);

	my $j;
	if ($self->{as_raw_json}) {
	    $j = $t2j->raw()->json();
	} else {
	    $j = $t2j->json();
	    if ($self->{with_symboltable}) {
		my $sym = SymbolTable->new;
		if (exists $self->{global_symbol_table} ) {
		    $sym->global_table($self->{global_symbol_table})
		} else {
		    $sym = $sym->with_standard_global_table();
		}
		$sym->analyze($j->{json});
		$j->{json}->{sym} = $sym->root_tree();
	    }
	}

	if ($self->{as_json_tree}) {
	    $text = $j->tree();
	} else {
	    $text = $j->str();
	}
    }
    return $text;
}



sub parse_tokens()
{
    my ($self, $text) = @_;

    $self->build() unless $self->{build};
    $text = $self->{beforePrep}($text)	if ($self->{beforePrep});
    $text = $self->{Prep}->rewrite($text);
    $text = $self->{BracketsID}->adjust_brackets($text);  ## heuristics
    $text = $self->{BracketsID}->conv($text);

    $text = $self->{beforeMacroStmt}($text)
	if ($self->{beforeMacroStmt});
    $text = $self->{MacroStmt}->rewrite($text);           ## heuristics

    $text = $self->{beforeCoarseGrainedParser}($text) 
	if ($self->{beforeCoarseGrainedParser});
    $text = $self->{CoarseGrainedParser}->parse($text);

    $text = $self->{FixCma}->conv($text) if ($self->{FixCma});

    $text = $self->{beforeNameSpaceRules}($text)
	if ($self->{beforeNameSpaceRules});
    $text = $self->{NameSpaceRules}->rewrite($text);

    $text = $self->{EParser}->parse($text) if ($self->{EParser});
    $text = $self->{Adjust}->rewrite($text);

    $text = $self->{PrepBranch}->parse($text) if ($self->{PrepBranch});
    return $text;
}

sub SCtoCA()
{
    my ($self, $tokens) = @_;
    my @tk = split(/\n/, $tokens);

    my $in_paren = 0;
    foreach (@tk) {
	if (/^P_L/) {
	    $in_paren++;
	} elsif (/^P_R/) {
	    $in_paren--;
	} else {
	    s/^SC\s+<>$/CA\t<>/ if $in_paren;
	}
    }
    return join("\n", @tk). "\n";
}

sub check_validity()
{
    my ($self, $tokens) = @_;
    my @res;

    my @tks = split("\n", $tokens);

    my @temp_tokens = grep(/^(_\w+)/, @tks);
    if (@temp_tokens) {
	my $list = join("", map("##   $_\n", @temp_tokens));
	push(@res, "## Temporal virtual tokens still remain.\n$list");
    }

    my @id_stack;
    my $is_error = 0;
    foreach (@tks) {
	if (/^(?|B_(\w+)\s+(#\w+)|([APC])_L\s+(#\w+))/) {
	    push(@id_stack, "$1\t$2");
	} elsif (/^(?|E_(\w+)\s+(#\w+)|([APC])_R\s+(#\w+))/) {
	    my $t = pop(@id_stack);
	    if ($t eq "" || $t ne "$1\t$2") {
		push(@res, "## Illegal combinations for \"$_\"\n");
		push(@id_stack, $t);
		$is_error = 1;
		last;
	    }
	}
    }
    if (@id_stack) {
	if (!$is_error) {
	    push(@res, "## Stack is not empty.\n");
	}
	my $s = join("", map("##    $_\n", @id_stack));
	push(@res, "## Stack:\n$s");
    }

    my $expr_test = q(
     { $ep:E_P $sp:SP $bp:B_P } => { $ep '{:EXPR_ERROR:}':ERROR $sp $bp }
    );
    my $tk = RewriteTokens->seq(&read_file("token-patterns.def"), $expr_test)
	->rewrite($tokens);

     # Exception: the inside of #error, #pragma, #line  is not expressions.
    my $directive_exception = q(
     { $bd#1:B_DIRE $sp1:SP $pt:PRE_TOP $sp2:SP $dir:PRE_DIR/error|pragma|line/
      $[any: $:_ANYTOKEN_SP $]*? $ed#1:E_DIRE }
       => { $bd ''#1:_B_ER $sp1 $pt $sp2 $dir $any ''#1:_E_ER $ed }
     { $:ERROR in ER } => {}
     { $:/_[BE]_ER/ } => {}
    );

    my $typical_target = q(_\w+|internal_function|IF_LINT|\w*(?:ATTRIBUTE|attribute)\w*);
    my $code_exception = q(
     # string concatenation
     { $str:LIS } => { ''#1:_B_S $str ''#1:_E_S }
     { $es:_E_S $[: $:ERROR $]? $sp:SP '(?>':X $bp#1:B_P
       $expr:ANY $ep#1:E_P ')':X } =>> { $sp $bp $expr $ep $es }
     { '(?>':X $bp#1:B_P $expr:ANY $ep#1:E_P ')':X $[: $:ERROR $]?
       $sp:SP $bs:_B_S } =>> { $bs $bp $expr $ep $sp }
     { $:/_[EB]_S/ } => { }

     # a typical type of error
    { $ep:E_P $:ERROR $sp:SP $bp:B_P $[call: $:B_FR $:B_P $]?
      $id:/ID_\w+//).$typical_target.q(/ }
    => { $ep $id:TYPICAL_ERR_B $sp $bp $call $id }
    { $id:/ID_\w+//).$typical_target.q(/ $[ep: $:E_P $]+ $:ERROR }
    => { $id $ep $id:TYPICAL_ERR_F }

     # miss-recognized type name
     { $t:/ID_VF//(?:.*_t(?:ype)?|bool|uint32)/ $ep:E_P $:ERROR }
     => { $t:TYPE_NAME_ERR $ep }

     # attribute
     { $a:ATTR $[arg: $#1:B_P $:P_L '(?>':X $:ANY $#1:E_P ')':X $]? $:ERROR }
     => { $a:ATTR_ERR $arg }

     # __typeof__
    { $typeof:ATTR/__typeof__/ $sp1:SP $bp#1:B_P
      '(?>':X $any:ANY $ep#1:E_P ')':X $:ERROR }
    => { $typeof $sp1 $bp $any $ep }

     # Compound values
     { $pr:P_R $[ep: $:E_P $]+ $:ERROR $sp:SP $bp:B_P $cp:B_CP }
     => {$pr $ep $sp $bp $cp }

    );
    $tk = RewriteTokens->seq(&read_file("prep-token-pattern.def"),
			     $directive_exception)->rewrite($tk);

    $tk = RewriteTokens->seq(&read_file("token-patterns.def"),
			     $code_exception)->rewrite($tk);

    my @tk = split("\n", $tk);
    my $err = grep(/^ERROR\s/, @tk);
    my @t_err = grep(/^TYPICAL_ERR_[FB]/, @tk);
    my @n_err = grep(/^TYPE_NAME_ERR/, @tk);
    my @a_err = grep(/ATTR_ERR/, @tk);
    if ($err + int(@t_err) + int(@n_err) + int(@a_err) > 0) {
	push(@res, "## Uncombined expression exists.\n");
	my %te;
	map($te{$_}++, @t_err);
	my %tn;
	map($tn{$_}++, @n_err);
	my %an;
	map($an{$_}++, @a_err);
	push(@res, map("## $_ $te{$_}\n", keys %te));
	push(@res, map("## $_ $tn{$_}\n", keys %tn));
	push(@res, map("## $_ $an{$_}\n", keys %an));
	push(@res, "## Others: $err\n");
#	push(@res, $tk);
#	print $tk; exit;
    }

    # checking unusual curly braces. Ex. "foreach () { ... }"
    my $cl_check = q(
      { $cl:C_L } => { '':_CL_CHECK $cl }
      { $b:/B_\w+/ $:_CL_CHECK } => { $b }
      { $b:/ID_TAG|RE_SUE|E_LB|ID_TPCS/ $sp:SP $:_CL_CHECK } => { $b $sp }
      { $:/_CL_CHECK/ in CP } => { }
      { $[ns: $:RE_NAME/namespace/ $:SP $#1:B_P $:/ID\w+/ $#1:E_P $:SP $] $:_CL_CHECK } => { $ns }
    );
    $tk = RewriteTokens->seq(&read_file("token-patterns.def"),
			     $cl_check)->rewrite($tk);
    my $cl_err = grep(/^_CL_CHECK\s/, split("\n", $tk));
    if ($cl_err) {
	push(@res, "## CL_ERROR exists.\n");
#	print $tk; exit;
    }

    my $else_check = q(
      { $b:B_ST $e:CT_EL/else/ } => { $b '':_ELSE_CHECK $e }
    );
    $tk = RewriteTokens->seq(&read_file("token-patterns.def"),
			     $else_check)->rewrite($tk);
    my $else_err = grep(/^_ELSE_CHECK\s/, split("\n", $tk));
    if ($else_err) {
	push(@res, "## ELSE_ERROR exists.\n");
#	print $tk; exit;
    }

    if (@res) {
	unshift(@res, "\n## INVALID ##\n") if $err;
    }
    print STDERR @res;

#    return join("", @res);
}

## Workaround: join tokens to construct file names in include directives.
# this routine will be replaced by rule including $## operators.
sub join_to_PRE_H() {
    my ($self, $tk) = @_;
    my @res;
    my @name;
    foreach (split(/\n/, $tk)) {
	if (/^E_PRE_H/) {
	    my $n = Tokenizer->join_tokens(join("\n", @name, $_));
	    push(@res, "PRE_H\t<$n>");
	    @name = ();
	} elsif (/^B_PRE_H/ || @name > 0) {
	    push(@name, $_);
	} else {
	    push(@res, $_);
	}
    }
    return join("\n", @res);
}



1;
