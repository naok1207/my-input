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

package RewriteTokens;

#use strict;
#no strict "refs";
#use warnings;

#############
#  Rules ::= ( Rule | TypeDefine | Filter )*
#
#  TypeDefine ::= '@' Name '=>' '"' Pattern '"'
#  Filter ::= Include | PipeFilter | Break
#  Include ::= '@"' FileName '"'
#  PipeFilter ::= '@|' FilterCommand '|'
#  Break ::= '@!BREAK!'
#  Print ::= '@!PRINT!'
#
#  Rule ::= '{' BeforePattern '}' '=>' '{' AfterPattern '}'
#         | '{' BeforePattern '}' '=>>' '{' AfterPattern '}'
#         | '{' TypedToken in Type '}' => '{' '}'
#         | '{' TypedToken in Type '}' => '{' TypedToken '}'
#  BeforePattern ::= ( TypedToken | TextToken | PatternToken
#                    | VarReference | TextReference | BeginGroup | EndGroup
#                    | JoinOperator | StrOperator )+
#  TypedToken ::= '$' Name ( '#' BackReferenceId )?
#                     ':' ( Type | '/' Pattern '/' ) ( '/' Pattern '/' )?
#  TextToken  ::= '$' Name ( '#' BackReferenceId )? ':' '\'' Text '\'
#  VarReference ::= '$' Name
#  TextReference ::= '\'' Text '\'' ':' Type
#  BeginGroup ::= '$[' Name ':'
#  EndGroup ::= '$]' ( '*'|'+'|'?' )
#  JoinOperator ::= '$##'
#  StrOperator ::= '$#'
#  [ if Name is empty, the variable is anonymous and unable to be refered. ]
#
#  AfterPattern ::= ( NamedToken | TextToken )*
#  NamedToken ::= '$' Name ( ':' Type )?
#  TextToken ::= '\'' Text '\'' ( '#' BackReferenceId )? ':' Type
#
#  CommentBlock ::= '[*' .*? '*]'

use Tokenizer;
use BeginEnd;

my $pkg_name;
my $pkg_path;

BEGIN {
    ($pkg_path = $INC{__PACKAGE__ . ".pm"}) =~ s/[^\/]+$//;
    $pkg_path = "." if !$pkg_path;
}


my ($TYPE_ORG, $TYPE_SEQ, $TYPE_REP) = (0..2);

sub new_inst() {  # create instances
    my $self = shift;
    my $type = shift;
    $self = bless {} if (!ref($self));  # $self is Class
    $self->{type} = $type;
    $self->{rules} = "";
    $self->set_rules(@_) if (@_);
    return $self;
}

sub new() {  # set for applying sequencially
    my $self = shift;
    return $self->new_inst($TYPE_ORG, @_);
}

sub seq() {  # set for applying sequencially
    my $self = shift;
    return $self->new_inst($TYPE_SEQ, @_);
}

sub rep() {  # set for applying sequencially and repeating it.
    my $self = shift;
    return $self->new_inst($TYPE_REP, @_);
}

sub load() {
    my ($self, $rulefile) = @_;

    open(MAP, "<$rulefile") || die "can't open $rulefile.";
    $self->add_rules(join('', <MAP>));
    close(MAP);
    return $self;
}

sub expand_include() {
    # not support recursive inclusion.
    my ($t, $tn) = @_;
    if ((my $f) = ($t =~ /^PINCLUDE\s+<\@"(.+)">/)) {
	open(my $fd, "<", "$pkg_path/$f") || die "can't open $pkg_path/$f";
	$tn->set_input(join('', <$fd>));
	close($fd);
	return grep((! m/^(SP|UNIT_BEGIN|UNIT_END)\s/), $tn->tokens());
    }
    return ($t);
}

sub set_rules() {
    my $self = shift;
    return $self->add_rules(@_);
}

sub add_rules() {
    my $self = shift;
    $self->{rules} .= join("\n", @_)."\n";
    return $self;
}

sub build_meta_types() {    # evaluates special pattern tokens
    my $MT = shift;
    my @res;
    my $pname = "";
    foreach (@_) {
	if (m/^PNAME\s+<\@(.*)>$/) {
	    $pname = $1;
	    next;
	}
	if ($pname) {
	    next if (m/^TO\s/);
	    if ((my $t) = (m/^PVALUE\s+<"(.*)">$/)) {
		$t =~ s/(?<!\\)\@$pname\b/$MT->{$pname}/g;
		$MT->{$pname} = $t;
		$pname = "";
		next;
	    }
	}
	push(@res, $_);
    }


    foreach (keys %$MT) {
	1 while ($MT->{$_} =~ s/(?<!\\)\@(\w+)/$MT->{$1}/g);
	$MT->{$_} =~ s/\\\\/\\/g;
    }
#    die  join("", map("$_ -> $MT->{$_}\n", keys %$MT));
    return @res;
}

