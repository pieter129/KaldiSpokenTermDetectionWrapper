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
# Master script for running a keyword spotting task and scoring the output.   
#------------------------------------------------------------------------------#

# -----------------------------------------------------------------------------#
# Initialise Variables                                                         #
# -----------------------------------------------------------------------------#

dir_scripts=$( dirname "$(realpath "$0")" )

decode=1
kws_search=1
skip_scoring=true

frame_subsampling_factor=3
kws_tag="KW000"
tag=`date -I`
word_ins_penalty=0.5

aligned_ctm=""
txt_list=""

dir_model=
dir_lang=
dir_graph=

# -----------------------------------------------------------------------------#
# Source Argument Parser Scripts                                               #
# -----------------------------------------------------------------------------#

source $dir_scripts/../conf/var.conf

[ ! -v "KALDI_ROOT" ] && echo "Error: \$KALDI_ROOT path does not exist!!" && exit
[ ! -v "MODEL_ROOT" ] && echo "Error: \$MODEL_ROOT path does not exist!!" && exit

dir_babel_root=$KALDI_ROOT/egs/babel/s5d
cd $dir_babel_root 

. utils/parse_options.sh
. $dir_scripts/bash_helper_functions.sh

# -----------------------------------------------------------------------------#
# Commandline Argument Info                                                    #
# -----------------------------------------------------------------------------#

