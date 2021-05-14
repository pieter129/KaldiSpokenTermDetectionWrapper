#!/usr/bin/perl

#------------------------------------------------------------------------------#
# Copyright 2021 (c) Saigen (PTY) LTD 
#
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
#
# Script creates the required resources for keyword spotting.                                      
#------------------------------------------------------------------------------#

use warnings;
use strict;
use File::Basename;
use open IO => ':encoding(utf8)';
use open ':std';
use utf8;
use Audio::Wav;

sub read_list ($\%) {
  my ($fn, $list) = @_;
  my $cnt = 0;
  open FN, "$fn" or die "Error: Cannot open '$fn' for reading!\n";
  while(<FN>) {
    chomp;
    $cnt += 1;
    my $line = $_;
    if ($line =~ /^[^\t]+\t([^\t]+)$/ or $line =~ /^[^ ]+\s+([^ ]+)$/) { $line = $1; }
    my @parts = split(/\//,$line);
    my $bn = pop @parts;
    $bn =~ s/\.[^\.]+$//g;
    $list->{$bn} = $line;
  }
  close(FN);

  print "Info: Read '$cnt' lines from '$fn'\n";
}

sub read_kwds($\%) {
  my ($fn, $kwds_p) = @_;
  my $cnt = 0;
  open FN, "$fn" or die "Error: Cannot open '$fn' for reading!\n";
  while(<FN>) {
    chomp;
    $cnt += 1;
    my $line = $_;
    if ($line =~ /^[^\t]+\t([^\t]+)$/) {
      my @parts = split(/\t/,$line);
      if (exists($kwds_p->{$parts[0]})) {
        die "Error: [$parts[0]] id already used for $kwds_p->{$parts[0]}\n";
      }
      $kwds_p->{$parts[0]} = $parts[1];
    } else {
      die "Error: format error in kwids\n";
    }
  }
  close(FN);

  print "Info: Read '$cnt' lines from '$fn'\n";
}

sub read_ctm($\%) {
  my ($fn, $ctm_p) = @_;
  open CTM, "$fn" or die "Error: Cannot open '$fn' for reading!\n";
  while(<CTM>) {
    chomp;
    my @parts = split(/\s+/,$_);
    $ctm_p->{$parts[0]}{$parts[2]}{"dur"} = $parts[3];
    $ctm_p->{$parts[0]}{$parts[2]}{"wrd"} = $parts[4];
  }
  close(CTM);
  printf "Info: Read '%d' files from '$fn'\n", scalar(keys %$ctm_p);
}

if ((@ARGV + 0) < 4) {
  print "perl prep_kw_resources.pl <tag> <out:dir> <in:wav> <in:kwds> [<in:fn:text | fn:ctm>]\n";
  print "  fn:text | fn:ctm	kaldi text file or ctm file from which to generate rttm\n";
  print "  kwds format:	kwid[tab]kwds\n";
  exit 1;
}

my $tag     = $ARGV[0];
my $dir_out = $ARGV[1];
my $fn_iwav = $ARGV[2];
my $fn_kwds = $ARGV[3];
my $fn_ref  = "";
my $fn_type = "";

my %ref;
if (scalar(@ARGV) == 5) {
  if ($ARGV[4] =~ /^([^:]+):(text|ctm)$/) {
    $fn_ref = $1;
    $fn_type= $2;
    if ($fn_type eq "ctm") {
      read_ctm($fn_ref, %ref);
    }
  } else {
    die "Error: expected [$ARGV[4]] to be in format [fn:(text|ctm)]\n";
  }
}

system("mkdir -p $dir_out");

my %txts;
my %wavs;
my %kwds;

# Read the names from the lists
#read_list($fn_itxt, %txts);
read_list($fn_iwav, %wavs);
read_kwds($fn_kwds, %kwds);

# ---------------------------------------------
# Generate the ECF file from the wav file list
# ---------------------------------------------
system("mkdir -p $dir_out");
my $fn_ecf = "$dir_out/$tag.ecf.xml";
open OUT, ">$fn_ecf" or die "Error: Cannot open '$fn_ecf' for writing\n";
my $total_dur = 0;
my @lines;
my %dur;
foreach my $bn (sort keys %wavs) {
  my $fn_wav = $wavs{$bn};
  if (!defined($fn_wav)) {
    die "Error: no wav file for '$bn': skipping.\n";
  } else {
    my $audio_seconds = `soxi -D $fn_wav`;
    chomp($audio_seconds);
    my $line = sprintf("<excerpt audio_filename=\"%s.wav\" channel=\"1\" tbeg=\"0.000\" dur=\"%.3f\" source_type=\"splitcts\"/>", $bn, $audio_seconds);
    push @lines, $line;
    $dur{$bn} = $audio_seconds;
    $total_dur += $audio_seconds;
  }
}

my $datestring = localtime();
printf OUT "<ecf source_signal_duration=\"%.2f\" language=\"sa_english\" version=\"$tag - %s\">\n", $total_dur, $datestring;
printf OUT "%s\n", (join "\n", @lines);
print OUT "</ecf>\n";
close(OUT);
print "Info: done [$fn_ecf]\n";

# ---------------------------------------------
# Generate the KWS file
# ---------------------------------------------
@lines = ();
$fn_kwds = "$dir_out/$tag.kwlist.xml";
open OUT, ">$fn_kwds" or die "Error: Cannot open '$fn_kwds' for writing\n";
foreach my $id (sort keys %kwds) {
  my $kwd = $kwds{$id};
  my $line = sprintf("<kw kwid=\"%s\">", $id); push @lines, $line;
  $line = sprintf("<kwtext>%s<\/kwtext>\n<\/kw>", $kwd); push @lines, $line;
}

printf OUT "<kwlist ecf_filename=\"%s\" language=\"sa_english\" encoding=\"UTF-8\" compareNormalize=\"lowercase\" version=\"keywords - %s\">\n", $fn_ecf, $datestring;
printf OUT "%s\n", (join "\n", @lines);
print OUT "</kwlist>\n";
close(OUT);
print "Info: done [$fn_kwds]\n";

# Create rttm if defined
if ($fn_ref ne "") {
  @lines = ();
  my $fn_rttm = "$dir_out/$tag.rttm";
  # Create the rttm
  foreach my $bn (sort keys %ref) {
    my $line = sprintf("SPKR-INFO %s 1 <NA> <NA> <NA> unknown %s <NA>", $bn, $bn);
    push @lines, $line;
    $line = sprintf("SPEAKER %s 1 0.000 %.3f <NA> <NA> %s <NA>", $bn, $dur{$bn}, $bn);
    push @lines, $line;
    foreach my $ts (sort { $a <=> $b } keys %{ $ref{$bn} }) {
      $line = sprintf("LEXEME %s 1 %.3f %.3f %s lex %s <NA>", $bn, $ts, $ref{$bn}{$ts}{"dur"}, $ref{$bn}{$ts}{"wrd"}, $bn);
      push @lines, $line;
    }
  }
  open OUT, ">$fn_rttm" or die "Error: Cannot open '$fn_rttm' for writing\n";
  printf OUT "%s\n", (join "\n", @lines);
  close(OUT);
  print "Info: done [$fn_rttm]\n";
}