sub build_prog() {
    my $self = shift;
    my $MT = shift;

    my $is_left = 1;
    my $is_cur = 0;
    my @rep;
    my (@left, @right);
    my $is_rec;
    my $use_pkg = "";
    my $last_rule;
    my $rm_or_repl = 0;
    my $in_comment = 0;
    foreach (@_) {
	if (m/^([BE])_CMT/) {
	    $in_comment = $1 eq "B" ? 1 : 0;
	    print STDERR "CMT: $1, $in_comment\n";
	    next;
	}
	next if ($in_comment);

	if (m/^(?:BREAK|PRINT)/) {
#	    print STDERR "Last rule:\n$last_rule\n\n";
	    my $r = $last_rule;
	    $r =~ s/\\/\\\\/g;
	    push (@rep, qq(print 'Last rule:\n$r\n\n';));
	    push (@rep, qq(print "current buffer:\n\$_\n";));
	    push (@rep, qq(die 'break';)) if (m/^BREAK/);
	    next;
	}

	if ((my $call) = (m/^CALL\s+<\@\|(.*)\|>$/)) {
	    push(@rep, "\$_ = $call(\$_); \$c = 0;");
	    if ($call =~ /^(\w+)->/) {
		$use_pkg .= "use $1;\n";
	    }
	    next;
	}

	if (my ($label) = (m/NO_MATCH\s+<\@\:\w+:(\w+):>$/)) {
	    push(@rep, "goto $label if (!\$cl);\n");
	    next;
	}
	if (my ($label) = (m/LABEL\s+<\@\:\w+:(\w+):>$/)) {
	    push(@rep, "$label:\n");
	    next;
	}

	if ($is_left && m/^TO(R?)\s/) { # left TO right
	    $is_left = 0;
	    $is_rec = $1;
	    next;
	}
	if (!$is_left && m/^C_R\s/) { # out of right
	    if (0 && $self->{type} == $TYPE_SEQ) {  ## debug
		my $t = sprintf(qq(print STDERR qq(%s =>%s %s\\n);),
				join(" ", @left), ($is_rec? ">" : ""),
				join(" ", @right));;
		$t =~ s/\$/\\\$/g;
		push(@rep, $t);
	    }

	    $last_rule = ($rm_or_repl ?
			  &generate_rm_or_repl(\@left, \@right) :
			  &generate_pattern(\@left, \@right, $is_rec, $MT));
	    push(@rep, $last_rule);

	    if (0) { ## debug
		my $x = pop(@rep);
		my $t = sprintf(qq(print STDERR qq($x\n);));
		$t =~ s/([\$\\])/\\$1/g;
		push(@rep, $t, $x);
	    }
	    $is_left = 1;
	    @left = ();
	    @right = ();
	    $rm_or_repl = 0;
	    next;
	}
	next if (m/^(C_[LR])/); # skip { and }

	if ($is_left) {
	    $rm_or_repl = 1 if /^IN/;
	    push(@left, $_);
	} else {
	    push(@right, $_);
	}
    }

    if ($self->{type} == $TYPE_ORG) {
	@rep = map("$_ last if (\$cl);", @rep);
    }
    my $rep = join('', map("$_\n", @rep));

    my $template =
	qq($use_pkg sub(\$) {\$_ = shift; my (\$c,\$cl,\$ca); %s return \$_;});

    my $code;
    if ($self->{type} == $TYPE_ORG) {  # default
	$code = qq(do { \$c = 0; while (1) {\n$rep last; } } while (\$cl > 0););
    } elsif ($self->{type} == $TYPE_SEQ) {
	$code = $rep;
    } elsif ($self->{type} == $TYPE_REP) {
	$code = qq(do { \$ca = 0; $rep } while (\$ca > 0););
    } else {
	die "type error: $self->{type}";
    }
    return sprintf($template, $code);
}

sub build() {
    my $self = shift;

    my $tn = Tokenizer->new()->load("$pkg_path/rule-token.def");
    $tn->set_input($self->{rules});

    # remove comments and spaces
    my @tokens = grep( (! m/^(SP|UNIT_BEGIN|UNIT_END)\s/), $tn->tokens());

    @tokens = map( &expand_include($_, $tn), @tokens);

    # translation table of special token patterns
    my %META_TYPE;
    @tokens = &build_meta_types(\%META_TYPE, @tokens);

    $self->{prg} = $self->build_prog(\%META_TYPE, @tokens);
#    print "DEBUG: $self->{prg}\n";
    $self->{rewritep} = eval($self->{prg});

    return $self;
}

