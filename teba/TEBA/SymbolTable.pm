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

package SymbolTable;

use strict;
use warnings;
no warnings 'recursion';

use JSON;
use Data::Dumper;

our %arith_type;
our %type_size;

my $LIB;

BEGIN {
    %type_size = (
	"void" => 0,
	"char" => 7,
	"unsigned.char" => 8,
	"short.int" => 15,
	"unsigned.short.int" => 16,
	"int" => 31,
	"unsigned.int" => 32,
	"long.int" => 63,
	"unsigned.long.int" => 64,
	"float" => 126,
	"double" => 127,
	"*" => 128,
	"#UNDEF" => 256,  # the largest
	);

    ($LIB = $INC{__PACKAGE__ . ".pm"}) =~ s/[^\/]+$//;

}

sub new {
    my $self = bless {};
    $self->{root} = { "#id" => "#UNDEF" };
    $self->{global} = { "#id" => "#GLOBAL", "#p" => $self->{root} };
    $self->{root}->{scopes} = [ $self->{global} ];
    return $self;
}

sub with_standard_global_table {
    my $self = shift;
    my $name = "global_symbol_table.json";
    open(my $f, '<', "$LIB/$name") || die "Can't open $name: $!";
    my $t = JSON->new->decode(join('', <$f>));
    close($f);
    $self->global_table($t);
    return $self;
}

sub global_table {
    my ($self, $g) = @_;  # $g must be a json format tree.
    # merge $g table to #GLOBAL.
    map($self->{global}->{$_} = $g->{$_}, keys %$g);
    return $self;
}

sub analyze {
    my ($self, $src_tree) = @_;
    &add_sym($src_tree, $self->{global});
}

sub root_tree {
    my $self = shift;
    &remove_p_link($self->{root});
    return $self->{root}
}

sub remove_p_link {
    my $el = shift;
    delete $el->{"#p"};
    map(&remove_p_link($_), @{$el->{scopes}});
}

############################################################################

sub is_scope {
    my $el = shift;
    return ($el->{t} =~ /^ST_(COMP|FOR)/ || $el->{t} eq "FUNC" | $el->{t} eq "DIRE_DEFINE");
}

sub add_sym {
    my ($el, $sym) = @_;
#    print "DEBUG add_sym: BID = $el->{id}, T = $el->{t}, id = $el->{id}\n";

    if (&is_scope($el)) {
	my $parent_sym = $sym;
	$sym = { '#id' => $el->{id}, '#p' => $parent_sym }; # a new symbol table
	push(@{$parent_sym->{scopes}}, $sym);
    }

    if ($el->{t} eq "DE") {  # declaration
	&mark_decl_ident($el, $sym);
	&restruct_tag_tree($sym);
    } elsif ($el->{t} eq "TD") {  # typedef
	&mark_decl_ident($el, $sym, "type:");
	&restruct_tag_tree($sym);
    } elsif ($el->{t} eq "FUNC") { # function name
	my @tp = map("TYPE\t<$_>", @{$el->{type}});
	&mark_and_regist(&child($el, "name"), $sym->{'#p'}, "", \@tp)
	    if (exists $el->{name});
    } elsif ($el->{t} =~ /^ID_(VF|MC)$/) {
	&mark_ident($el, &lookup_sym($el->{name}, $sym))
	    unless &is_marked($el);
    } elsif ($el->{t} eq "LIN") {
	# no need to be registed to the symbol table
	my ($tail) = ($el->{value} =~ /([uUlLfF]+)$/);
	$tail |= "";
	my @tp;
	push(@tp, "unsigned") if ($tail =~ /[uU]/);
	push(@tp, "long") if ($tail=~ /[lL]/);
	if ($el->{value} =~ /\./) {
	    push(@tp, ($tail =~ /fF/) ? "float" : "double");
	} else {
	    push(@tp, "int");
	}
	$el->{stype} = join(".", @tp);
    } elsif ($el->{t} eq "LIC") {
	# no need to be registed to the symbol table
	$el->{stype} = "char";
    } elsif ($el->{t} eq "LIS") {
	# no need to be registed to the symbol table
	$el->{stype} = "char.*";
    } elsif ($el->{t} eq "ST_LABELED") {
	my $label = &child_at($el, $el->{label});
	if (!&isObj($label) && $label =~ /^ID_LB\s+<(\w+)>$/) {
	    $sym->{"label:$1"} = 1;
	}
	# todo: goto statement should have a reference of label.
    }

    foreach (&children($el)) {
	next if $_->{t} eq "SCT";
	&add_sym($_, $sym);
    }
    &calc_stype($el, $sym) if $el->{t} eq "P";

    if ($el->{t} eq "DIRE_DEFINE") {
	my $mc = &child_at($el, $el->{mc});
	my $type = [];
	if (exists $el->{def}) {
	    my $mcb = &child_at($el, $el->{def});
	    my $p = &child_at($mcb, 0);
	    push(@$type, map("TYPE <$_>", split(/\./, $p->{stype})))
		if (&isObj($p) && exists $p->{stype} && $p->{stype});
	    # in the case of "#define X ({ ... })", $p will be empty.
	}
	&mark_and_regist($el, $sym->{'#p'}, "", $type);
    }
}

