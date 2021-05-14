##!/bin/bash
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

# The creation of this script was informed by:
#     local/chain/run_ivector_common.sh
#     steps/nnet/decode.sh - shared under Apache 2.0 Licence  
#-------------------------------------------------------------------------------#

# ------------------------------------------------------------------------------#
# Initialise Variables                                                          #
# ------------------------------------------------------------------------------#

dir_scripts=`dirname $0`

chain_model="chain_cleaned/tdnn1g_sp"
decode_mbr=true
ins_pen=	# Will be set to wip if not set
max_lmwt=9
min_lmwt=9
nj=1
num_threads=2
segment=
skip_scoring=true
tag=`date -I`
wip=0.5
word_alignment=true

# -----------------------------------------------------------------------------#
# Source Argument Parser Scripts                                               #
# -----------------------------------------------------------------------------#

source $dir_scripts/../conf/var.conf

[ ! -v "KALDI_ROOT" ] && echo "Error: \$KALDI_ROOT path does not exist!!" && exit
decode_script=$KALDI_ROOT/egs/wsj/s5/steps/nnet/decode.sh
babel_root_dir=$KALDI_ROOT/egs/babel/s5d

echo "$0 $@"  # Print the command line for logging

. $dir_scripts/bash_helper_functions.sh
. $babel_root_dir/utils/parse_options.sh || exit 1

# -----------------------------------------------------------------------------#
# Commandline Argument Info                                                    #
# -----------------------------------------------------------------------------#