sub dump() {
    my $self = shift;
    $self->build() if (!$self->{prg});
    return $self->{prg};
}

sub rewrite() {
    my ($self, $tokens_text) = @_;
    # adding a dummy newline at the top of the token sequence as a sentinel.
    $tokens_text = "\n".$tokens_text;
    $self->build() if (!$self->{rewritep});
    $tokens_text = &{$self->{rewritep}}($tokens_text);
    $tokens_text =~ s/^\n//;
    return $tokens_text;
}

##########################################################################

my %_ID;

sub generate_pattern()
{
    my ($L, $R, $is_rec, $META_TYPE) = @_;
    my ($id_tbl, $lp) = &gen_left_pattern($L, $META_TYPE);
    my ($rp, $has_join, $has_str, @ids) = &gen_right_pattern($id_tbl, $R);

    my $ex = "";
    if (@ids) {
	$ex = "(?{".join("", map("\$_ID{\"$_\"}=\&gen_tmpl_id();", @ids))."})";
    }

    my $rep = "\$c = s/(?<=\\n)$lp$ex/$rp/g; \$cl += \$c;";
    if ($has_join) { # in the right pattern
	$rep .= q(s/>\n##JOIN\n\w+\s+(?:#\w+\s+)?<//g;);
    }
    if ($has_str) { # in the right pattern
	$rep .= q(s/(?<=\n)#STR\n\w+\s+(?:#\w+\s+)?<(.*?)>\n/LIS\t<"$1">\n/g;);
    }

    if ($is_rec) {
	$rep = qq(do { $rep } while (\$c > 0););
    }
    $rep = "\$cl = 0; $rep \$ca += \$cl;";

    return $rep;
}

my %join_ref;  # for JOIN operators.
my %lack_tail;  # for JOIN operators.

sub gen_left_pattern()
{
    my @ret;
    my $i = 0;
    my $id = {};
    my $tokens = shift;
    my $MT = shift;
    my $backref_id = 0;
    foreach (@$tokens) {
	my $pt = '';
	if (/^VAR_TYPE\s+<\$(\w*)(?:#(\w+))?:(\w+|\/(?:\\\/|[^\/])+\/)(\/.*\/)?>$/) {
	    my ($n, $s, $tp, $tx) = ($1, $2, $3, $4);
	    my $pn = "P$n";
	    if ($n && $id->{$pn}) {  # already used
		$pt = &gen_left_var_ref($n, $pn, $id, \@ret);
	    } elsif ($tp !~ /^\// && $MT->{$tp}) { # meta type
		my $mtp = $MT->{$tp};
		$backref_id++;
		$mtp =~ s/\(\?<#(\w+)>/(?<$1$backref_id>/g;
		$mtp =~ s/\\k<#(\w+)>/\\k<$1$backref_id>/g;
		$pt = sprintf("(?%s%s)", ($n ? "<$pn>" : ":"), $mtp);
		$id->{$pn} = "MT";
	    } else {
		if (!$tx) {
		    $tx = ".*";
		} elsif ($tx =~ s|^/(.*)/$|(?:$1)|) {
		    $tx = Tokenizer->unescape($tx);
		}
		if ($ret[-1] eq "##JOIN") {  # join with the last token.
		    pop(@ret); # ignore $ret[-1], i.e. '##JOIN'.
		    $pt = pop(@ret);
		    $id->{$pn} = "JN";
		    if ($pt =~ /^(?:\(\?|\\k)<(A\w+)>/) {
			$join_ref{$pn} = $1;
			$lack_tail{$1} = '>\n';
		    }
		    if ($pt =~ /^\(\?<A\w+>/) {
			# the token before JOIN is a new variable or identifier.
			$pt =~ s/>\\n(\)?)$/$1(?<T$pn>$tx)>\\n/;
		    } elsif ($pt =~ /^(\\k<A(\w+)>)\\k<B\w+>$/) {
			# the token before JOIN is a variable reference.
			$pt = "$1\\s+(?:#\\w+\\s+)?<\\k<T$2>(?<T$pn>$tx)>\\n";
		    } elsif ($pt =~ /^\\k<A\w+>/) {
			# the sequence begins a variable reference.
			$pt =~ s/>\\n$/(?<T$pn>$tx)>\\n/;
		    } else {
			print join("\n", @ret), "\n$pt\n";
			die "can't join \$$n to the previous variable.";
		    }
		} elsif ($ret[-1] eq "#STR") {
		    pop(@ret);
		    $pt = qq/(?<A$pn>LIS)\\s+<"(?<T$pn>$tx)">\\n/;
		    $id->{$pn} = "STR";
		} else {
		    if ($tp =~ s|^/(\S+)/$|(?:$1)|) {
			$tp = Tokenizer->unescape($tp);
		    }
		    $pt = &gen_left_var_pattern($n, $pn, $s, $tp, $tx, $id);
		}
	    }
	} elsif (/^VAR_REF\s+<\$(\w+)>$/) {
	    $pt = &gen_left_var_ref($1, "P$1", $id, \@ret);
	} elsif (/^TOKEN_TEXT\s+<'(.*)':\w+>$/) { # direct regular expression
	    $pt = $1; 	    # ignores type names
	} elsif (/^B_GRP\s+<\$?\[(\w*):>$/) {
	    my $pn = "P$1";
	    $pt = sprintf("(?%s(?|", ($1 ? "<$pn>" : ":"));
	    $id->{$pn} = "GP";
	} elsif (/^E_GRP\s+<\$?\]([\*\+]?[\?\+]?)>$/) {
	    $pt = ")$1)";
	} elsif (/^OR\s/) {
	    $pt = "|";
	} elsif (/^JOIN/) {
	    $pt = '##JOIN';
	} elsif (/^STR/) {
	    $pt = '#STR';
	} elsif (/^VAR_TEXT\s+<\$(\w*)(?:#(\w+))?:'(.*)'>$/) {
	    die "text variables are not going to be supported anymore: $_";
	    my ($n, $s, $t) = ($1, $2, $3);
	    $t =~ s/^\\\\'(.*)\\\\'$/'$1'/;
	    $t =~ s/\\'/'/g; # remove backslash for escaping single quote
	    $t =~ s/([.\[\]\*\+\(\)\/\?\|\$])/\\$1/g;
	    $pt = &gen_left_var_pattern($n, "P$n", $s, '\w+', $t, $id);
	} else {
	    die "RewriteTokens: Illegal token: $_\n" . join("\n", @$tokens);
	}
	push(@ret, $pt);
    }
    return ($id, join('', @ret));
}

sub gen_left_var_pattern()
{
    my ($n, $pn, $s, $tp, $tx, $id) = @_;
    my $pt_attr;
    if ($s) {
	my $s1 = "R$s";
	if ($id->{$s1}) { # id reference
	    $pt_attr = "\\k<$s1>\\s+";
	} else {
	    $pt_attr = "(?<$s1>\\#\\w+)\\s+";
	    $id->{$s1} = "R";
	}
    } else {
	$pt_attr = "(?:\\#\\w+\\s+)?";
    }

    if ($n) {
	$pt = "(?<A$pn>$tp)(?<B$pn>\\s+$pt_attr<(?<T$pn>$tx)>\\n)";
	$id->{$pn} = "AB";
    } else {
	$pt = "(?:$tp\\s+$pt_attr<$tx>\\n)";
    }
    return $pt;
}

sub gen_left_var_ref()
{
    my ($n, $pn, $id, $ret) = @_;
    my $pt;

    if ($ret->[-1] eq "#STR") {
	pop(@$ret);
	$pt = qq/LIS\\s+<"\\k<T$pn>">\\n/;
    } elsif ($ret->[-1] eq "##JOIN") {
	pop(@$ret);
	$pt = pop(@$ret);
	$id->{$pn} = "JN";
	if ($pt =~ /^(?:\(\?|\\k)<(A\w+)>/) {
	    $join_ref{$pn} = $1;
	    $lack_tail{$1} = '>\n';
	}
	if ($pt =~ /^\(\?<A\w+>/) {
	    # the token before JOIN is a new variable or identifier.
	    $pt =~ s/>\\n(\)?)$/$1\\k<T$pn>>\\n/;
	} elsif ($pt =~ /^\\k<A\w+>/) {
	    # the sequence begins a variable reference.
	    $pt =~ s/>\\n$/\\k<T$pn>>\\n/;
	} else {
	    die "can't join \$$n to the previous variable.";
	}

    } elsif ($id->{$pn} eq "MT") {
	$pt = "\\k<$pn>";
    } elsif ($id->{$pn} eq "AB") {
	$pt = "\\k<A$pn>\\k<B$pn>";
    } elsif ($id->{$pn} eq "JN") {
	$pt = "\\k<$join_ref{$pn}>\\s+<\\k<T$pn>>\\n";
    } elsif ($id->{$pn} eq "STR") {
	$pt = "ID\\w+\\t<\\k<T${pn}>>\\n";
    } else {
	die "Invalid variable: $n ($id->{$pn})";
    }
    return $pt;
}

sub gen_right_pattern()
{
    my ($id_tbl, $tokens) = @_;
    my @ret;
    my %ids = ();
    my $sp = 0;
    my $has_join = 0;
    my $has_str = 0;
    foreach (@$tokens) {
	if (m/^(?:VAR_REF|VAR_TYPE)\s+<\$(\w+):?(\w+)?>$/) {
	    my ($n, $r) = ($1, $2);
	    my $pn = "P$n";
	    my $v = $id_tbl->{$pn};
	    die "unknown variable: $n" unless ($v);
	    my $pt;
	    if ($v eq "AB") {
		$pt = ($r || "\$+{A$pn}")."\$+{B$pn}".($lack_tail{"A$pn"} ||"");
	    } elsif ($v eq "MT" || $v eq "GP" ) {
		$pt = "\$+{$pn}";
	    } elsif ($v eq "JN") { # joined token
		$pt = ($r || "\$+{$join_ref{$pn}}")."\\t<\$+{T$pn}>\\n";
	    } elsif ($v eq "STR") {
		$pt = ($r || "IDN")."\\t<\$+{T$pn}>\\n";
	    } else {
		die "Invalid variable: $n ($v)";
	    }
	    push(@ret, $pt);
	} elsif (/^TOKEN_TEXT\s+<'(.*)'(#\w+)?:(\w+)>$/) {
	    my ($t, $m, $a) = ($1, $2, $3);
	    $t =~ s|([\/\$])|\\$1|g;
	    if ($m) {
		$a .= " \$_ID{\"$m\"}";
		$ids{$m}++;
	    }
	    push(@ret, "$a\\t<$t>\\n");
	} elsif (/^JOIN/) {
	    push(@ret, "##JOIN\\n");
	    $has_join = 1;
	} elsif (/^STR/) {
	    push(@ret, "#STR\n");
	    $has_str = 1;
	} elsif (/^\w+\s+<(.*)>$/) { # これは何だっけ?
	    push(@ret, "\\$1\\n");
	}
    }

    return (join('', @ret), $has_join, $has_str, keys %ids);
}

sub gen_tmpl_id()
{
    return BeginEnd->gen_id();
}

##########################################################################
sub generate_rm_or_repl()
{
    my ($left, $right) = @_;

    my ($target, $in, $context) = @$left;
    die "illegal format: $target $in $context for IN style."
	if ($in !~  /^IN\b/);
    $target =~ s/^VAR_TYPE\s+<\$\w*:(.*)>$/$1/ || die "illegal target: $target";
    $target =~ s|^/(.*)/$|$1|;
    $context =~ s/^IDN\s+<(\w+)>$/$1/ || die "illegal context: $context";

    my $replace = shift @$right;
    if ($replace) {
	chomp $replace;
	$replace =~ s/^VAR_TYPE\s+<\$\w*:(\w+)>$/$1/
	    || die "illegal replace: $replace";
    }

    chomp ($target, $context, $replace);
    return sprintf(qq(\$_ = RewriteTokens->%s_tokens_in(
        qr/$target/, %sqr/$context/, \$_); \$c = 0;),
		   ($replace ? "replace" : "remove"),
		   ($replace ? "$replace, " : ""));
}


sub remove_tokens_in()
{
    my ($self, $target, $context, $code) = @_;

    my @code = split(/\n/, $code);
    my $in = 0;
    my @res = ();
    foreach (@code) {
	if (/^_?B_$context/) {
	    $in++;
	} elsif (/^_?E_$context/) {
	    $in--;
	} elsif ($in) {
	    next if (/^$target\s+.*$/)
	}
	push(@res, $_);
    }
    return join("\n", @res)."\n";
}

sub replace_tokens_in()
{
    my ($self, $target, $replace_type, $context, $code) = @_;

    my @code = split(/\n/, $code);
    my $in = 0;
    my @res = ();
    foreach (@code) {
	if (/^_?B_$context/) {
	    $in++;
	} elsif (/^_?E_$context/) {
	    $in--;
	} elsif ($in && /^$target(\s+.*)$/) {
	    $_ = "$replace_type$1";
	}
	push(@res, $_);
    }
    return join("\n", @res)."\n";
}

1;
