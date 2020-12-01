# 言語判定 & 共通モデル作成用モジュール

package PPParser;

use strict;
use warnings;

use Data::Dumper;

my $LIB;

use RewriteTokens;
use Diff 'diff';
use PParser;


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
  my @result;

  # my @langs = ( "c", "php", "python", "ruby", "javascript" );
  my @langs;

  my $fname = "$LIB/language";
  open(my $fp, '<', $fname) || die "can't open $fname";
    while(my $line = <$fp>) {
      chomp $line;
      push @langs, $line;
    }
  close($fp);

  # PParserのインスタンスを作成
  my $pp = PParser->new();

  # 言語ごとにインスタンスをコピーしつつ(insert_token_def)
  # 言語ごとの解析結果を変数に格納
  foreach my $lang (@langs) {
    my $code = $pp->insert_token_def($lang)->parse($tk);

    # rulesを適用し、言語の判定、共通モデル抽出
    $code = &check_rules($code, $lang);

    # 出力を配列に格納
    push @result, $code;
  }

  # 配列を結合し、出力
  return join("", @result);
}

sub check_rules() {
  my ($code, $lang) = @_;

  $code = RewriteTokens->new()->set_rules(&load_rules('unit'))
    ->rewrite($code);

  my $token = $code;

  $code = RewriteTokens->new()->set_rules(&load_lang_rules($lang))
    ->rewrite($code);

  my $diff = diff(\$token, \$code);

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
    my $lang = shift;
    my $fname = "$LIB/${lang}/${lang}.rules";
    my $common_def = "$LIB/common.rules";

    open(my $co, '<', $common_def) || die "can't open $common_def";
    my $def = join('', <$co>);
    close($co);
    open(my $fp, '<', $fname) || die "can't open $fname";
    my $rules = join('', <$fp>);
    close($fp);
    return $def.$rules;
}

sub load_def() {
    my $language = shift;
    my $fname = "$LIB/$language.def";

    open(my $fp, '<', $fname) || die "can't open $fname";
    my $def = join('', <$fp>);
    close($fp);
    return $def;
}

sub read_file() {
    my $name = shift;
    open(my $f, '<', "$LIB/$name") || die "Can't open $name: $!";
    my $t = join('', <$f>);
    close($f);
    return $t;
}
# ======================================================================

###### テスト
sub test() {
  my $self = shift;

}

sub csv() {
  my $self = shift;
  open (OUT, ">$LIB/test.csv") or die "$!";
  foreach my $line ($self) {
    print OUT "$line\n";
  }
  close (OUT);
  return $self;
}

# use がエラーにならないように 0 以外の値を記述しておく
1;         
