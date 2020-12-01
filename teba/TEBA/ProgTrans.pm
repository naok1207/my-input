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

package ProgTrans;

use strict;
use warnings;

use CParser;
use Tokenizer;
use BeginEnd;
use BracketsID;
use IdUnify;
use PrepBranch;

use Algorithm::Diff qw(diff sdiff LCS traverse_sequences);

my $LIB;

BEGIN {
    ($LIB = $INC{__PACKAGE__ . ".pm"}) =~ s/[^\/]+$//;
    $LIB .= "ProgPattern/";
}

sub new() {
    my $opts = $_[1];
    my $self = bless {};
    $self->{opts} = $opts;
    return $self;
}

sub set_pattern() {
    my ($self, $text) = @_;

    my $mode = "end";
    my %pt;
    foreach (split("\n", $text)) {
	if (/^%\s*([rs])/) { $self->{opts}->{$1} = 1; next; }
	if (/^%\s*ex/) { $self->{opts}->{e} = 1; next; }
	if (/^%\s*(before|after|end)\s*$/) {
	    $mode = $1;
	    next;
	}
	$self->{$mode} .= "$_\n";
    }
    return $self;
}

sub default_vars()
{
    my $vars;
    open(R, "$LIB/default-pt.rules") || die "can't open $LIB/default-pt.rules.";
    $vars = join('', <R>);
    close(R);
    return $vars;
}

sub build() {
    my $self = shift;

    $self->{vars} = &default_vars();
    $self->{rule} = $self->gen_rules($self->gen_token_patterns());
    print "DEBUG-Rules:\n$self->{vars}\n$self->{rule}\n" if $self->{opts}->{d};

    my $rt = RewriteTokens->seq($self->{vars}, $self->{rule});
    print "DEBUG-Rules(dump):\n", $rt->dump(), "\n" if $self->{opts}->{d};
    my $be = BeginEnd->new();
    my $co = BracketsID->new();
    my $pb = PrepBranch->new();

    my $rmx = &gen_extra_stmt_remover();
    my $clean_up = &gen_cleanuper();
    my $opt_r = $self->{opts}->{r};


    $self->{rewrite} = sub {
	my $prg = shift;
	while (1) {
	    my $p0 = $prg;
	    my $p1 = $rt->rewrite($p0);

	    # remove extra XSPs
	    $p1 = $rmx->rewrite($p1);
	    $prg = $pb->parse($be->conv($co->conv($p1)));
	    $prg = $clean_up->rewrite($prg);

	    last if ($p0 eq $p1 || !$opt_r);
	}
	return $prg;
    };
    return $self;
}

sub rewrite() {
    my ($self, $prg) = @_;
    $self->build() if (!$self->{rewrite});
    return $self->{rewrite}($prg);
}

#######################################################################