if [ $# -lt 5 ]; then
  echo "Usage: $(basename $0) [options] <in:wav_list> <in:kwd_list> <in:lang> <out:dir_work> <out:kwd_results>"
  echo ""
  echo "Args: "
  echo "  wav_list	# List of wav files to search through (full paths)"
  echo "  kwd_list	# Keyword list to search for in wav files"
  echo "  lang		# Language used for Keyword search"
  echo "  dir_work	# Output directory where necessary resources are created"
  echo "  kwd_results	# Keyword results output directory"
  echo ""
  echo "Options:"
  echo "  --aligned-ctm		       <fn>     # Aligned ctm for all reference files ($aligned_ctm)"
  echo "  --frame-subsampling-factor   <int>    # Frame subsampling factor ($frame_subsampling_factor)"
  echo "  --kws-tag	               <tag>	# Keywords tag used ($kws_tag)"
  echo "  --txt-list		       <fn>	# Text file containing list of reference transcriptions"
  echo "					# corresponding with the wav files"
  echo "  					# Note: Transcripts should be one line 'paragraph'"
  echo " 					# Passing txt_list will enable scoring ($txt_list)"
  echo "  --word-ins-penalty	       <float>	# Word insertion penalty ($word_ins_penalty)"
  echo ""
  echo "  If one of the optional arguments below are empty, script will look for"
  echo "  a model matching the language provided"
  echo "  --dir-model	<dir>	# Model directory"
  echo "  --dir-graph	<dir>	# Graph directory"
  echo "  --dir-lang	<dir>	# Language directory"
  exit 1;
fi

# -----------------------------------------------------------------------------#
# Set Required Arguments                                                       #
# -----------------------------------------------------------------------------#

wav_list=`realpath $1`
kwd_list=`realpath $2`
lang=$3
dir_work=`realpath $4`
kwd_results=`realpath $5`
dir_decode=$dir_work/decode_${lang}

# -----------------------------------------------------------------------------#
# Set Required Arguments                                                       #
# -----------------------------------------------------------------------------#

# Check that, if any of the 3 are set, but not all three, raise an error. 
# To use different models, all 3 variables need to be set.

if [ -z $dir_model ] && [ -z $dir_lang ] && [ -z $dir_graph ]; then
  if [ $lang == "afr" ]; then
    dir_model=$MODEL_ROOT/kaldi_afr_8k_sasal_m1.0
    dir_lang=$dir_model/data/sasal_eval
    dir_graph=$dir_model/exp/chain_cleaned/tdnn1g_sp/graph_sasal_eval

  elif [ $lang == "sot" ]; then
    dir_model=$MODEL_ROOT/kaldi_sot_8k_sasal_m1.0
    dir_lang=$dir_model/data/sasal_eval
    dir_graph=$dir_model/exp/chain_cleaned/tdnn1g_sp/graph_sasal_eval

  elif [ $lang == "zul" ]; then
    dir_model=$MODEL_ROOT/kaldi_zul_8k_sasal_m1.0
    dir_lang=$dir_model/data/sasal_eval
    dir_graph=$dir_model/exp/chain_cleaned/tdnn1g_sp/graph_sasal_eval

  else
    echo "Error: Could not find a model matching '$lang' provided"
    exit
  fi
else
  error_flag=0
  if [ -z $dir_model ]; then
    echo "Error: [dir_model] is not set!" 2>&1
    error_flag=1
  fi
  if [ -z $dir_graph ]; then
    echo "Error: [dir_graph] is not set!" 2>&1
    error_flag=1
  fi
  if [ -z $dir_lang ]; then
    echo "Error: [dir_lang] is not set!" 2>&1
    error_flag=1
  fi
  [ $error_flag -eq 1 ] && echo "Error: Some variables are not set" 2>&1 && exit
fi

# -----------------------------------------------------------------------------#
# Check Scoring Option                                                         #
# -----------------------------------------------------------------------------#

if [ ! -z "$aligned_ctm" ]; then
  if [ -f "$aligned_ctm" ]; then
    skip_scoring=false
  else
    echo "Error: [$aligned_ctm] doesn't exist" 2>&1 && exit
  fi
  
elif [ ! -z "$txt_list" ]; then
  if [ -f "$txt_list" ]; then
    echo "Info: Checking that reference txt file exists in wav list"
    txt_line=`head -n 1 $txt_list`
    file_path=$(basename -- "$txt_line")
    fbname="${file_path%.*}"
    audio_file=`grep "/$fbname.wav" $wav_list`

    [ ! -v "audio_file" ] && echo "Error: Wav file corresponding to reference text file ($file_path) not in wav list!!" && exit
    echo "Info: Text list passed --> Keyword scoring enabled"
  
    skip_scoring=false

  else
    echo "Error: [$txt_list] doesn't exist" 2>&1 && exit
  fi
fi

# -----------------------------------------------------------------------------#
# Create KWS resources for KWS SEARCH                                          #
# -----------------------------------------------------------------------------#

if [ $kws_search -eq 1 ]; then
  
  step="kws_search"
  local_work=$dir_work/$step
  dir_data=$local_work/data
  
  safe_remove_dir $local_work 0
  mkdir -p $dir_data
   
  if [ $decode -eq 1 ]; then
    echo "--------------------------------------------------------------------"
    echo "Info: Start decoding"
    echo "--------------------------------------------------------------------"
    
    safe_remove_dir $dir_decode 1
    mkdir -p $dir_decode
    echo "bash $dir_scripts/simple_decode_chain.sh $dir_model $dir_graph $wav_list $dir_decode/decode"
    
    bash $dir_scripts/simple_decode_chain.sh $dir_model $dir_graph $wav_list $dir_decode/decode
    cp $dir_decode/decode/segmentation/segments $dir_data/segments
 
  else
    cp $dir_decode/decode/segmentation/segments $dir_data/segments
  fi

  echo "--------------------------------------------------------------------"
  echo "Info: Creating hand selected keywords with ID's"
  echo "--------------------------------------------------------------------"
 
#  no_kwds=`wc -l $kwd_list | awk '{print $1}'`
#  if [[ $no_kwds -eq 1 ]]; then
#    head -n1 $kwd_list >> $kwd_list
#  fi

  counter=1
  while read line; do
    kw_count=`python3 -c 'print("{:05d}".format('$counter'))'`
    counter=$((counter+1))
    echo -e "$kws_tag-$kw_count\t$line" | tee -a $local_work/kwds
  done < $kwd_list

  if [ $skip_scoring == false ]; then
    echo "--------------------------------------------------------------------"
    echo "Info: Create a keyword list, Experimental Control File (ECF) and RTTM file"
    echo "--------------------------------------------------------------------"
      

    if [ ! -f "$aligned_ctm" ]; then
      echo "Info: Create fake ctm from text file"
      ctm=$dir_data/text_data.ctm
      while read text; do
        fbname=`echo "$text" | awk -F "/" '{print $NF}' | sed "s/.txt//g"`
        audio_file=`grep "$fbname.wav" $wav_list`
        duration=`sox --i -D $audio_file`
        python3 $dir_scripts/text_to_ctm.py $text $fbname $duration $ctm
      done < $txt_list
    else
      ctm=$aligned_ctm
    fi

    perl $dir_scripts/prep_kw_resources.pl ${tag} $local_work $wav_list $local_work/kwds ${ctm}:ctm
  
    rttm_file=$local_work/${tag}.rttm
    ecf_file=$local_work/${tag}.ecf.xml
    kwlist_file=$local_work/${tag}.kwlist.xml
  else
    perl $dir_scripts/prep_kw_resources.pl ${tag} $local_work $wav_list $local_work/kwds

    ecf_file=$local_work/${tag}.ecf.xml
    kwlist_file=$local_work/${tag}.kwlist.xml
  fi
  
  if [ ! -L $dir_decode/decode/decoded_${tag}/final.mdl ]; then
     [ ! -f "$dir_graph/../final.mdl" ] && echo "Error: 'final.mdl' file not where its supposed to have been!!" && exit
     ln -s $dir_graph/../final.mdl $dir_decode/decode/decoded_${tag}/final.mdl
  fi
  
  echo "--------------------------------------------------------------------"
  echo "Info: Setup KWS data directory for Kaldi"
  echo "--------------------------------------------------------------------"
  
  if [ $skip_scoring == true ]; then
    bash local/kws_setup.sh $ecf_file $kwlist_file $dir_lang $dir_data
  else
    bash local/kws_setup.sh --rttm-file $rttm_file  $ecf_file $kwlist_file $dir_lang $dir_data
  fi
  
  echo "--------------------------------------------------------------------"
  echo "Info: Run keyword search"
  echo "--------------------------------------------------------------------"
  
  bash local/kws_search.sh --skip-scoring $skip_scoring --word-ins-penalty $word_ins_penalty \
	  --frame-subsampling-factor $frame_subsampling_factor --lang $lang $dir_lang $dir_data \
	  $dir_decode/decode/decoded_${tag}/decode_${tag}
  
  while read line; do
    parts=($(echo $line | tr "\t" "\n"))
    sed -i "s/kwid=\"${parts[0]}\"/kwid=\"${parts[0]}\" kwd_text=\"${parts[1]}\"/g" \
	    $dir_decode/decode/decoded_${tag}/decode_${tag}/kws_9/kwslist.xml
  done < $local_work/kwds
  
  cp $dir_decode/decode/decoded_${tag}/decode_${tag}/kws_9/kwslist.xml $kwd_results
  output_file=`realpath $kwd_results`
  wc $output_file

  echo "--------------------------------------------------------------------"
  echo "KWSLIST RESULTS --> $output_file"
  if [ $skip_scoring == false ]; then
    echo "KWS SCORING RESULTS --> $dir_decode/decode/decoded_${tag}/decode_${tag}/kws_9/bsum.txt"
    echo "KWS SCORING STATS --> $dir_decode/decode/decoded_${tag}/decode_${tag}/kws_9/metrics.txt"
  fi
  echo "--------------------------------------------------------------------"
  echo "[`date`]: Done with [$step]"
fi
