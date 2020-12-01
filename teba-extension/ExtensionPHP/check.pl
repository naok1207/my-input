#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib ("$Bin/../TEBA/LangChecker", "$Bin/../TEBA", "$Bin/../TEBA/PHParse");

use Check;

use Getopt::Std;

my %opts;
if (!getopts("deEh", \%opts) || $opts{h}) {
    print STDERR "check.pl [-cphpjsrbpy] [files...]\n",
                 "  -c: check C\n",
                 "  -php: check PHP\n",
                 "  -js: check JavaScript\n",
                 "  -rb: check Ruby\n",
                 "  -py: check Python\n",
                 "  -h: help.\n";
    exit(1);
}

my @tk = <>;

if ($opts{c}) {
  print "check C -----------------------------------------\n"
  print Check->new('c')->set_teba(\@tk)->check();
}
if ($opts{php}) {
  print "check PHP ---------------------------------------\n"
  print Check->new('php')->set_teba(\@tk)->check();
}
if ($opts{js}) {
  print "check JavaScript --------------------------------\n"
  print Check->new('javascript')->set_teba(\@tk)->check();
}
if ($opts{rb}) {
  print "check Ruby --------------------------------------\n"
  print Check->new('ruby')->set_teba(\@tk)->check();
}
if ($opts{py}) {
  print "check Python ------------------------------------\n"
  print Check->new('python')->set_teba(\@tk)->check();
}