sub mark_decl_ident {
    my ($el, $sym, $prefix) = @_;
#    print "DEBUG: mark_decl_ident: $el->{id}, ", $sym->{'#id'}, "\n";
    $prefix ||= "";
    my @tp = ();
    my @storage = ();
    my @qual = ();
    foreach (&elms($el)) {
	if (&isObj($_)) {
	    if ($_->{t} eq "SCT") {
		push(@tp, &parse_struct($_, $sym));
	    } elsif ($_->{t} eq "EN") {
		push(@tp, &parse_enum($_, $sym));
	    } elsif ($_->{t} =~ /^(ID|P)/) {
		&mark_and_regist($_, $sym, $prefix, \@tp, \@storage, \@qual);
	    } # ignore the others, which are illgeal.
	} elsif (/^ID_TPCS/) {
	    push(@storage, $_);
	} elsif (/^ID_TPQ/) {
	    push(@qual, $_);
	} elsif (/^ID_TP/) {
	    push(@tp, $_);
	}
    }
}

sub mark_and_regist {
    my ($el, $sym, $prefix, $tp, $storage, $qual) = @_;
    my ($ident, @mod) = &find_most_inner_left($el);
    print STDERR Dumper($el, $ident) unless $ident;
    my $type = &type_str(@$tp, @mod) || "#UNDEF";

    print STDERR Dumper($el, $ident) unless &elm_at($ident, 0);

    if (&elm_at($ident, 0) =~ m/<(\S+)>$/) {
	$sym->{$prefix.$1} = $type;
    }
    &mark_ident($ident, $sym, $type);
    $ident->{storage} = &type_str(@$storage) if ($storage && @$storage);
    $ident->{qual} = &type_str(@$qual) if ($qual && @$qual);
}

sub mark_ident {
    my ($el, $sym, $type) = @_;
    $el->{scope} = ($sym->{'#id'} =~ /^\d/) ? sprintf("#%04d", $sym->{'#id'})
	: $sym->{'#id'};

    $el->{e}->[0] =~ s/^(ID_\w+)/$1 $el->{scope}/;
    $el->{stype} = &type_resolve($type, $sym);
}

sub is_marked {
    my $el = shift;
    return exists $el->{scope};
}

