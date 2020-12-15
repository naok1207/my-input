# 言語判定 & 共通モデル作成用モジュール
package WWrong;

use strict;
use warnings;

use Data::Dumper;

my $LIB;

use RewriteTokens;
use Diff 'diff';
use Wrong;


# パッケージを有効化するため
BEGIN {
    ($LIB = $INC{__PACKAGE__ . ".pm"}) =~ s/[^\/]+$//;
    unshift(@INC, "$LIB/..");
}

sub new() {
  # このパッケージにオブジェクト $self を連携させる
  my $self = bless {};
  return $self;
}

sub check() {
  my ($self, $tk) = @_;
  my $stmt = $_[2];
  my @result;

  # PParserのインスタンスを作成
  my $wrong = Wrong->new();

  # 言語ごとにインスタンスをコピーしつつ(insert_token_def)
  # 言語ごとの解析結果を変数に格納

  my $code = $wrong->insert_token_def()->parse($tk);

  # rulesを適用し、言語の判定、共通モデル抽出
  $code = &check_rules($code,$stmt);

  # 出力を配列に格納
  push @result, $code;

  # 配列を結合し、出力
  return join("", @result);
}

sub check_rules() {
  my $code = $_[0];
  my $stmt = $_[1];

  # unit_wrong.rulesを適用
  $code = RewriteTokens->new()->set_rules(&load_rules('unit_wrong'))
    ->rewrite($code);

  my $token = $code;

  # wrong.rulesを適用
  $code = RewriteTokens->new()->set_rules(&load_lang_rules($stmt))
    ->rewrite($code);
 
  my $diff = diff(\$token, \$code);
  
  # 差分ないなら変更されていないのでなにも出力しない
  if ($diff eq '') {
    $code = "";
  }

  return $code;
}

# 実行補助用ルーチン ======================================================
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

sub load_lang_rules() {
    my $stmt = shift;
    my $common_def = "$LIB/common.rules";
    my $fname = "$LIB/${stmt}_wrong.rules";
    open(my $co, '<', $common_def) || die "can't open $common_def";
    my $def = join('', <$co>);
    close($co);
    open(my $fp, '<', $fname) || die "can't open $fname";
    my $rules = join('', <$fp>);
    close($fp);
    return $def.$rules;
}


# ======================================================================


# use がエラーにならないように 0 以外の値を記述しておく
1;         
