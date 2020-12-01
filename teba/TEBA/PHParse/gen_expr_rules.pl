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

#!/usr/bin/perl

use strict;
use warnings;

# Operator Precedence for PHP
# 00 left: \  #defined in expr.rules

# 01 none: clone, new, RE_PAT(static, const, ...)
# 02 left: [
#    left: ->
# 03 right: **
# 04 right: ++ -- ~ (int) (float) (string) (array) (object) (bool) @
# 05 none: instanceof
# 06 right: !
# 07 left: * / %
# 08 left: + - .
# 09 left: << >>
# 10 none: < <= > >=
# 11 none: == != === !== <> <=>

# 12 left: &
# 13 left: ^
# 14 left: |
# 15 left: &&
# 16 left: ||
# 17 right: ??
# 18 left: ?:
# 19 right: = += -= *= **= /= .= %= &= |= ^= <<= >>= ??=
# 20 left: and
# 21 left: xor
# 22 left: or


# 23 left: =>

# 24 right: ...

# 25 left: as
# 26 left: insteadof

# 27 left: comma

# ul => unary left
# ur => unary right
# bin => binary
my @op = (
#    ["left", "bin",  '\\\\\\\\'],
    ["right", "ul",  '\$'],
    ["none",  "ul",  '(?:clone|new)'],
    ["PAT",  "ul",  'RE_PAT'],  ## static, const, ...
    ["PAT",  "ul",  'ID_TP'],  ## types
    ["PAT",  "ul",  'RE_F'],  ## function
    ["array", "ur",  '\['],
    ["left",  "bin", '(?:->|::)'],
    ["right", "bin", '\*\*'],
    ["right", "ul",  '(?:\+\+|--|[~@])'],
    ["right", "cast",  ''],
    ["right", "ur",  '(?:\+\+|--)'],
    ["none",  "bin",  'instanceof'],
    ["right", "ul",  '!'],
    ["left",  "bin", '[*\/%]'],
    ["left",  "binPM", '[-+.]'],
    ["left",  "bin", '(?:<<|>>)'],
    ["none",  "bin", '(?:[<>]=?)'],
    ["none",  "bin", '(?:[!=]==?|<=?>)'],
    # foreach can have a left value after 'AS'.
#    ["left",  "binPM", '&'],
    ["left",  "bin", '&'],

    ["left",  "bin", '\^'],
    ["left",  "bin", '\|'],
    ["left",  "bin", '&&'],
    ["left",  "bin", '\|\|'],
    ["right", "bin", '\?\?'],
# 18 left: ?:
    ["left",  "tri", '?:'],
    ["right", "bin", '(?:[-+\/.%&|^]|\*\*?|<<|>>|\?\?)?='],
    ["left",  "bin", 'and'],
    ["left",  "bin", 'xor'],
    ["left",  "bin", 'or'],

    # Vertually, '=>' are treated as operator with the lowest precedence.
    ["left",  "bin", '=>'],
    # Vertually, '...' are treated as operator with the lowest precedence.
    ["right", "ul", "..."],
    ["left", "bin", "as"],
    ["left", "bin", "insteadof"],

    # comma
    ["left",  "binCA", ','],

    );

