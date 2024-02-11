#!/usr/bin/perl
#
#２進数文字列を16進数文字列に変換するスクリプト
#
# copyright (c) 2023 kouji55@gmail.com
#

my @data;
my @comment;
while(<>){
    if(/^.byte    %(.+)$/){ #２進数文字列の取得
	my $num = oct('0b' . $1); #2進数->10進数
	my $hex = sprintf("%02X", $num); #10進数->16進数
	push @data, $hex;
	push @comment, $1;
    }
}

for ($i = 1; $i <= (8 * 7); $i++) {
    printf(".byte \$%s, \$%s ;%s %s\n",
	   $data[$i - 1], $data[$i - 1 + (8 * 7)],
	   $comment[$i - 1],
	   $comment[$i - 1 + (8 * 7)]);

    if ($i % 8 == 0) {
	printf("\n");
    }
}
