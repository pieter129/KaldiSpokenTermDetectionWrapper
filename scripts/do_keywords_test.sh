#!/bin/bash
set -euo pipefail

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
# This is a test script to demonstrate how the main keyword script 
# do_all_kws_search should be run.
#-----------------------------------------------------------------------------#

############################# SET TEST LANGUAGE ###############################

lang='afr' # Alternative options: 'sot' , 'zul'

###############################################################################

#-----------------------------------------------------------------------------#
# Initialise Variables                                                        #
#-----------------------------------------------------------------------------#

dir_scripts=$( dirname "$(realpath "$0")" )
dir_data=$dir_scripts/../data/${lang}_parl
dir_audio=$dir_data/audio
dir_text=$dir_data/text
dir_work=$dir_scripts/../keyword_output

ctm=$dir_data/${lang}_parliament_clip.ctm
kwd_list=$dir_data/keywords.txt

aligned_ctm=true
score=true

#-----------------------------------------------------------------------------#
# Source Argument Parser Scripts                                              #
#-----------------------------------------------------------------------------#

source $dir_scripts/../conf/var.conf

[[ ! -v KALDI_ROOT ]] && echo "Error: \$KALDI_ROOT path does not exist!!" && exit
babel_root_dir=$KALDI_ROOT/egs/babel/s5d

. $babel_root_dir/utils/parse_options.sh
. $dir_scripts/bash_helper_functions.sh

#-----------------------------------------------------------------------------#
# Commandline Argument Info                                                   #
#-----------------------------------------------------------------------------#

if [ $# != 0 ]; then
  echo "Usage: $(basename $0) [options]"
  echo ""
  echo "Options:"
  echo "  --dir-scripts	     <dir>     # Directory containing all the scripts ($dir_scripts)"
  echo "  --dir-data	     <dir>     # Data directory containing audio files ($dir_data)"
  echo "  --ctm		     <ctm>     # Ctm i.r.o. audio file ($ctm)"
  echo "  --dir-text	     <dir>     # Directory containing text i.r.o. audio files ($dir_text)"
  echo "  --kwd-list	      <fn>     # List of keywords to search for ($kwd_list)"
  echo "  --dir-work	     <dir>     # Output directory ($dir_work)"
  echo "  --score     <true|false>     # Score the output ($score)"
  echo "  --aligned-ctm      <ctm>     # Aligned ctm option ($aligned_ctm)"
  exit 1;
fi

#-----------------------------------------------------------------------------#
# Create required input resources for Keyword Search Script                   #
#-----------------------------------------------------------------------------#

mkdir -p $dir_work
find $dir_audio -iname "*.wav" > $dir_audio/../wav.lst   # List of audio files
find $dir_text -iname "*.txt" > $dir_text/../txt.lst     # List of text files

#-----------------------------------------------------------------------------#
# Run Keyword Search                                                          #
#-----------------------------------------------------------------------------#

# i) Run with Scoring
if [ $score == "true" ]; then

  # a) Use Aligned CTM
  if [ $aligned_ctm == "true" ]; then 
    echo "Info: Scoring - Aligned CTM"

    bash $dir_scripts/do_all_kws_search.sh --aligned-ctm $ctm $dir_audio/../wav.lst $kwd_list $lang \
	 $dir_work $dir_work/kwd_results

  # b) Use text files
  else
    echo "Info: Scoring - Text Files"
    bash $dir_scripts/do_all_kws_search.sh --txt-list $dir_text/../txt.lst $dir_audio/../wav.lst $kwd_list $lang \
	 $dir_work $dir_work/kwd_results
  fi

# ii) Run without scoring
else
  echo "Info: Test - No scoring"
  bash $dir_scripts/do_all_kws_search.sh $dir_audio/../wav.lst $kwd_list $lang $dir_work $dir_work/kwd_results

fi

echo "Sample Run: [$lang] : Complete."
