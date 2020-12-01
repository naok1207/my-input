sub lang_judge() {
    
    my $model;
    my $lang;

    if($_[0] =~ /(.+)*\n(.+)*/){
       $model = "$1"."\n";
       $lang = "$2";
    }else{
        print "エラー\n";
        return 0;
    }

    my @cnt = (0,0,0,0,0);

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

    for(my $i = 0;$i <= $#cnt;$i++){
    if($max == $cnt[$i] && $i == 0){  print "C言語 "; }
    if($max == $cnt[$i] && $i == 1){ print "PHP "; }
    if($max == $cnt[$i] && $i == 2){ print "JS "; }
    if($max == $cnt[$i] && $i == 3){ print "Python "; }
    if($max == $cnt[$i] && $i == 4){ print "Ruby "; }
    }
    print "っぽい\n";

    return $model;
}

1;