sub preserve_spaces()
{
    my ($self, $pt_b, $pt_a) = @_;

    # Delete before-pattern spaces.
    my @after_pattern = split("\n", $pt_a);
    my @before = grep(!/^SP/, split("\n", $pt_b));
    my @after = grep(!/^SP/, @after_pattern);

    IdUnify->new()->set(\@before, \@after)->unify();

    # Add Number brfore-pattern.
    my $a = 0;
    @before = map(sprintf("$_ \#D%04d", ++$a), @before);
    @after = map(sprintf("$_ \#D%04d", ++$a), @after);

    # Algorithm:Diff を利用した最長共通部分列
    my (%lmbe, %lmaf);

    my $match = sub { # 適合した字句の間の関係を覚えるサブルーチン
	my ($lcsb) = ($before[$_[0]] =~ /(\#D\w+)$/);
	my ($lcsa) = ($after[$_[1]] =~ /(\#D\w+)$/);
	$lmbe{$lcsb} = $lcsa;
	$lmaf{$lcsa} = $lcsb;
    };

    my $keygen = sub { # 比較時のキーの生成
	my $a = shift;
	$a =~ s/\s+#D\w+$//;
	if ($a =~ /<\$\{(\w*)(\:\w+)?\}\w*>/){
	    # $a = $1;
	    $a = "PVAR";  ## 名前無視モード
	}
	## ignore distinguish between 'for' and 'while'.
	#$a =~ s/^(CTRL_\w+)\s+<.*>$/$1\t<>/;
	return $a;
    };

    &traverse_sequences(\@before, \@after, { MATCH => $match }, $keygen);

    # パターン変数は必ず共通字句であるとする
    my %pvar_be;
    foreach (@before) {
	my ($name, $id) = (/<\$\{(\w+)\:\w+\}>\s+(#D\w+)$/);
	$pvar_be{$name} = $id if ($name);
    }
    foreach (@after) {
	my ($name, $id) = (/<\$\{(\w+)\}\w*>\s+(#D\w+)$/);
	next unless ($name);
	$lmbe{$pvar_be{$name}} = $id;
	$lmaf{$id} = $pvar_be{$name};
    }
    # Multiple occurrences of pattern variables are not supported.

    # afterの共通字句の番号をbeforeの番号に書換える
    foreach (@after) {
	my ($id) = (/^.*?\s(\#D\w+)$/);
	my $nid = exists $lmaf{$id} ? $lmaf{$id} : $id."X";
	s/(\#D\w+)$/$nid/;
    }	

    # beforeの不一致字句の番号の末尾にXを加える
    foreach (@before) {
	my ($id) = (/^.*?\s(\#D\w+)$/);
	$_ =~ s/$/X/ unless (exists $lmbe{$id});
    }	

    # beforeの字句の間に仮の空白字句を挿入する.
    my @sp_before;
    my $sp = 0;
    foreach (@before) {
	pop(@sp_before) if (/^_?E_/); # no spaces before E_*.
	push(@sp_before, $_);
	next if (/^_?B_/);  # no spaces after B_*
	push(@sp_before, sprintf("SP_PTVAR\t<\${_b%02d:SP}>", ++$sp));
    }
    pop(@sp_before);

    # 繰り返し型のグループ $[ $]+, $[ $]* がある場合には、その後ろの
    # SP_PT_VAR をグループに入れ、グループ内の空白は無視する。
    # 繰り返し型の内部の要素を個別に参照することは、基本的にありえない。
    my $in_repeat = 0;
    my @group;
    for (my $i = $#sp_before; $i >= 0; $i--) {
	my $t = \$sp_before[$i];
	if (my ($re) = ($$t =~ /^_E_GRP\s+#\w+\s+<\$\]([\*\+])?.?>/)) {
	    ++$in_repeat if ($re);
	    push(@group, $re);
	    if ($sp_before[$i+1] =~ /^SP_PTVAR/) {
		($$t, $sp_before[$i+1]) = ("SP_B\t< >", $$t);
	    }
	} elsif ($$t =~ /^_B_GRP/) {
	    --$in_repeat if (pop(@group));
	} elsif ($in_repeat) {
	    $$t =~ s/^SP_PTVAR.*$/SP_B\t< >/g;
	}
    }

    # after字句とafter_pattern字句を合成する．
    my @sp_after;
    foreach (@after_pattern) {
	my $t = /^SP/ ? "X$_" : shift(@after);
	push(@sp_after, $t);
    }

    # 字句と出現場所の関係 (共通字句の場所を探すために用いる)
    my %aflcs_num;
    for (my $i = 0; $i < @sp_after; $i++) {
	if ($sp_after[$i] =~ s/\s+(\#D\w+)$//) {
	    push(@{$aflcs_num{$1}}, $i);
            # パターン変数は複数回出現するので、配列で覚える
	}
    }

    #空白字句を最も近い共通字句に付随させる
    my @dl_sp;
    for (my $i = 0; $i < @sp_before; $i++) {
	next if ($sp_before[$i] !~ /^SP_PTVAR/);

	my $near = 0;
	for (my ($bi, $fi) = ($i, $i); $bi >= 0 && $fi < @sp_before; 
	     $bi--, $fi++) {
	    if ($bi >= 0 && &is_common_token($sp_before[$bi])) {
		$near = $bi - $i;
		last;
	    }
	    if ($fi < @sp_before && &is_common_token($sp_before[$fi])) {
		$near = $fi - $i;
		last;
	    }
	}
	unless ($near) { # 維持されない空白字句を記憶 (これはありえるのか?)
	    push(@dl_sp, $sp_before[$i]);
	    next;
	}
	my ($id) = ($sp_before[$i + $near] =~ /(\#D\w+)$/);
	foreach my $aid (@{$aflcs_num{$id}}) {
	    if ($near < 0) {  # 字句の末尾に挿入
		$sp_after[$aid] .= "\n".$sp_before[$i];
	    } else {          # 字句の先頭に挿入
		$sp_after[$aid] =~ s/^/$sp_before[$i]\n/;
	    }
	}
    }

    #beforeの疑似空白パターン変数を字句に書き直す.
    s/(\s+\#D\w+)?$/\n/ foreach (@sp_before);
    $pt_b = join("", @sp_before);

    #afterの疑似空白パターン変数を字句に書き直す.
    foreach (@sp_after) {
	if (/^((?:SP_PTVAR\s+<\$\{\w+\:SP\}>\n)+)((.|\n)+)$/) {
	    $_ = join("\n", reverse(split("\n", $1)))."\n$2";
	}
    }
    $pt_a = join("", map("$_\n", @sp_after));

    #維持されない空白字句は最後にまとめて保存
    if (@dl_sp > 0) {
	$pt_a .= join("",
		      "SP_NL <\\n>\n",
		      "SP_C </*drop out space Begin*/>\n",
		      "SP_NL <\\n>\n",
		      join("", map("$_\n"."SP_NL <\\n>\n", @dl_sp)),
		      "SP_C </*drop out space End*/>\n",
		      "SP_NL <\\n>\n");
    }

    return ($pt_b, $pt_a);
}

sub is_common_token()
{
    my $t = shift;
    return ($t !~ /^SP_PTVAR/ && $t !~ /X$/ && $t !~ /^_?[BE]/);
}

#######################################################################

sub gen_element_complementer() {
    my $r = RewriteTokens->seq(q(
# compilement expressions

{ $arglist:ARGLIST } => { '':P_L $arglist:_ARGLIST '':P_R }
# Changing ARGLIST to _ARGLIST as a temprary type.

# complement semicolons
{ $st:IDN/\$\{\w*:(?:STMT|DECL|FUNCDEF)\}/ } => { $st '':SC }
{ $st:IDN/\$\{\w+\}(?:STMT|DECL)/ } => { $st '':SC }
{ $[: $s:SC $]? $semi:SC_MARK } => { '':SC }));

  my %id_tbl;  # should be here, because the result of parsing %before
               # are used when parsing %after.

  return sub { 
      my $t = shift;
      &build_id_table($t, \%id_tbl);
      $t = &solve_var_type($t, \%id_tbl);
      return $r->rewrite($t);
   }
};

sub build_id_table() {
    my ($pt, $tbl) = @_;
    foreach (split("\n", $pt)) {
	if (/^ID\w+\s+<\$\{(\w+):(\w+)\}>$/) {
	    $tbl->{$1} = $2;
	}
    }
}

sub solve_var_type() {
    my ($pt, $tbl) = @_;
    my @tk = split("\n", $pt);
    my @ret;
    my %type_map = (
	"EXPR" => "IDN", "DECR" => "IDN", "DECL" => "IDN",
	"STMT" => "IDN", "TYPE" => "ID_TP", "ID" => "IDN",
	"VAR" => "IDN", "FNAME" => "IDN",
    );

    foreach (@tk) {
	if (/^ID\w+\s+<\$\{(\w*):(\w+)}>$/) {
	    my $type = $2;
	    $type = $type_map{$type} if ($type_map{$type});
	    $_ = "$type\t<\${$1:$2}>";
	} elsif (/^ID\w+\s+<\$\{(\w+)\}>$/ && $tbl->{$1}) {
	    my $type = $tbl->{$1};
	    $type = $type_map{$type} if ($type_map{$type});
#	    print "$tbl->{$1} => $type\n";
	    $_ = "$type\t<\${$1}$tbl->{$1}>"
	}
    }
    return join("\n", @tk)."\n";
}

sub gen_namespace_modifier() {
    my $r = RewriteTokens->seq(q({ $semi:SC// } => { }));
    return sub {
        my $t = shift;
        return $r->rewrite($t);
    }
}

#######################################################################

sub gen_token_patterns() {
    my $self = shift;

    my $parser = $self->gen_parser();

    $self->{before} = $parser->($self->{before});
    $self->{after} = $parser->($self->{after});

    # for preserving spaces
    if ($self->{opts}->{s}) {
	($self->{before}, $self->{after}) = 
	    $self->preserve_spaces($self->{before}, $self->{after});
    } else {
	$self->{before} = $self->normalize_spaces($self->{before});
    }
    $self->{after} = $self->normalize_spaces_for_after($self->{after});

#print $self->{before}, "\n";exit;
#print $self->{after}, "\n";exit;

    my @before = $self->gen_before_pattern($self->{before});
    my @after = $self->gen_after_pattern($self->{after});
#print join("\n", @before),"\n"; exit;
#print join("\n", @after),"\n"; exit;

    return (\@before, \@after);
}

sub gen_rules() {
    my ($self, $before, $after) = @_;
    return "{\n". join("", map(" $_", @$before)) . "\n} => {\n"
	. join("", map(" $_", @$after)) . "\n}\n";
}

sub gen_parser() {
    my $self = shift;

    my $parser = CParser->new();
    if ($self->{opts}->{b}) {
	$parser->use_prep_branch();
    }
    # Adding pattern-variable pattern as token.
    $parser->insert_token_def(join("\n",
				   'SP_PTVAR (\$\{\w+:SP\})',
				   'IDN (\$\{\w*(?::\w+)?\})',
				   'IDN (\$\{\{\w*(?::\w+)?\}\})',
				   '_IGN_B (\$\{\%begin\})',
				   '_IGN_E (\$\{\%end\})',
				   'SC_MARK (\$;)',
				   '_B_GRP (\$\[\w*:)',
				   '_E_GRP (\$\][\*\+]?[\?\+]?)',
#				   'SP_B_AGRP (\$\[\[\w*:)',
#				   'SP_E_AGRP (\$\]\][?*+]?)',
				   'SP_OR (\$\|)',
				   'PRE_JOIN (\$##)',
				   'PRE_S (\$#)',
				   'IDN (\$\[\w+\])'));

    my $clean_macro_mode = 0;
    if ($self->{opts}->{m}) {
	$parser->{beforePrep} = &gen_macro_mode();
	$clean_macro_mode = sub { my @t = split("\n", $_[0]);
				  shift(@t); pop(@t); return join("\n",@t)."\n"; }
    }
    $parser->{beforeMacroStmt} = &gen_element_complementer();
    $parser->{beforeNameSpaceRules} = &gen_namespace_modifier();
    $parser->add_types(join("\n",
			    '@_EXPR => "@_EXPR|_ARGLIST.*\n"',
			    '@DECL_ELEM => "@DECL_ELEM|_ARGLIST.*\n"',
			    '@_SP => "@_SP|(?:_[BE]_GRP|_IGN_[BE]|DIRE).*+\n"',
			    '@_ANYTOKEN => "(?:[^BES]|SC|[BE]_[^G]).*+\n"',
			    # @_ANYTOKEN is defined in prep.rules.
		       ));

    my $expr_sanitizer;
    if ($self->{opts}->{e}) {  # for expression mode
	$expr_sanitizer = &gen_expr_sanitizer();
    }
    my $sanitizer = &gen_pattern_sanitizer();

    return sub {
	my $pt = shift;
	$pt = $parser->parse($pt);
	if ($expr_sanitizer) {
	    $pt = $expr_sanitizer->rewrite($pt);
	}
	$pt = $sanitizer->rewrite($pt);
	if ($clean_macro_mode) {
	    $pt = $clean_macro_mode->($pt);
	}
	return $pt;
    };
}

sub gen_macro_mode() {
    return sub {
	return join("", "B_MCB\t<>\n", $_[0], "E_MCB\t<>\n");
    }
}

sub gen_expr_sanitizer() {
  return RewriteTokens->seq(q(
@_SP => "SP.*+\n"
@SP => "(?:@_SP)*+"
@_ANY => ".*+\n"
@ANY => "(?:@_ANY)*?"

# remove unit tokens
{ $ub:UNIT_BEGIN $sp1:SP $sb#1:B_ST $any:ANY $se#1:E_ST $sp2:SP $ue:UNIT_END }
=> { $ub $any $ue }
{ $ub:UNIT_BEGIN $sp1:SP $sb#1:B_DE $any:ANY $se#1:E_DE $sp2:SP $ue:UNIT_END }
=> { $ub $any $ue }
));
}

sub gen_pattern_sanitizer() {
    return RewriteTokens->seq(q(
@"token-patterns.def"

# remove unnecessary [BE]_P
{ $bp#1:B_P $st:/ID\w+//\$\[\w+\]/ $ep#1:E_P } => { $st }
{ $#1:B_P $:P_L $a:_ARGLIST $:P_R $#1:E_P } => { $a }

# remove unnecessary [BE]_ST and [BE]_P
{ $be#1:B_ST $st:/ID\w+//\$\[\w+\]/ $en#1:E_ST } => { $st }
{ $be#s:B_ST $bp#p:B_P  $st:ID_VF/\$\{\w*:(?:STMT|DECL|FUNCDEF)\}/ 
  $ep#p:E_P $sp:SP $en#s:E_ST } => { $st $sp }
{ $be#s:B_ST $bp#p:B_P $st:ID_VF/\$\{\w+\}(?:STMT|DECL)/
  $ep#p:E_P $sp:SP $en#s:E_ST } => { $st $sp }

{ $be#1:B_ST $decl:IDN/\$\{\w*:DECL\}/ $en#1:E_ST } => { $decl }

# Experimental: make the groups align borders of elements.
# This code is only for demo/init-decl.pt, and not general.
{ $gb#1:_B_GRP $sp:SP $b#2:/B_\w+/ $any1:ANY $ge#2:_E_GRP
  $any2:ANY $e#1:/E_\w+/ } =>> { $sp $b $gb $any1 $ge $any2 $e }
@|BeginEnd->conv|

# remove unit tokens
@PURE_SP0 => "(@_SPC)*"
{ $u:UNIT_BEGIN $sp:PURE_SP0 } => { }
{ $sp:PURE_SP0  $u:UNIT_END } => { }

# rename SP_OR to OR
{ $o:SP_OR } => { $o:OR }

#@BEGIN => "B_.*+\n"
#@END => "E_.*+\n"
#{ $g:B_AGRP $sp:SP $b:BEGIN } => { $sp $b $g }
#{ $e:END $sp:SP $g:E_AGRP } => { $g $e $sp }

));
}

sub normalize_spaces() {
    my ($self, $t) = @_;
    my $ss = RewriteTokens->seq(q(
@"token-patterns.def"

{ $any:TOKEN } => { $any ' ':SP_B }

@PURE_SP => "(?:@_SPC)++"
{ $b:/_?B_\w+/ $sp:PURE_SP } => { $b }
{ $sp:PURE_SP $e:/_?E_\w+/ } => { $e }

{ $sp:PURE_SP } => { ' ':SP_B }

# exception
{ $e:E_MCB } => { $e ' ':SP_B }
{ $g:_E_GRP/.*[\*+]/ } => { ' ':SP_B $g }
{ $g:_E_GRP/.*[\*+]/ $:SP_B } => { $g }
{ $:SP_B $j:PRE_JOIN/\$##/ } => { $j }
{ $j:PRE_JOIN/\$##/ $:SP_B } => { $j }
{ $ps:PRE_S/\$#/ $:SP_B } => { $ps }
{ $g:OR $:SP_B } => { $g }
));
    my $res = $ss->rewrite($t);
    $res =~ s/SP_B\s+< >\n$//;  # remove the tail space.
    return $res;
}

sub normalize_spaces_for_after() {
    my ($self, $t) = @_;
    my $ss = RewriteTokens->seq(q(
@"token-patterns.def"

{ $:_SP $join:PRE_JOIN } =>> { $join }
{ $join:PRE_JOIN $:_SP } =>> { $join }
));
    my $res = $ss->rewrite($t);
    return $res;
}


#######################################################################

my $ign_filter;
sub gen_IGN_filter() {
    $ign_filter //= RewriteTokens->seq(q(
{ $:/\w+/ $b:_IGN_B } =>> { $b }
{ $e:_IGN_E $:/\w+/ } =>> { $e }
{ $:_IGN_B $[: $sp:/SP\w+/ $]? } => {}
{ $[: $sp:/SP\w+/ $]? $:_IGN_E } => {}
));
   return $ign_filter;
}

sub gen_before_pattern() {
    my ($self, $pt) = @_;
    my @before = ();
    my $i = 0;

    $pt = (&gen_IGN_filter())->rewrite($pt);

    foreach (split("\n", $pt)) {
	my $t = "";
	if (/^\w+\s+<\$\{(\w*):(\w+)\}>$/) {
	    $t ="\$$1:$2";
	    $t =~ s/(:ID_\w+)$/$1\/\\w+\//;
	} elsif (/^\w+\s+<\$\{\{(\w*):(\w+)\}\}>$/) {
	    $t = "\$:ANY \$$1:$2 \$:ANY";
	} elsif (/^ID\w+\s+<\$\{(\w+)\}\w*>$/) {
	    $t = "\$$1";
	} elsif (/^SP_PTVAR\s+<\$\{(\w+:SP)\}>$/) { ##
	    $t = "\$$1";
	} elsif (/^SP/) {
	    $t = sprintf("\$_t%02d:SP", ++$i);
	} elsif (/^(?:_[EB]_GRP|OR)\s+(?:\#\w+\s+)?<(.*)>$/) {
	    $t = $1;
	} elsif (/^(?:PRE_JOIN|PRE_S)\s+<(\$.*)>$/) {
	    $t = $1;
	} elsif (/^(\w+)\s+(?:(#\w+)\s+)?<(.*)>$/) {
	    my ($tp, $id, $tk) = ($1, $2, $3);
	    $id = "" if !defined($id);
	    # $tk should be compared with a "" explicitly because $tk may be "0".
	    $tk =~ s/([()+\[\]*+?^.\\\/\$\@\|\&\%])/\\$1/g;
	    $tp =~ s!^ID_(VF|MC)!/ID_(?:VF|MC)/!;
	    $t = sprintf("\$_t%02d%s:%s%s", ++$i, $id, $tp, $tk ne "" ? "/$tk/" : "" );
	} else {
	    die "'$_'";
	}
	push(@before, $t);
    }
    return @before;
}

sub gen_after_pattern() {
    my ($self, $pt) = @_;
    my @after = ();

    $pt = (&gen_IGN_filter())->rewrite($pt);

    foreach (split("\n", $pt)) {
	my $t;
	if (/^\w+\s+<\$[\[{](\w+)(?::\w+)?[\]}]\w*>$/) {  # $[var] and ${var}
	    $t = "\$$1";
	} elsif (/^SP_PTVAR\s+<\$\{(\w+):SP\}>$/) {
	    $t = "\$$1";
	} elsif (/^(?:PRE_JOIN|PRE_S)\s+<(\$.*)>$/) {
	    $t = $1;
	} elsif (/^(\w+)\s+(?:(#\w+)\s+)?<(.*)>$/) {
	    $t = sprintf("'%s':%s", $3, $1);
	} else {
	    die "unknown: $_";
	}
	push(@after, $t);
    }
    return @after;
}

sub gen_extra_stmt_remover() {
    return RewriteTokens->seq(q(
@XBNL => "(?:XSP_(?:B|NL).*\n)*+"
@SBNLC => "SP_(?:[BC]|NL).*\n"
# [BE]_DIRE is an exception.
{ $[sp: $:SBNLC $]+ $x:/E_(?:[^D]\w|DE)/ } => { $x $sp }
{ $x:/B_(?:[^D]\w|DE)/ $[sp: $:SBNLC $]+ } => { $sp $x }

{ $sp:SBNLC $x:XBNL } => { $sp }
{ $x:XBNL $sp:SBNLC} => { $sp }

{ $x:XSP_B } => { $x:SP_B }
{ $x:XSP_NL } => { $x:SP_NL }
));
}

sub gen_cleanuper() {
    return RewriteTokens->seq(q(
@"token-patterns.def"

# remove virtual semicolons
{ $semi:SC// } => { }

# remove duplicate virtual tokens of statements
{ $b1#1:B_ST $sp1:SP $b2#2:B_ST $any:ANY $e2#2:E_ST $sp2:SP $e1#1:E_ST }
 =>> { $sp1 $b2 $any $e2 $sp2 }
));
}

1;