my %rules = (
    "right:ul" => q(
@OP%ID% => "OP\s+<%PT%>\n"
{ $op:OP%ID% $sp:SP $bx#1:_B_X '(?>':X $any:ANYEXPR $ex#1:_E_X ')':X }
 =>> { ''#1:_B_X $op $sp $bx:B_P $any $ex:E_P ''#1:_E_X }
),
    "PAT:ul" => q(
@OP%ID% => "%PT%\s+<.*?>\n"
{ $op:OP%ID% $sp:SP $bx#1:_B_X '(?>':X $any:ANYEXPR $ex#1:_E_X ')':X }
 =>> { ''#1:_B_X $op $sp $bx:B_P $any $ex:E_P ''#1:_E_X }
),
    "right:ur" => q(
@OP%ID% => "OP\s+<%PT%>\n"
{  $bx#1:_B_X '(?>':X $any:ANYEXPR $ex#1:_E_X ')':X $sp:SP $op:OP%ID% }
 =>> { ''#1:_B_X $bx:B_P $any $ex:E_P $sp $op ''#1:_E_X }
),
    "right:bin" => q(
@OP%ID% => "OP\s+<%PT%>\n"
{ $ex:_E_X $sp:SP $op:OP%ID% } => { $ex ''#1:_B_OP%ID% $sp $op ''#1:_E_OP%ID% }
{ $bx#1:_B_X '(?>':X $any:ANY $ex#1:_E_X ')':X $bop:_B_OP%ID% }
  =>> { $bop $bx:B_P $any $ex:E_P }
{ $bx1#1:_B_OP%ID% '(?>':X $any1:ANY $ex1#1:_E_OP%ID% ')':X $sp:SP
  $bx2#2:_B_X '(?>':X $any2:ANY $ex2#2:_E_X ')':X }
  =>> { ''#1:_B_X $any1 $sp $bx2:B_P $any2 $ex2:E_P ''#1:_E_X }
),

    "left:bin" => q(
@OP%ID% => "OP\s+<%PT%>\n"
{ $op:OP%ID% $sp:SP $bx#1:_B_X $any:ANYEXPR $ex#1:_E_X }
  =>> { ''#1:_B_OP%ID% $op $sp $bx:B_P $any $ex:E_P ''#1:_E_OP%ID% }

{ $bx1#1:_B_X '(?>':X $any1:ANYEXPR $ex1#1:_E_X ')':X $sp1:SP
  $#2:_B_OP%ID% $any2:ANYEXPR $#2:_E_OP%ID% }
  =>> { ''#1:_B_X $bx1:B_P $any1 $ex1:E_P $sp1 $any2 ''#1:_E_X }
),

    "left:binPM" => q(
@OP%ID% => "OP\s+<%PT%>\n"
{ $op:OP%ID% $sp:SP $bx#1:_B_X $any:ANYEXPR $ex#1:_E_X }
  =>> { ''#1:_B_OP%ID% $op $sp $bx:B_P $any $ex:E_P ''#1:_E_OP%ID% }

{ $bx1#1:_B_X '(?>':X $any1:ANYEXPR $ex1#1:_E_X ')':X $sp1:SP
  $#2:_B_OP%ID% $any2:ANYEXPR $#2:_E_OP%ID% }
  =>> { ''#1:_B_X $bx1:B_P $any1 $ex1:E_P $sp1 $any2 ''#1:_E_X }

{ $x:_B_OP%ID% } => { $x:_B_X }
{ $x:_E_OP%ID% } => { $x:_E_X }
)
,

    "left:binCA" => q(
@OP%ID% => "CA\s+<%PT%>\n"
{ [b: $:/[APC]_L/ | $:OP%ID% ] $sp:SP $c:OP%ID% }
=>> { $b ''#1:_B_X ''#1:_E_X $sp $c }
{ $c:OP%ID% $sp:SP $e:/[APC]_R/ }
=>> { $c ''#1:_B_X ''#1:_E_X $sp $e }

{ $op:OP%ID% $sp:SP $bx#1:_B_X '(?>':X $any:ANY $ex#1:_E_X ')':X  }
  =>> { ''#1:_B_OP%ID% $op $sp $bx:B_P $any $ex:E_P ''#1:_E_OP%ID% }

{ $bx1#1:_B_X '(?>':X $any1:ANY $ex1#1:_E_X ')':X $sp1:SP
  $#2:_B_OP%ID% $any2:ANY $#2:_E_OP%ID% }
  =>> { ''#1:_B_X $bx1:B_P $any1 $ex1:E_P $sp1 $any2 ''#1:_E_X }
),

    "array:ur" => q(
{ $:_X_AR $al#a:A_L $arg:ANYEXPR $ar#a:A_R }
  =>> { ''#1:_B_OP%ID% $al $arg $ar ''#1:_E_OP%ID% }
{ $bx#1:_B_X '(?>':X $any:ANYEXPR $ex#1:_E_X ')':X $sp:SP
  $#m:_B_OP%ID% $any1:ANYEXPR $#m:_E_OP%ID% }
  =>> { ''#1:_B_X $bx:B_P $any $ex:E_P $sp $any1 ''#1:_E_X }

{ $x:_B_OP%ID% } => { $x:_B_X }
{ $x:_E_OP%ID% } => { $x:_E_X }

{ $b:OP/\.\.\./ $sp:SP $#m:_B_OP%ID% $any:ANYEXPR $#m:_E_OP%ID% }
  =>> { ''#1:_B_X $b $sp ''#2:_B_X $any ''#2:_E_X ''#1:_E_X }


# array initializer
{ $b:/[AP]_L|CA/ $sp:SP $#m:_B_OP%ID% $any:ANYEXPR $#m:_E_OP%ID% }
  =>> { $b $sp ''#1:_B_X $any ''#1:_E_X }
{ $b:OP/=/ $sp:SP $#m:_B_OP%ID% $any:ANYEXPR $#m:_E_OP%ID% }
  =>> { $b $sp ''#1:_B_X $any ''#1:_E_X }

),

    "left:tri" => q(
#  ? {expr} : => < ? (expr) : >

{ $opl:OP/\?/ $sp1:SP $bx#1:_B_X $any:ANYEXPR $ex#1:_E_X $sp2:SP $opr:OP/:/ }
=>> { ''#1:_B_OP%ID% $opl $sp1 $bx:B_P $any $ex:E_P $sp2 $opr ''#1:_E_OP%ID% }
@:NO_MATCH:END_TRI:

# {expr} < ? (expr) : > => < (expr) ? (expr) : >

{ $bx1#1:_B_X '(?>':X $any1:ANYEXPR $ex1#1:_E_X ')':X $sp:SP
  $bx2#2:_B_OP%ID% $any2:ANYEXPR $ex2#2:_E_OP%ID% }
=>> { $bx2 $bx1:B_P $any1 $ex1:E_P $sp $any2 $ex2 }

# < (expr) ? (expr) : > {expr} => { (expr) ? (expr) : (expr) }

{ $#1:_B_OP%ID% '(?>':X $any1:ANYEXPR $#1:_E_OP%ID% ')':X $sp:SP
  $bx2#2:_B_X $any2:ANYEXPR $ex2#2:_E_X }
=>> {  ''#1:_B_X $any1 $sp $bx2:B_P $any2 $ex2:E_P ''#1:_E_X }

@:LABEL:END_TRI:
),
    "right:cast" => q(
{ $[cast: $#1:B_CST $:ANY $#1:E_CST $] $sp:SP
  $bx#2:_B_X '(?>':X $any:ANYEXPR $ex#2:_E_X ')':X }
  =>> { ''#1:_B_X $cast $sp $bx:B_P $any $ex:E_P ''#1:_E_X }
),

    );


print q(
# Expression rules generated from gen_expr_rules.pl.
), "\n";

my $cnt = 0;
foreach (@op) {
    $cnt++;
    my ($dir, $ar, $pt) = @$_;
    $dir = "right" if ($dir eq "none");
    my $t = "$dir:$ar";
    if ($rules{$t}) {
        my $r = $rules{$t};
        my $c = sprintf("%02d", $cnt);
        $r =~ s/%ID%/$c/g;
        $r =~ s/%PT%/$pt/g;
        print "$r\n";
    } else {
        print "******* $cnt: $t\n";
    }
}
