#!/usr/bin/perl
use FindBin qw($Bin);
use lib "$Bin/../TEBA";
use lib "$Bin/../TEBA/ProgPattern";

use strict;
use warnings;

use ProgTrans;

my @token_patterns = (
# remove spaces
q( { $:/SP\\w+/ } => { } )
    );

my @macro_def_patterns = (
# strip do-while(0)
q(
%%before
#define ${name:ID_MC}%s do ${body:STMT} while(0)
%%after
#define ${name}%s ${body}
%%end
),
# strip a compound block
q(
%%before
#define ${name:ID_MC}%s { ${body:ANY} }
%%after
#define ${name}%s $[body]
%%end
),
# strip the outermost parentheses
q(
%%before
#define ${name:ID_MC}%s ( ${body:ANY} )
%%after
#define ${name}%s $[body]
%%end
),
    );

my @expr_patterns = (
# srip pairs of parentheses surrounding variables.
q(
%ex
%before
(${v:ID_VF})
%after
${v}
%end
),
);
#########################################################


my $vars = ProgTrans->new()->build()->{vars};

my @rules;

#push(@rules, @token_patterns);

foreach my $p (@macro_def_patterns) {
    my $pt = ProgTrans->new()->set_pattern(
        sprintf($p, '(${args:ARGLIST})', '(${args})'))->build();
    push(@rules, $pt->{rule});
    $pt = ProgTrans->new()->set_pattern(sprintf($p, '', ''))->build();
    push(@rules, $pt->{rule});
    
}

push(@rules, q(
{ $ct:/CT_(?:BE|IF)/ $sp:SP $bp:B_P $pl#1:P_L $e:ANY $pr#1:P_R } 
=> {$ct $sp $bp '('#1:_XP_L $e ')'#1:_XP_R }
));
foreach my $p (@expr_patterns) {
# strip pairs of parentheses surrounding variables.
    my $pt = ProgTrans->new()->set_pattern($p)->build();
    push(@rules, $pt->{rule});
}
push(@rules, q(
{ $ct:/CT_(?:BE|IF)/ $sp:SP $bp:B_P $pl#1:_XP_L $e:ANY $pr#1:_XP_R } 
=> {$ct $sp $bp '('#1:P_L $e ')'#1:P_R}
));

## for variable arguments
push(@rules, q(
{ $:/ID.*//__VA_ARGS__/ } => { '${__VA_ARGS__:ARGLIST}':ID_VF }
{ $:ID_VF/\.\.\./ } => { '${__VA_ARGS__:ARGLIST}':ID_VF }
));

my $templ = q(
    $pt = q@%s@;
    $tk = RewriteTokens->seq($vars, $pt)->rewrite($tk);
    $tk = $be->conv($bi->conv($tk));
);
my $rules = join("\n", map(sprintf($templ, $_), @rules));

print qq/
use BeginEnd;
use BracketsID;

sub normalize_macro_def() {
    my \$tk = shift;
    my \$vars = q!$vars!;
    my \$pt;
    my \$be = BeginEnd->new();
    my \$bi = BracketsID->new();
$rules
    return \$tk;
}
/;
