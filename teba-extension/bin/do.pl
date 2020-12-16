#!/usr/bin/env perl
use strict;
use warnings;

use FindBin qw($Bin);
use lib ("$Bin/../../teba/TEBA/PHParse","$Bin/../../teba/TEBA","$Bin/../ExtensionPHP");

use JSON;
use WWrong;
use CommonModel;
use TEBA2TEXT;

my $json_text;

my $code = $ARGV[0];
my $lang = $ARGV[1];

# 改行文字を追加
$code .= "\n";

# stmt-judge.pl
my $stmt;

if($code =~ /^[^a-zA-Z0-9]*(if|else|elseif|elsif|elif|else\sif)/){
    $stmt = "if";
}elsif($code =~ /^[^a-zA-Z0-9]*(for|foreach)/){
    $stmt = "for";
}elsif($code =~ /^[^a-zA-Z0-9]*(while)/){
    $stmt = "while";
}else{
    $json_text = {
      ok => "false",
      error => "no_stmt"
    };
    $json_text = JSON->new()->pretty()->encode( $json_text );
    print $json_text;
    exit(0);
}

# wrong.pl
my $wrong = WWrong->new()->check($code, $stmt);

# common-model.pl
my @tk = split(/\n/, $wrong);

if (!@tk || $tk[0] !~ /OK/){ 
  $json_text = {
    ok => "false",
    error => "not_code"
  };
  $json_text = JSON->new()->pretty()->encode( $json_text );
  print $json_text;
  exit(0);
}

my $expr = &CommonModel::expr_checker($lang, @tk);

my @model;
my @count;
my $i = 0;
my $j = 0;

while($tk[$i] =~ /^(?!.*CNT).*$/){
    push(@model,$&."\n");
    $i++;
}
while($i <= $#tk){
    $count[$j] = $tk[$i];
    $i++; $j++;
}

my $from_lang = &CommonModel::lang_judge(@count);
my $token = CommonModel->new($lang)->set_teba(\@model)->rewrite();

# join-token.pl
my $to_code = TEBA2TEXT->new()->set_teba($token)->text();

# 改行文字を取り除く
$code =~ s/\n//;
$to_code =~ s/\n//;

# print
$json_text = {
  ok => "true",
  messages => [
    {
      message => $from_lang . "っぽい",
    },
    {
      message => $expr,
    }
  ],
  from => { language => $from_lang, code => $code },
  to => { language => $lang, code => $to_code }
};
$json_text = JSON->new()->pretty()->encode( $json_text );
print $json_text;
