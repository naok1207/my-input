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

package BeginEnd;

my $BEID = 0;

sub new() {
    $BEID = 0;
    my $self = {};
    return bless $self;
}

sub conv() {
    my ($self, $text) = @_;

    my @code = split(/\n/, $text);
    foreach (@code) {
	if (/^(_?B_\w+)(?:\s+#\w+)?\s+<(.*?)>$/) {
	    my $id = &gen_id();
	    $_ = "$1 $id\t<$2>";
	    push(@begin, $id);
	} elsif (/^(_?E_\w+)(?:\s+#\w+)?\s+<(.*?)>$/) {
	    my $id = pop(@begin);
	    $_ = "$1 $id\t<$2>";
	}
    }
    return join("\n", @code)."\n";
}

sub gen_id() {
    return sprintf("#E%04d", ++$BEID);
}

sub conv_p() { # preserve id as possible.
    my ($self, $text) = @_;
    my @out = ();
    my $max = 0;
    foreach (split(/\n/, $text)) {
	if (/^B_\w+\s+#E(\w+)?\s+<.*?>$/) {
	    $max = $1 if $max < $1;
	}
    }
    $self->{BEID} = $max;
    foreach (split(/\n/, $text)) {
	if (/^(_?B_\w+)(?:\s+(#\w+))?\s+<(.*?)>$/) {
	    $id = ($2 ? $2 : sprintf("#E%04d", ++$self->{BEID}));
	    push(@out, sprintf("%s %s\t<%s>\n", $1, $id, $3));
	    push(@begin, $id);
	} elsif (/^(_?E_\w+)(\s+#\w+)?\s+<(.*?)>$/) {
	    my $id = pop(@begin);
	    push(@out, sprintf("%s %s\t<%s>\n", $1, $id, $3));
	} else {
	    push(@out, "$_\n");
	}
    }
    return join('', @out);
}

1;