if [ $# != 7 ]; then
  echo "Usage: $(basename $0) [options] <in:dir_model> <in:wav.scp> <in:utt2spk> <in:spk2utt> <in:dir_graph> <out:dir_work> <out:fn_ctm>"
  echo "Args: "
  echo "  dir_model		# Model directory (contains exp, steps, utils, etc)"
  echo "  wav.scp		# Kaldi wav.scp file (format: utt[space]full_path_to_wav)"
  echo "  utt2spk		# Kaldi utt2spk file (format: utt[space]spk)"
  echo "  spk2utt		# Kaldi spk2utt file (format: spk[space]utt1[space]utt2...)"
  echo "  dir_graph		# Graph directory (contains HCLG.fst, phones.txt, etc)."
  echo "  dir_work		# Working directory (\$dir_work/[feat_\$tag|data_\$tag|decode_\$tag] will be removed)"
  echo "  fn_ctm		# Kaldi ctm containing decoded output for wav.scp"
  echo ""
  echo "Options: "
  echo "  --nj <num-jobs>       # Number of parallel jobs to run ($nj)"
  echo "  --tag <name>          # Name of the data, eg dev10h.uem ($tag)"
  echo "  --segment <segments>  # Kaldi segments file ($segment)"
  echo "  --chain-model <type>	# Either chain_cleaned/tdnn1g_sp or chain_cleaned/tdnn_sp. ($chain_model)"
  echo "  --num-threads <nt>    # Number of threads to use per process ($num_threads)"
  echo "  --min-lmwt <weight>   # Minimum language modeling weight ($min_lmwt)"
  echo "  --max-lmwt <weight>   # Maximum language modeling weight ($max_lmwt)"
  echo "  --ins-pen <wip>       # Word insertion penalty ($wip)"
  echo "  --decode-mbr <boolean>	# Decode mbr ($decode_mbr)"
  echo "  --word-alignment <boolean>	# Lattice to ctm word alignment ($word_alignment)"
  exit 1;
fi

# -----------------------------------------------------------------------------#
# Set Required Arguments                                                       #
# -----------------------------------------------------------------------------#

dir_model=`realpath $1`
wav_scp=`realpath $2`
utt2spk=`realpath $3`
spk2utt=`realpath $4`
dir_graph=`realpath $5`
dir_work=`realpath $6`
fn_ctm_out=`realpath $7`

if [ -e "$segment" ]; then
  segment=`realpath $segment`
fi

# -----------------------------------------------------------------------------#
# Preliminary Checks                                                           #
# -----------------------------------------------------------------------------#

# Check that all the required directories exist
check_dirs_exist $dir_model $dir_graph 

# Check that all the required files exist
check_files_exist $wav_scp $utt2spk $spk2utt $dir_model/conf/common_vars.sh \
  $dir_model/lang.conf $dir_model/exp/$chain_model/final.mdl $dir_graph/HCLG.fst \
  $dir_model/utils/copy_data_dir.sh $dir_model/steps/make_mfcc_pitch_online.sh \
  $dir_model/steps/compute_cmvn_stats.sh $dir_model/utils/fix_data_dir.sh \
  $dir_model/utils/data/limit_feature_dim.sh \
  $dir_model/steps/online/nnet2/extract_ivectors_online.sh \
  $decode_script $babel_root_dir/local/lattice_to_ctm.sh

num_wavs=`cat $wav_scp | wc -l`
if [ $num_wavs -lt $nj ]; then
  echo "[`date`] Warning: less than '$nj' regular files in '$wav_scp'. Reducing number of jobs to '$num_wavs'."
  nj=$num_wavs
fi

cd $dir_model
. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;

# -----------------------------------------------------------------------------#
# Setup                                                                        #
# -----------------------------------------------------------------------------#

safe_remove_dir $dir_work/feat_${tag} 0
safe_remove_dir $dir_work/data_${tag} 0
safe_remove_dir $dir_work/data_${tag}_hires 0
safe_remove_dir $dir_work/data_${tag}_hires_nopitch 0
safe_remove_dir $dir_work/decode_${tag} 0
safe_remove_dir $dir_work/log_${tag} 0

mkdir -p $dir_work/data_${tag} $dir_work/decode_${tag} $dir_work/feat_${tag} $dir_work/log_${tag}

cp $wav_scp $dir_work/data_${tag}/wav.scp
cp $utt2spk $dir_work/data_${tag}/utt2spk
cp $spk2utt $dir_work/data_${tag}/spk2utt

dataset_dir=$dir_work/data_${tag}
decode_chain=$dir_work/decode_${tag}
feat_dir=$dir_work/feat_${tag}
log_dir=$dir_work/log_${tag}

if [ -z "$segment" ]; then
  # Unset
  echo "Info: not using segments!"
else
  echo "Info: using segments from '$segment'"
  cp $segment $dir_work/data_${tag}/segments
fi

# -----------------------------------------------------------------------------#
# Feature Extraction and Decoding                                              #
# -----------------------------------------------------------------------------#

graph_name=`echo $dir_graph | awk -F '/' '{print $NF}'`
d_graph_chain="exp/$chain_model/$graph_name"

echo "$graph_name"
echo "$d_graph_chain"

if [ -f exp/$chain_model/final.mdl ]; then
  if [ -f $dir_graph/HCLG.fst ]; then

    if  [ ! -f ${dataset_dir}_hires/.mfcc.done ]; then
      dataset=$(basename $dataset_dir)
      echo ---------------------------------------------------------------------
      echo "Preparing ${tag} MFCC features in  ${dataset_dir}_hires on "`date`
      echo ---------------------------------------------------------------------
      if [ ! -d ${dataset_dir}_hires ]; then
	utils/copy_data_dir.sh $dir_work/data_${tag} ${dataset_dir}_hires
      fi

      mfccdir=$feat_dir
      steps/make_mfcc_pitch_online.sh --nj $nj --mfcc-config conf/mfcc_hires.conf \
	  --cmd "$train_cmd" ${dataset_dir}_hires $log_dir $mfccdir;
      steps/compute_cmvn_stats.sh ${dataset_dir}_hires $log_dir $mfccdir;
      utils/fix_data_dir.sh ${dataset_dir}_hires;

      utils/data/limit_feature_dim.sh 0:39 \
	${dataset_dir}_hires ${dataset_dir}_hires_nopitch || exit 1;
      steps/compute_cmvn_stats.sh \
	${dataset_dir}_hires_nopitch $log_dir $mfccdir || exit 1;
      utils/fix_data_dir.sh ${dataset_dir}_hires_nopitch
      touch ${dataset_dir}_hires/.mfcc.done
      touch ${dataset_dir}_hires/.done
    fi

    if [ ! -f $dir_work/feat_${tag}/ivectors/.done ] ; then
      steps/online/nnet2/extract_ivectors_online.sh --cmd "$decode_cmd" --nj $nj \
	${dataset_dir}_hires_nopitch exp/nnet3_cleaned/extractor $dir_work/feat_${tag}/ivectors/ || exit 1;
      touch $dir_work/feat_${tag}/ivectors/.done
    fi
    printf 'Info: Features complete.'

    extras=""
    if [ $num_threads -gt 0 ]; then
      extras="$extras --num-threads $num_threads"
    fi

    if [ ! -f $decode_chain/.done ]; then
      $decode_script $extras --nj $nj --cmd "$decode_cmd" --acwt 1.0 --post-decode-acwt 10.0 \
	    --beam $dnn_beam --lattice-beam $dnn_lat_beam \
	    --skip-scoring $skip_scoring  \
	    --online-ivector-dir $dir_work/feat_${tag}/ivectors \
	    $d_graph_chain ${dataset_dir}_hires $decode_chain exp/$chain_model | tee $decode_chain/decode.log

      touch $decode_chain/.done
    fi
    printf 'Info: Decoding Complete.'

    # Generate ctm
    echo "Info: generating ctm"

    if [ ! -z $ins_pen ]; then
      export wip=$ins_pen
    fi

    bash $babel_root_dir/local/lattice_to_ctm.sh --decode-mbr $decode_mbr --min-lmwt $min_lmwt \
      --word-alignment $word_alignment --max-lmwt $max_lmwt --cmd "run.pl" --beam 7 --stage 0 \
      --word-ins-penalty $wip --dir-model exp/$chain_model ${dataset_dir} $d_graph_chain $decode_chain

    cp -v $decode_chain/score_${min_lmwt}/data_${tag}.ctm $fn_ctm_out
    wc $fn_ctm_out
  else
    echo "Warning: chain model exists, but '$d_graph_chain/HCLG.fst' does not. Skipping chain model decoding."
  fi
fi

echo "Info: Done!"
