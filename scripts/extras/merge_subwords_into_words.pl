#!/usr/bin/perl

# Copyright 2021 Saigen (PTY) LTD

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# This script merges sub-word units in a CTM to reconstruct the original
# word forms.

use warnings;
use strict;
use File::Basename;
use open IO => ':encoding(utf8)';
use open ':std';
use utf8;

if ((@ARGV + 0) != 2) {
  print "perl $0 <in:ctm> <out:ctm>\n";
  print "  <in:ctm>  - input ctm with [sub+ +words]\n";
  print "  <out:ctm> - output ctm with [subwords]\n";
  exit 1;
}

my $ctm_in  = $ARGV[0];
my $ctm_out = $ARGV[1];

my %lines;
open CTM_IN, "$ctm_in" or die "Error: Cannot open '$ctm_in' for reading!\n";
while(<CTM_IN>) {
  chomp;
  my $line = $_;
  my @words = split(/\s+/,$line);
  my $bn = $words[0];
  push @{ $lines{$bn} }, $line;
}
close(CTM_IN);

sub mean(\@) {
  my ($vals_p) = @_;
  my $sum;
  foreach my $s (@$vals_p) {
    $sum += $s;
  }
  return $sum / scalar(@$vals_p);
}

sub add_to_sequence($$\@\@) {
  my ($wrd, $cnf, $wrds_p, $cnfs_p) = @_;
  push @$wrds_p, $wrd;
  push @$cnfs_p, $cnf;
}

sub end_the_sequence($$\@\@\%) {
  my ($ts_seq_tmp, $dur_tmp, $wrds_p, $cnfs_p, $ctm_p) = @_;
  $ctm_p->{$ts_seq_tmp}{"wrd"} = join(" ", @$wrds_p);
  $ctm_p->{$ts_seq_tmp}{"dur"} = $dur_tmp;
  $ctm_p->{$ts_seq_tmp}{"cnf"} = mean(@$cnfs_p);
  @$wrds_p = ();
  @$cnfs_p = ();
}

my %ctm;
foreach my $bn (sort keys %lines) {
  my @words;
  my @confs;
  my $ts_seq = 0;

  foreach my $i (0..(@{ $lines{$bn} } - 1)) {
    my $line = $lines{$bn}[$i];
    my @parts = split(/\s+/, $line);
    my $ts  = $parts[2];
    my $dur = $parts[3];
    my $wrd = $parts[4];
    my $cnf = $parts[5];
    if (scalar(@words) == 0) {
      # We expect something that ends with ] or +
      if ($wrd =~ /[^\+]$/) {
        $ctm{$bn}{$ts}{"wrd"} = $wrd; $ctm{$bn}{$ts}{"dur"} = $dur; $ctm{$bn}{$ts}{"cnf"} = $cnf;
      } else {
        $ts_seq = $ts;
	add_to_sequence($wrd, $cnf, @words, @confs);
      }
    } else {
      # We have words that should be joined. This word can either end the sequence, or add to it
      if ($wrd =~ /^\+/ and $wrd =~ /\+$/) {
        # (1) Just add to sequence
	add_to_sequence($wrd, $cnf, @words, @confs);
      } elsif ($wrd =~ /^\+/ and $wrd !~ /\+$/) {
        # (2) Add and END
	add_to_sequence($wrd, $cnf, @words, @confs);
	#END THE SEQ
	end_the_sequence($ts_seq, $ts - $ts_seq + $dur, @words, @confs, %{ $ctm{$bn} });
      } elsif ($wrd !~ /^\+/ and $wrd !~ /\+$/) {
        # (3) END AND PRINT
	# Illegal
	printf("Warning: illegal sequence. [%s][%s]\n", (join(" ", @words)), $wrd);
	# END THE SEQ
	end_the_sequence($ts_seq, $ts - $ts_seq, @words, @confs, %{ $ctm{$bn} });
        # ADD THE WORD
        $ctm{$bn}{$ts}{"wrd"} = $wrd; $ctm{$bn}{$ts}{"dur"} = $dur; $ctm{$bn}{$ts}{"cnf"} = $cnf;
      } elsif ($wrd !~ /^\+/ and $wrd =~ /\+$/) {
        # (3) END AND ADD
	# END THE SEQ
	end_the_sequence($ts_seq, $ts - $ts_seq, @words, @confs, %{ $ctm{$bn} });
	add_to_sequence($wrd, $cnf, @words, @confs);
      }
    }

    if ($i == (@{ $lines{$bn} } - 1) and scalar(@words) > 0) {
      end_the_sequence($ts_seq, $ts - $ts_seq + $dur, @words, @confs, %{ $ctm{$bn} });
    }
  }
}
      
open CTM_OUT, ">$ctm_out" or die "Error: Cannot open '$ctm_out' for writing!\n";
foreach my $bn (sort keys %ctm) {
  #print "[$bn]\n";
  foreach my $ts (sort { $a <=> $b } keys %{ $ctm{$bn} }) {
    #print "$ts\n";
    my $word = $ctm{$bn}{$ts}{"wrd"};
    #print "[$word]\n";
    $word =~ s/\+\s+\+//g;
    $word =~ s/\+//g;
    #print "[$word]\n";
    printf CTM_OUT "%s 1 %.2f %.2f %s %.2f\n", $bn, $ts, $ctm{$bn}{$ts}{"dur"}, $word, $ctm{$bn}{$ts}{"cnf"};
  }
}
close(CTM_OUT);
