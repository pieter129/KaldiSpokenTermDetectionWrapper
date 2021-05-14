#!/bin/bash

[ ! -v "KALDI_ROOT" ] && echo "Error: \$KALDI_ROOT path does not exist!!" && exit

if [ $# -lt 1 ]; then
  echo "Usage: $(basename $0) <in:dir_patches>"
  echo "Args: "
  echo "  dir_patches	# Path to patches directory"
  exit 1;
fi

dir_patches=`realpath $1`

echo "Info: Applying patches to Kaldi files"

patch $KALDI_ROOT/egs/babel/s5d/cmd.sh -i $dir_patches/cmd.patch
patch $KALDI_ROOT/egs/babel/s5d/local/kws_search.sh -i $dir_patches/kws_search.patch
patch $KALDI_ROOT/egs/babel/s5d/path.sh -i $dir_patches/path.patch
patch $KALDI_ROOT/egs/babel/s5d/local/search_index.sh -i $dir_patches/search_index.patch
patch $KALDI_ROOT/egs/wsj/s5/steps/nnet/decode.sh -i $dir_patches/decode.patch
patch $KALDI_ROOT/egs/babel/s5d/local/kws_score_f4de.sh -i $dir_patches/kws_score_f4de.patch
patch $KALDI_ROOT/egs/babel/s5d/local/lattice_to_ctm.sh -i $dir_patches/lattice_to_ctm.patch
patch $KALDI_ROOT/egs/babel/s5d/local/kws_data_prep.sh -i $dir_patches/kws_data_prep.patch

echo "Info[`date`]: $(basename $0) done."
exit
