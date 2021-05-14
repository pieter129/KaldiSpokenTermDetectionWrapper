#!/bin/bash
CXX=${CXX:-g++}
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
# Script installs and sets up Kaldii, applies Kaldi patches, and ensures that
# all the requisite packages for running a keyword spotting task using this 
# package, are installed.
#------------------------------------------------------------------------------#

sed -i "/export\sPATH=/d" ./conf/var.conf
sed -i "/export\sKALDI_ROOT=/d" ./conf/var.conf

. ./conf/var.conf || exit 1
. $dir_scripts/bash_helper_functions.sh

mkdir -p $KALDI_TRUNK
cd $KALDI_TRUNK

# Check if python_version is installed
find_python=`which $python_version`
if [ ! -f "$find_python" ]; then
  echo "Info: Installing Python3"
  sudo apt update
  sudo apt install software-properties-common
  sudo add-apt-repository ppa:deadsnakes/ppa
  sudo apt update
  sudo apt install $python_version
  echo "Info: Done installing Python3"
  which python3
else
  echo "Info: Using $find_python"	
fi

if [[ $install_kaldi == "true" ]]; then

  if [ -d "$KALDI_TRUNK/kaldi" ]; then # Check to insure kaldi is not already installed
    echo -e "Info: Looks like Kaldi is already installed\nRemove Kaldi or provide a different path to install Kaldi version required for Keyword Spotting."
    exit 1
  fi

  echo "Info: Downloading Kaldi"
  git clone https://github.com/kaldi-asr/kaldi.git kaldi --origin upstream
  # A specific version of Kaldi is required
  cd $KALDI_TRUNK/kaldi
  git checkout -b kws_811bd21a9 811bd21a9

  echo "Info: Installation starting"
  cd $KALDI_TRUNK/kaldi/tools
  
  sudo apt-get update
  sudo apt-get install g++ make automake autoconf unzip sox gfortran libtool subversion python2.7 zlib1g-dev gnuplot
  
  MKL_ROOT="${MKL_ROOT:-/opt/intel/mkl}"
  if [ ! -f "${MKL_ROOT}/include/mkl.h" ] && ! echo '#include <mkl.h>' | $CXX -I /opt/intel/mkl/include -E - &>/dev/null; then
     bash extras/install_mkl.sh
  fi

  if [ ! -d /opt/intel/mkl/ ]; then
    echo "Info: Kaldi's 'extras/install_mkl.sh' script was not successful"
    sudo apt-get install intel-mkl-64bit-2018.2-046
    echo "/opt/intel/lib/intel64"     >  /etc/ld.so.conf.d/mkl.conf
    echo "/opt/intel/mkl/lib/intel64" >> /etc/ld.so.conf.d/mkl.conf
    ldconfig
  fi
  
  bash extras/check_dependencies.sh
  make -j $nj CXXFLAGS="-O3 -DNDEBUG"
  cd $KALDI_TRUNK/kaldi/src
  CXXFLAGS="-O3 -DNDEBUG" ./configure --shared
  make -j clean depend
  make -j $nj ext || exit 1
  echo -e "Info: Done Installing Kaldi\n"
fi

if [ $install_f4de == "true" ]; then
  echo "Info: Installing other requirements"
  echo "Info: Downloading F4DE"
  cd $KALDI_TRUNK/kaldi/tools
  git clone https://github.com/usnistgov/F4DE
  cd $KALDI_TRUNK/kaldi/tools/F4DE
  echo "Info: Installing Prerequisites"

  sudo apt install cpanminus
  sudo apt-get update -y && sudo apt-get install cpanminus gnuplot libxml2 
  # ensure the rsync tool is available in your PATH (used in the installation process)
  # For more info, visit https://github.com/usnistgov/F4DE#-prerequisites
  sudo apt-get install sqlite3 expat libexpat1-dev icu-devtools libxml2-utils

  # Perl Modules
  sudo cpanm Text::CSV Text::CSV_XS Math::Random::OO::Uniform Math::Random::OO::Normal Statistics::Descriptive XML::Parser XML::SAX::Expat
  sudo cpanm Statistics::Descriptive::Discrete Statistics::Distributions DBI DBD::SQLite File::Monitor 
  sudo cpanm File::Monitor::Object Digest::SHA YAML Data::Dump XML::Simple
  sudo cpanm Audio::Wav

  sudo make install || exit 1

  echo "Info: Done Installing F4DE"
  echo "---------------------------------------------------"
  export PATH=$PATH:$KALDI_TRUNK/kaldi/tools/F4DE/bin
  [ ! -d "$HOME/local/bin" ] && echo "Error: Path '$HOME/local/bin' doesn't exist. Can't create softlink! Creating path" && mkdir -p $HOME/local/bin
  echo "Info: Adding softlink to KWSEval to $HOME/local/bin"
  #ln -s $KALDI_TRUNK/kaldi/tools/F4DE/KWSEval/tools/KWSEval/KWSEval.pl $HOME/local/bin/KWSEval
fi

if [ $apply_patches == "true" ]; then
  export KALDI_ROOT=$KALDI_TRUNK/kaldi
  echo "Applying Patches to $KALDI_ROOT"

  [ ! -d "$dir_patches" ] && echo "Error: $dir_patches directory not found" && exit
  bash $dir_scripts/apply_patches_to_kaldi.sh $dir_patches
fi

(echo "export PATH=\$PATH:\$HOME/local/bin:\$KALDI_TRUNK/kaldi/tools/F4DE/bin"
echo -e "export KALDI_ROOT=$KALDI_TRUNK/kaldi\nexport MODEL_ROOT=$dir_models") >> $dir_scripts/../conf/var.conf

awk '!visited[$0]++' $dir_scripts/../conf/var.conf > /tmp/conf.tmp
mv /tmp/conf.tmp $dir_scripts/../conf/var.conf

echo "---------------------------------------------------"
echo -e "Info: [`date`] - Installation Process Complete"
echo "Info: conf/var.conf has been updated with PATH and environmental variables:"
echo "   PATH=\$PATH:\$HOME/local/bin:\$KALDI_TRUNK/kaldi/tools/F4DE/bin"
echo "   KALDI_ROOT=\$KALDI_TRUNK/kaldi"
echo "   MODEL_ROOT=\$dir_models"
echo "---------------------------------------------------"
exit 1
