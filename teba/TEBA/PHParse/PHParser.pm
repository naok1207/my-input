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

package PHParser;

use strict;
use warnings;

my $LIB;

BEGIN {
    ($LIB = $INC{__PACKAGE__ . ".pm"}) =~ s/[^\/]+$//;
    unshift(@INC, "$LIB/..");
}

use Tokenizer;
use RewriteTokens;
use BracketsID;

use PEBA2JSON;

sub new {
    my $self = bless {};
    return $self;
}

sub parse {
    my ($self, $src) = @_;

    my $tb = '<\?(?:php|=)?';
    my $te = '\?>';

    my $tk = Tokenizer->new()->load("$LIB/token.def");

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

sub load_rules() {
    my $f = shift;
    my $fname = "$LIB/${f}.rules";
    my $common_def = "$LIB/common.rules";

    open(my $co, '<', $common_def) || die "can't open $common_def";
    my $def = join('', <$co>);
    close($co);
    open(my $fp, '<', $fname) || die "can't open $fname";
    my $rules = join('', <$fp>);
    close($fp);
    return $def.$rules;
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

1;
