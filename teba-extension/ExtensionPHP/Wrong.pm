package Wrong;

use strict;
use warnings;

use Tokenizer;
use RewriteTokens;
use BracketsID;

use PEBA2JSON;

use FindBin qw($Bin);
my $PHParse = "$Bin/../../teba/TEBA/PHParse";

my $LIB;

BEGIN {
    ($LIB = $INC{__PACKAGE__ . ".pm"}) =~ s/[^\/]+$//;
    unshift(@INC, "");
}

sub new {
    my $self = bless {};
    $self->{token_definitions} = &read_file("token.def");
    # &insert_token_def($self, &read_file_add("python.def"));
    return $self;
}

sub parse {
    my ($self, $src) = @_;

    my $tb = '<\?(?:php|=)?';
    my $te = '\?>';

    my $tk = Tokenizer->new()->set_def($self->{token_definitions});

    my @tokens = ();

    my $code;
    if ($self->{REQUIRE_PHP_TAG}) {
	while ($src) {
	    my $matched = 0;
	    if ($src =~ s/^(.*?)($tb)//s) {
		push(@tokens, &html_code($1), &tag_token($2));
		$matched++;
	    }
	    if ($src =~ s/^(.*?)($te\n?)//s
		|| $matched && $src =~ s/^(.*)$//s) {
		# if the file is ended without $te
		push(@tokens, $tk->set_input($1)->tokens());
		push(@tokens, &tag_token($2)) if ($2);
		$matched++;
	    }
	    if (!$matched && $src =~ s/^(.*)$//s) {
		push(@tokens, &html_code($1));
	    }
	}

	$code = join("", ("B_FILE\t<>\n",
			  grep(!/^UNIT/, @tokens), "E_FILE\t<>\n" ));

    } else {
	$code = $tk->parse($src);
    }
    $code =  &vars_in_string($code, $tk);

    $code = BracketsID->new()->conv($code);

    $code = RewriteTokens->seq()->set_rules(&load_rules("expr"))
	->rewrite($code);
    $code = RewriteTokens->rep()->set_rules(&load_rules("expr-op"))
	->rewrite($code);
    $code = RewriteTokens->seq()->set_rules(&load_rules("expr-final"))
	->rewrite($code);

    $code = RewriteTokens->seq()->set_rules(&load_rules("colon-stmt"))
	->rewrite($code);

    $code = RewriteTokens->seq()->set_rules(&load_rules("stmt"))
	->rewrite($code);
    $code = RewriteTokens->rep()->set_rules(&load_rules("stmt-if"))
	->rewrite($code);
    $code = RewriteTokens->seq()->set_rules(&load_rules("stmt-final"))
	->rewrite($code);
    unless ($self->{JSON}) {
	return $code;
    } else {
	return PEBA2JSON->new(\$code)->json()->str();
    }
}

sub require_php_tag {
    my $self = shift;
    $self->{REQUIRE_PHP_TAG} = 1;
    return $self;
}

sub as_json {
    my $self = shift;
    $self->{JSON} = 1;
    return $self;
}

###########################################################################

sub html_code() {
    my $str = shift;
    $str =~ s/\n/\\n/g;
    return "HTML <$str>\n";
}

sub tag_token() {
    my $str = shift;
    $str =~ s/\n/\\n/g;
    return "SP_TAG <$str>\n";
}

sub vars_in_string() {
    my ($code, $tk) = @_;
    my @out;
    foreach (split(/\n/, $code)) {
	if (my ($s) = /^LIS\s+<(.*)>$/) {
	    if ($s =~ s/(\$(?:{\w+[^}]*}|\w+(?:\[[^\]]*\]|->\w+)?))/\n$1\n/g) {
		push(@out, "B_LIS\t<>\n",
		     map(/^\$/ ? grep(!/^UNIT/, $tk->set_input($_)->tokens())
			       : "LIS\t<$_>\n", split(/\n/, $s)),
		     "E_LIS\t<>\n");
		next;
	    }
	}
	push(@out, "$_\n")
    }
    return join("", @out);
}

# 変更追加箇所 開始 ------------------------------------------------------------------------

# parse用 開始 =============================================================================
sub read_file() {
    my $name = shift;
    open(my $f, '<', "$PHParse/$name") || die "Can't open $name: $!";
    my $t = join('', <$f>);
    close($f);
    return $t;
}

sub insert_token_def() {
    my ($self, $def) = @_;
    $def = read_file_add();
    $self->{token_definitions} = $def . "\n" . $self->{token_definitions};
    return $self;
}

sub load_rules() {
    my $f = shift;
    my $fname = "$PHParse/${f}.rules";
    my $common_def = "$PHParse/common.rules";

    open(my $co, '<', $common_def) || die "can't open $common_def";
    my $def = join('', <$co>);
    close($co);
    open(my $fp, '<', $fname) || die "can't open $fname";
    my $rules = join('', <$fp>);
    close($fp);
    return $def.$rules;
}

# parse用 終了 =============================================================================

# 拡張用 開始 ===============================================================================


# 今回の解析用
sub load_def() {
    my $language = shift;
    my $fname = "$LIB/$language.def";

    open(my $fp, '<', $fname) || die "can't open $fname";
    my $def = join('', <$fp>);
    close($fp);
    return $def;
}



# 拡張用
sub read_file_add2() {
    my $lang = shift;
    open(my $f, '<', "$LIB/$lang/$lang.def") || die "Can't open $lang.def: $!";
    my $t = join('', <$f>);
    close($f);
    return $t;
}

# 拡張用
sub read_file_add() {
    open(my $f, '<', "$LIB/wrong.def") || die "Can't open wrong.def: $!";
    my $t = join('', <$f>);
    close($f);
    return $t;
}
# 拡張用 終了 ===============================================================================

# 変更追加箇所 終了 ------------------------------------------------------------------------
1;
