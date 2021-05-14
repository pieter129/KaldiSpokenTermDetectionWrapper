#!/bin/bash
set -euo pipefail

#------------------------------------------------------------------------------#
# Copyright 2021 (c) Saigen (PTY) LTD 

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#  http://www.apache.org/licenses/LICENSE-2.0

# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# Script creates the required resources for keyword spotting using Kaldi's   
# keyword search script. Scores results                                      

# This is a wrapper-script for calling the decode_chain.sh. It creates the     
# resources required as input for decoding.                                   
#------------------------------------------------------------------------------#

# -----------------------------------------------------------------------------#
# Initialise Variables                                                         #
# -----------------------------------------------------------------------------#

dir_scripts=$( dirname "$(realpath "$0")" )

max_lmwt=9
min_lmwt=9
nj=20
num_threads=0
tag=`date -I`
word_ins_penalty=0.5
word_alignment=true

# ----------------------------------------------------------------------------#
# Source Argument Parser Scripts                                              #
# ----------------------------------------------------------------------------#

source $dir_scripts/../conf/var.conf

[ ! -v "KALDI_ROOT" ] && echo "Error: \$KALDI_ROOT path does not exist!!" && exit
babel_root_dir=$KALDI_ROOT/egs/babel/s5d
cd $babel_root_dir

. utils/parse_options.sh || exit 1
[ -f local.conf ] && . ./local.conf
. conf/common_vars.sh || exit 1;
. $dir_scripts/bash_helper_functions.sh

# ----------------------------------------------------------------------------#
# Commandline Argument Info                                                   #
# ----------------------------------------------------------------------------#

if [ $# -lt 4 ]; then
    echo "Usage: $(basename $0) [options] <in:dir_model> <in:dir_graph> <in:wavs_lst> <out:dir_work>"
    echo "Args:"
    echo "  dir_model	  # Model directory (contains exp, steps, utils, etc)."
    echo "  dir_graph	  # Graph directory (contains HCLG.fst, phones.txt, etc)."
    echo "  wavs_list	  # Text file listing full file paths to wav files to be decoded."
    echo "  dir_work	  # Working Directory (\$dir_work/decode\$tag will be removed)."
    echo ""
    echo "Options:"
    echo "  --max-lmwt	   	     <int>   # Maximum language model weight. Default ($max_lmwt)."
    echo "  --min-lmwt	 	     <int>   # Minimum language model weight. Default ($min_lmwt). " 
    echo "  --nj 	   	     <int>   # Number of parrellel jobs to run. ($nj)."
    echo "  --num-threads  	     <int>   # Number of threads to use per process ($num_threads)."
    echo "  --tag 		     <tag>   # Name of data batch, eg atc_eng_01-12-18. ($tag)."
    echo "  --word-alignment  <true|false>   # Lattice to ctm word alignment ($word_alignment)."
    echo "  --word_ins_penalty	   <float>   # Default ($word_ins_penalty)."
    exit 1;
fi

# -----------------------------------------------------------------------------#
# Set Required Arguments                                                       #
# -----------------------------------------------------------------------------#

dir_model=`realpath $1`
dir_graph=`realpath $2`
wavs=`realpath $3`
dir_work=`realpath $4`

if [ -z $tag ]
then
  tag2=$tag
else
  tag2=$(echo "_$tag")
fi

# -----------------------------------------------------------------------------#
# Setup                                                                        #
# -----------------------------------------------------------------------------#

safe_remove_dir $dir_work/decoded${tag2} 1
mkdir -p $dir_work/decoded${tag2}
dir_out=$dir_work/decoded${tag2}

dir_segment=$dir_work/segmentation
mkdir -p $dir_segment/vad_data
dir_prep=$dir_segment/vad_data

cat $wavs | awk -F '/' '{print $NF " " $0}' | sed "s/\.wav//1" | sort > $dir_prep/wav.scp
cat $dir_prep/wav.scp | awk '{print $1 " " $1}' > $dir_prep/utt2spk
cat $dir_prep/wav.scp | awk '{print $1 " " $1}' > $dir_prep/spk2utt

echo "Info: Created required files."

# -----------------------------------------------------------------------------#
# Create Segments                                                              #
# -----------------------------------------------------------------------------#                                                            

# MFCC creation
num_files=`wc -l $wavs | awk '{print $1}'`

steps/make_mfcc.sh --mfcc-config conf/mfcc.conf --nj $num_files \
        --cmd "$train_cmd" --write-utt2num-frames true \
        $dir_prep $dir_segment/log $dir_segment/vad

# Compute VAD decision
steps/compute_vad_decision.sh --vad-config ../../callhome_diarization/v1/conf/vad.conf --nj $num_files --cmd "$train_cmd" $dir_prep \
	$dir_segment/make_vad $dir_prep

utils/fix_data_dir.sh $dir_prep
bash ../../callhome_diarization/v1/diarization/vad_to_segments.sh --nj $num_files --cmd "$train_cmd" \
	$dir_prep $dir_segment

# ----------------------------------------------------------------------------#
# Decode Audio                                                                #
# ----------------------------------------------------------------------------#

bash $dir_scripts/decode_chain.sh --word-alignment $word_alignment \
        --tag ${tag} --nj $nj --num-threads $num_threads \
        --ins-pen $word_ins_penalty --min_lmwt $min_lmwt --max_lmwt $max_lmwt \
	--segment $dir_segment/segments $dir_model $dir_segment/wav.scp $dir_segment/utt2spk \
       	$dir_segment/spk2utt $dir_graph $dir_out $dir_out/ctm_${tag}.ctm

echo "Info[`date`]: $(basename $0) done."
exit 0