sub find_most_inner_left {
    my ($el, $is_target) = @_;
    my $ch;
    my @tp = ();

    if ($is_target && $is_target->($el)) {
	return ($el);
    }

    foreach (&elms($el)) {
	if (&isObj($_)) {
	    $ch = $_ unless $ch;
	} elsif (/^(A_L|OP_U)/) {
	    push(@tp, $_);
	}
    }
    if ($ch) {
	my ($in_el, @in_tp) = &find_most_inner_left($ch, $is_target);
	$el = $in_el;
	push(@tp, @in_tp);
    }
    return ($el, @tp);
}

sub lookup_sym {
    my ($ident, $sym) = @_;
    while ($sym->{'#p'}) {
	return ($sym, $sym->{$ident}) if exists $sym->{$ident};
	$sym = $sym->{'#p'};
    }
    return ($sym, $sym->{$ident} = "#UNDEF");
}

sub type_resolve {
    my ($type, $sym, $tested, $tested_size) = @_;
    $tested ||= { };
    $tested_size ||= 0;
    my @tp;
    foreach (split(/\./, $type)) {
	if (/^(void|int|char|double|float|long|short|(?:un)?signed|#UNDEF)$/
	    || /\W/) {
	    push(@tp, $_);
	} else {
	    if (exists $tested->{$_}) {
		if ($tested->{$_}->[0] ne "#UNDEF") {
		    my @t = sort { $tested->{$a}->[1] cmp $tested->{$b}->[1] }
		    keys %$tested;
#		    print STDERR "Warning: Found recursivly defined typedef-ed types:", join("->", @t, $_), "\n";
		    return "#UNDEF";
		} else {
		    return $_;
		}
	    }
	    my ($s, $tp) = &lookup_sym("type:$_", $sym);
	    $tested->{$_} = [$tp, ++$tested_size];
	    $tp = $_ if $tp eq "#UNDEF";
	    push(@tp, split(/\./, &type_resolve($tp, $s, $tested, $tested_size)));
	}
    }
    return join(".", @tp);
}

sub parse_fr {
    my $fr = shift;
    my ($name, @el) = &elms($fr);
    my @args = ();
    my @tp;
    my $arg;
    foreach (&elms($fr)) {
	if (&isObj($_)) {
	    $arg = $_;
	}elsif (/^ID_TP/) {
	    push(@tp, $_);
	} elsif (/^CA/) {  #comma
	    push(@args, { 't' => [ @tp ], 'a' => $arg });
#	    print "DEBUG: t:", type_str(@tp), " a: ", $arg->{id}, "\n";
	    @tp = ();
	}
    }
    if (@tp) {
	push(@args, { 't' => [ @tp ], 'a' => $arg });
    }
    return ($name, @args);
}

my $tag_num;
sub new_tag {
    return sprintf("%04d", ++$tag_num);
}

sub Xparse_struct {
    my ($el, $sym) = @_;
    my $tag; my $re;
    foreach (&elms($el)) {
       if (&isObj($_)) {  # member declaration
           my $id;
           if ($tag && $sym->{"tag:$tag"}) {
               $id = $sym->{"tag:$tag"}->{"#id"};
           } else {
               $id = &new_tag;
           }
           $tag ||= $id;
           $sym->{"tag:$tag"} ||= { "#id" => $id };
           &mark_decl_ident($_, $sym->{"tag:$tag"});
       } elsif (/^ID_TAG\s+(?:#\w+\s+)?<(\w+)>$/) { # struct tag
           $tag = $1;
       } elsif (/RE_SUE\s+(?:#\w+\s+)?<(\w+)>$/) {
           $re = $1;
       }
    }
    $el->{scope} = $sym->{"#id"};
    return "TYPE <$re $tag>";
}

sub parse_struct {
    my ($el, $sym) = @_;
    my ($re, $tag, @member) = &parse_sue($el, $sym);

#    print STDERR Dumper($el) unless (defined $re && defined $tag);
    $tag ||= "#UNDEF";
    foreach (@member) {
	&mark_decl_ident($_, $sym->{"tag:$tag"});
    }
    return "TYPE <$re $tag>";
}

sub parse_enum {
    my ($el, $sym) = @_;
    my ($re, $tag, @member) = &parse_sue($el, $sym);

    $tag ||= "#UNDEF";
    foreach (@member) {
	&mark_and_regist($_, $sym->{"tag:$tag"}, "", ["TYPE <$re $tag>"]);
	&mark_and_regist($_, $sym, "", ["TYPE <$re $tag>"]);
    }
    return "TYPE <$re $tag>";
}

sub parse_sue {
    my ($el, $sym) = @_;
    my $tag; my $re;
    my @member;
    foreach (&elms($el)) {
	if (&isObj($_)) {  # member declaration
	    push(@member, $_);
	} elsif (/^ID_TAG\s+(?:#\w+\s+)?<(\S+)>$/) { # struct tag
	    # A struct tag in FreeBSD has a charactor $ in the tag name.
	    $tag = $1;
	} elsif (/RE_SUE\s+(?:#\w+\s+)?<(\w+)>$/) {
	    $re = $1;
	}
    }
    if (@member) {
	my $id = ($tag && $sym->{"tag:$tag"}) ?
	    $sym->{"tag:$tag"}->{"#id"} : &new_tag;
	$tag ||= $id;
	$sym->{"tag:$tag"} ||= { "#id" => $id };
    }
    $el->{scope} = $sym->{"#id"};
    return ($re, $tag, @member);
}


sub restruct_tag_tree {
    my $sym = shift;
    my @tags;
    foreach (keys %$sym) {
	&extract_tag_def($sym->{$_}, $sym) if /^tag:/;
    }
#    print "DEBUG: after restructed sym: ", Dumper($sym), "\n";
}

sub extract_tag_def {
    my ($tag, $sym) = @_;
    my @tags = grep(/^tag:/, keys %$tag);
    foreach (@tags) {
	&extract_tag_def($tag->{$_}, $sym);
	$sym->{$_} = $tag->{$_};
	delete $tag->{$_};
    }
}

sub calc_stype {
    my ($el, $sym) = @_;


    if (@{$el->{e}} == 0) { # empty expression
	$el->{stype} = "#UNDEF";
    } elsif (exists $el->{call}) { # function call
	my $fname = &child($el, "call");
	$el->{stype} = $fname->{stype} || "#UNDEF"
	# don't take care of arguments.
    } elsif (!exists $el->{sym}) {  # illegal expression
	$el->{stype} = "#UNDEF";
    } elsif ($el->{sym} =~ /^_([-+&*\/\%\|^]|<<|>>)?=_$/) {
	my ($lhs, $rhs) = &children($el,"operand");
	if (exists $lhs->{stype} && $lhs->{stype} eq "#UNDEF"
	    && exists $rhs->{stype} && $rhs->{stype} ne "#UNDEF") {
	    # initializer of array is not P expr and $rhs has no 'stype'.
	    # type inference: LHS should be same with RHS.
	    $lhs->{stype} = $rhs->{stype}
	    # RHS may not be same with LHS when using implicit type casting.
	}
	$el->{stype} = $lhs->{stype};
    } elsif ($el->{sym} =~ m!^_[-+*/%]_$!) { # arithmetic
	my @oprd_t = map($_->{stype}||"#UNDEF", &children($el, "operand"));
	$el->{stype} = &calc_arith_type(@oprd_t, $el->{sym});
    } elsif ($el->{sym} =~ m/^_([&\|^]|<<|>>)_$/) { # bit operator
	# type inference: operands shoud be int
	$el->{stype} = "int";
    } elsif ($el->{sym} =~ m/^_([<>]=?|[=!]=|&&|\|\|)_$/) { # logical operator
	# type inference: operands shoud be int
	$el->{stype} = "int";
    } elsif ($el->{sym} =~ m/^[-+~!]_$/ || $el->{sym} eq "(_)") {
	$el->{stype} = &child_at($el, 0, "operand")->{stype} || "#UNDEF";
    } elsif ($el->{sym} =~ /^((--|\+\+)_|_(--|\+\+))$/) {
	$el->{stype} = &child_at($el, 0, "operand")->{stype} || "#UNDEF";
    } elsif ($el->{sym} eq "*_") {
	# type inference operand should be "UNDEF.*" if it was UNDEF.
	my $t = &child_at($el, 0, "operand")->{stype} || "#UNDEF";
	$el->{stype} = &pref($t);
    } elsif ($el->{sym} eq "&_") {
	my $t = &child_at($el, 0, "operand")->{stype} || "#UNDEF";
	$el->{stype} = $t. ".*";
    } elsif ($el->{sym} =~ /^_\[_?\]$/) {
	my @oprd_t = map($_->{stype}||"#UNDEF", &children($el, "operand"));
	push(@oprd_t, "int") if (@oprd_t == 1);  # no index such as "int a[];"
	my $t = &calc_arith_type(@oprd_t, $el->{sym});
	$el->{stype} = &pref($t);
	# type inference: one of the operands is int.
    } elsif ($el->{sym} eq "_?_:_") {
	my $t1 = &child_at($el, 1, "operand")->{stype} || "#UNDEF";
	my $t2 = &child_at($el, 2, "operand")->{stype} || "#UNDEF";
	$t1 = $t2 if &cmp_type_size($t1, $t2);
	$el->{stype} = $t1;
    } elsif ($el->{sym} =~ m/^_(\.|->)_/) {
	my $op = $1;
	my $st = &child_at($el, 0, "operand")->{stype} || "#UNDEF";
	my $mem = &child_at($el, 1, "operand");
	$st = &pref($st) if ($op eq "->");

	$el->{stype} = "#UNDEF";
	if ($st =~ s/^(struct|union)\s+/tag:/) {
	    my ($s, $tag) = &lookup_sym($st, $sym);
	    if (&isObj($tag) && $tag->{$mem->{name}}) {
		$el->{stype} = $mem->{stype} = $tag->{$mem->{name}};
		$mem->{tag} = $tag->{"#id"};
	    }
	}
    } elsif ($el->{sym} eq "T_") {
	my $cast = &child($el, "op");
	my @tp;
	foreach (&elms($cast)) {
	    if (&isObj($_)) {
		if ($_->{t} eq "SCT") {
		    push(@tp, &parse_struct($_, $sym));
		} else {
		    # complex cast: (struct *(*)(void *))x
		    @tp = ("#UNDEF");
		    last; # give up. sorry.
		}
	    }
	    push(@tp, $_) if (/^(?:ID_TP|OP_U)/);
	}
	$el->{stype} = &type_str(@tp);
    } elsif ($el->{sym} eq "sizeof_") {
	$el->{stype} = &type_resolve("size_t", $sym);
    } elsif ($el->{sym} =~ /^[,_]+$/) { # comma operators
	my $last_one = $el->{operand}->[-1];
	$el->{stype} = &child_at($el, $last_one)->{stype} || "#UNDEF";
    } elsif ($el->{sym} eq "defined_") {
	$el->{stype} = "int";
    } elsif ($el->{sym} eq "._") { # C99, not supported yet.
	$el->{stype} = "#UNDEF";
    } else {  # illegal expressions
	$el->{stype} = "#UNDEF";
#	print STDERR "Warning: Not supported yet:", Dumper($sym, $el),
#	    "Please contanct to the author.\n";
    }
}

sub cmp_type_size {
    my ($t1, $t2) = @_;
    return defined $t1 && defined $t2
	&& exists $type_size{$t1} && exists $type_size{$t2}
    && $type_size{$t1} < $type_size{$t2};
}

sub calc_arith_type {
    my ($t_la, $t_sm, $op) = @_;

    my $enum = $t_la  if $t_la =~ /^enum/;
    $enum = $t_sm  if $t_sm =~ /^enum/;
    return $enum if $enum;

    $t_la =~ s/^.*\.[\*\[]$/\*/; # pointer type
    $t_sm =~ s/^.*\.[\*\[]$/\*/;
    my ($larger, $smaller) = @_;
    if (&cmp_type_size($t_la, $t_sm)) {
	($t_sm, $t_la) = ($t_la, $t_sm);
	($smaller, $larger) = @_;
    }
    if ($t_la eq "*") {
	return "#UNDEF" if ($t_sm eq "double"); # a compile error happens.
	if ($t_sm eq "*") { # a subtraction of pointers is valid.
	    return $op eq "_-_" ? "int" : "#UNDEF";
	}
	return $larger if ($op =~ /^(_[-\+]_|_\[_\])$/); # add or subtract an int value.
	return "#UNDEF";
    } elsif ($t_sm eq "*") { 	# $t_la is #UNDEF, which may be really int.
	return $smaller;
    }
    return $larger;
}

sub type_str {
    my $s = join(".", map(m/^\w+\s+(?:\S+\s+)?<(.+)>$/, @_));
    $s =~ s/(unsigned|long|short)((\.\W)*)$/$1.int$2/;
    return $s;
}

sub pref {
    my $st = shift;
    unless ($st =~ s/\.[\[\*]$//) {
	$st = "#UNDEF";
    }
    return $st;
}


###################################################################
sub children {
    # if $attr is specified, returns the objects referred by $attr.
    # Otherwise returns all objects.
    my ($elem, $attr) = @_;
    my @ch;
    if ($attr) {
	unless (exists $elem->{$attr}) {
	    die "No attribute '$attr' exists in obj #$elem->{id}\n"
		. Dumper($elem);
	}
	if (ref($elem->{$attr}) eq "ARRAY") {
	    @ch = @{$elem->{$attr}};
	} else {  # as SCALAR
	    die "$attr is not a attribute for child index."
		unless &is_numeric($elem->{$attr});
	    @ch = ($elem->{$attr});
	}
	@ch = map(&elm_at($elem, $_), @ch);
    } else { # all children
	@ch = grep(&isObj($_), @{$elem->{e}});
    }
    return @ch;
}

sub child {
    my ($self, $attr) = @_;
    die "Illegal attribute for child." if (ref($self->{$attr}) eq "ARRAY");
    die "$attr is not a attribute for child index."
	unless &is_numeric($self->{$attr});
    return &child_at($self, $self->{$attr});
}

sub child_at {
    my ($self, $i, $attr) = @_;
    if ($attr) {
	return &elm_at($self, $self->{$attr}->[$i]);
    } else {
	return &elm_at($self, $i);
    }
}

sub elm_at() {
    my ($self, $i) = @_;
    return $self->{e}->[$i];
}

sub elms {
    return @{$_[0]->{e}};
}

###################################################################

sub isObj {
    return ref($_[0]) eq "HASH";
}

sub is_numeric() {
    return ($_[0] ^ $_[0]) eq '0';
    # XOR returns 0 for numeric and NUL for string.
}

sub tokenize {
# the orignal is a copy from TEBA2JSON.pm
    shift if (ref($_[0]) eq "");
    my $el = shift;
    my @ch = &elms($el);
    my $be; my $en;
    if ($el->{t} eq "UNIT") {
	$be = "UNIT_BEGIN\t<>";
	$en = "UNIT_END\t<>";
    } else {
	my $bid = sprintf("#%04d", $el->{id});
	$be = "B_$el->{t} $bid\t<>";
	$en = "E_$el->{t} $bid\t<>";
	if ($el->{stype}) {
	    push(@ch, "SP_TYPE \t<`$el->{stype}`>");
	}
    }
    return ($be, map(&isObj($_) ? &tokenize($_) : $_, @ch), $en);
}

1;

