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

package Tokenizer;

sub new {
    my $self = {};
    bless $self;
    return $self;
}

sub load()
{
    my ($self, $file) = @_;

    ## read token definition
    open(DEF, "<$file") || die "can't load token definition: $file";
    my $def = join('', <DEF>);
    close(DEF);

    return $self->set_def($def);
}

sub set_def()
{
    my ($self, $def) = @_;

    my @def = split("\n", $def);

    ## add special rule.
    push(@def, qq(UNKNOWN /./));
    ## If no defined rules match tokens, the first character is
    ## to be cooked for preventing infinit loops.

    ## making rule sets. ($tp is a global variable.)
    my @pt;
    foreach (@def) {
	if (/^(\w+)\s+\S(.*)\S$/) {
	    push(@pt, qq((?:(?:$2)(?{\$tp = "$1"}))));
	}
    }
    my $pts = join('|', @pt);

    $self->{prg} = qq(
sub (\$) {
    my \$self = shift;
    my \@ret = ();
    my \$in = \$self->{input};
    my \$c = 0;

    push(\@ret, "UNIT_BEGIN\\t<>\\n");
    while (\$in =~ m/($pts)/sg) {
          push(\@ret, "\$tp\\t<".(Tokenizer->escape(\$1)).">\\n");
    }
    push(\@ret, "UNIT_END\\t<>\\n");
    return \@ret;
};
);

    $self->{parser} = eval($self->{prg});
#    print $self->{prg};
    return $self;
}

sub escape() {
    my ($self, $tk) = @_;
    $tk =~ s/\\/\\\\/g;
    $tk =~ s/\n/\\n/g;
    $tk =~ s/\t/\\t/g;
    return $tk;
}

sub parse()
{
    my ($self, $text) = @_;
    $self->set_input($text);
    return join('',  $self->tokens());
}

sub tokens() {
    my $self = shift;
    return &{$self->{parser}}($self);
}

sub dump() {
    my $self = shift;
    return $self->{prg};
}

sub text() {
    my $self = shift;
    return $self->{input};
}

sub is_empty() {
    my $self = shift;
    return $self->{input} eq "";
}

sub set_input() {
    my ($self, $t) = @_;
    $self->{input} = $t;
    return $self;
}

sub unescape() {
    my ($self, $s) = @_;
    my @r;
    while ($s ne "") {
#	if ($s =~ s/^[^\\]+//) { push(@r, $&); }
	if ($s =~ s/(^[^\\]+)//) { push(@r, $1); }
	if ($s =~ s/^\\n//) { push(@r, "\n"); next; }
	if ($s =~ s/^\\t//) { push(@r, "\t"); next; }
	if ($s =~ s/^\\(.)//) { push(@r, $1); }
    }
    return join('', @r);
}

sub join_tokens() {
    my $self = shift;
    my @res;
    foreach (@_) {
	my @t = map { s/^\w+\s+(?:#\w+\s+)?<(.*)>$/$1/; &unescape(0, $_); }
                split("\n");
	push(@res, join("", @t));
    }
    return (@res == 1) ? $res[0] : @res;
}

1;
