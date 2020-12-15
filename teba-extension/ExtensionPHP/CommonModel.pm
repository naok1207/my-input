package CommonModel;

use strict;
use warnings;

use Data::Dumper;

my $LIB;

use RewriteTokens;
use Diff 'diff';


# パッケージを有効化するため
BEGIN {
    ($LIB = $INC{__PACKAGE__ . ".pm"}) =~ s/[^\/]+$//;
    unshift(@INC, "$LIB/..");
}

sub new() {
  # このパッケージにオブジェクト $self を連携させる
  my $self = bless {};
  if (defined $_[1]) {
    $self->{lang} = $_[1];
  }
  return $self;
}



sub set_teba() {
    # パッケージ名を$selfに記録
    my $self = shift;
    my $text = shift;
    # 引数がリファレンスならリファレンスが参照する型を返す
    if (ref($text) eq "ARRAY") {
      # 属性を設定
      $self->{coderef} = $text;
    } else { # should be ARRAY
      $self->{coderef} = [ split("\n", $text) ];
    }
    return $self;
}

sub rewrite() {
  my $self = shift;
  my @res;
  my $code = join("", @{$self->{coderef}});

  # 共通モデルからの書き換え
  $code = RewriteTokens->new()->set_rules(&load_rules($self->{lang}))
    ->rewrite($code);

  return $code;
}

sub load_rules() {
    my $lang = shift;
    my $fname = "$LIB/${lang}/change-${lang}.rules";
    my $common_def = "$LIB/common.rules";

    open(my $co, '<', $common_def) || die "can't open $common_def";
    my $def = join('', <$co>);
    close($co);
    open(my $fp, '<', $fname) || die "can't open $fname";
    my $rules = join('', <$fp>);
    close($fp);
    return $def.$rules;
}

sub expr_checker() {
  my $lang = shift;
  my @tk = @_;
  my $result = "$langに ";
 
  foreach my $t(@tk){
    #論理演算子 and
    if($t =~ /^OP\s+<\&\&>$/ && $lang eq "python"){
      $result .=  "「\&\&」";
    }
    elsif($t =~ /^OP\s+<and>$/ && ($lang eq "c" || $lang eq "javascript")){
      $result .=  "「and」";
    }

    #論理演算子 or
    if($t =~ /^OP\s+<\|\|>$/ && $lang eq "python"){
      $result .=  "「\|\|」";
    }
    elsif($t =~ /^OP\s+<or>$/ && ($lang eq "c" || $lang eq "javascript")){
      $result .=  "「or」";
    }

    #論理演算子 not
    if($t =~ /^OP\s+<!>$/ && $lang eq "python"){
      $result .=  "「!」";
    }
    elsif($t =~ /^ID_C\s+<not>$/ && $lang ne "python"){
      $result .=  "「not」";
    }

    # ==,===
    if($t =~ /^OP\s+<==>$/ && ( $lang eq "javascript" || $lang eq "php" )){
      $result .=  "「==」";
    }
    elsif($t =~ /^OP\s+<===>$/ && ( $lang eq "c" || $lang eq "python" || $lang eq "ruby")){
      $result .=  "「===」";
    }

    # !=,!==
    if($t =~ /^OP\s+<!=>$/ && ( $lang eq "javascript" || $lang eq "php" )){
      $result .=  "「!=」";
    }
    elsif($t =~ /^OP\s+<!==>$/ && ( $lang eq "c" || $lang eq "python" || $lang eq "ruby")){
      $result .=  "「!==」";
    }

    # $
      if($t =~ /^ID_C\s+<(.*)>$/ &&  $lang eq "php" ){
      $result .=  "「\$なし」";
    }
     elsif($t =~ /^ID_V\s+<(.*)>$/ &&  $lang ne "php" ){
      $result .=  "「\$あり」";
    }

    # 追加でチェックしたい字句系列を追加
    #     if($t =~ /字句系/ && $lang eq "その言語"){
    #     print "$langに !";
    # }
    #    elsif($t =~ /字句系/ && $lang ne "その言語"){
    #     print "$langに not";
    # }

  }
  if($result ne "$langに " ){
    $result .= "?\n";
    return $result;
  } else {
    return '';
  }
}

sub lang_judge() {
    
    my @count = @_;
    my @cnt = (0,0,0,0,0);
    my $lang = "";

    foreach(@count){
      if(/CNT(\s)+<(.*)>/){
        $lang = $lang.$2;
      }
    }

    foreach my $c (split //,  $lang){

        #C,PHP,JS,Python,Ruby
    if($c eq "C"){  $cnt[0]++; }
    elsif($c eq "P"){ $cnt[1]++;}
    elsif($c eq "J"){ $cnt[2]++;}
    elsif($c eq "Y"){ $cnt[3]++;}
    elsif($c eq "R"){ $cnt[4]++;}
    }

  
   my $max = $cnt[0];
   my $max_idx = 0;
    for(my $i = 1;$i <= $#cnt;$i++){
        if($max < $cnt[$i]){
            $max = $cnt[$i];
            $max_idx = $i;
        }
    }

    my $language;

    for(my $i = 0;$i <= $#cnt;$i++){
    if($max == $cnt[$i] && $i == 0){ $language = "C言語 "; }
    if($max == $cnt[$i] && $i == 1){ $language = "PHP "; }
    if($max == $cnt[$i] && $i == 2){ $language = "JS "; }
    if($max == $cnt[$i] && $i == 3){ $language = "Python "; }
    if($max == $cnt[$i] && $i == 4){ $language = "Ruby "; }
    }
    return $language;
 
}

# use がエラーにならないように 0 以外の値を記述しておく
1;
