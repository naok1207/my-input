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

package FixCma;

sub new() {
    my $self = {};
    bless $self;
    return $self;
}

sub conv()
{
    my ($self, $text) = @_;
    my @id = ();
    my @code = split(/\n/, $text);
    foreach (@code) {
	next if (s/^CA\s+(?:(\#\w+)\s+)?(<.*>)$/CA $id[-1]\t$2/);
	if (/^\w+\s+(\#\w+)\s+/) {
	    if ($id[-1] ne $1) {
		push(@id, $1);
	    } else {
		pop(@id);
	    }
	}
    }
    return join("\n", @code);
}

1;
