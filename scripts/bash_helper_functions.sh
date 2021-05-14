#!/bin/bash
set -eu
E_BAD_ARGS=65

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
#-----------------------------------------------------------------------------#

# -----------------------------------------------------------------------------
# Function: prompt_remove_dir

# If a 'dir' exists, does rm -r 'dir', else prints info message about
# non-existant directory

function prompt_remove_dir {
  if [ $# -ne 1 ]; then
    echo "Usage: $FUNCNAME <dir>"
    exit $E_BAD_ARGS
  fi
  dir=$1

  if [ -d $dir ]; then
    echo "Do you want to [rm -r] '$dir'? [y/n] then [ENTER]"
    read input
    if [ $input == "y" ]; then
      echo "INFO: Recursively removing '$dir'...";
      rm -r $dir
    elif [ $input == "n" ]; then
      echo "INFO: Please remove '$dir' manually to continue!"
      exit 0
    else
      echo "ERROR: Invalid choiced '$input'!"
      exit 1
    fi
  else
    echo "INFO: '$dir' does not exist!"
  fi
}

# -----------------------------------------------------------------------------
# Function: remove_dir

# If a dir exists, does rm -r dir, else prints info message about non-existant
# directory

function remove_dir {
  if [ $# -ne 1 ]; then
    echo "Usage: $FUNCNAME <dir>"
    exit $E_BAD_ARGS
  fi
  dir=$1

  if [ -d $dir ]; then
    echo "INFO: Recursively removing '$dir'...";
    rm -r $dir
  else
    echo "INFO: '$dir' does not exist!"
  fi
}

# -----------------------------------------------------------------------------
# Function: safe_remove_dir
#
# "Safe remove" because:
# - option to prompt a user before deleting a non-empty directory
# - does not use -f (which is necessary if a directory does not exist, otherwise
#   bash script exists due to set -eu.

function safe_remove_dir {
  if [ $# -ne 2 ]; then
    echo "Usage: $FUNCNAME <dir> <1/0 (prompt/don't prompt)>"
    exit $E_BAD_ARGS
  fi

  dir=$1
  prompt_before_remove=$2

  if [ -d $dir ]; then
    if [ "$(ls -A $dir)" ]; then
       echo "WARNING: '$dir' is not empty!"
       if [ $prompt_before_remove -eq 1 ]; then
         prompt_remove_dir $dir
       else
         remove_dir $dir
       fi
    else
      echo "INFO: '$dir' is empty. Removing..."
      rmdir $dir
    fi
  else
    echo "WARNING: '$dir' does not exist."
  fi
}

# -----------------------------------------------------------------------------
# Function: recursive_sort_file_content
#
# Find all files in a directory, and sort the content by the first column,
# with LC_ALL=C

function recursive_sort_file_content {
  if [ $# -ne 1 ]; then
    echo "Usage: $FUNCNAME <dir>"
    exit $E_BAD_ARGS
  fi

  dir=$1

  (
    export LC_ALL=C
    for fn in `find $dir -type f -iname "*"`
    do
      cat $fn | sort -k1,1 > $fn.tmp; mv $fn.tmp $fn
    done
  )
}

# -----------------------------------------------------------------------------
# Function: check_dirs_exist
#
# Check that all directories given as argument exists
function check_dirs_exist {
  if [ $# -eq 0 ]; then
    echo "Usage: $FUNCNAME <dir 0> [<dir 1> ... <dir n>]"
    exit $E_BAD_ARGS
  fi

  flag_dirs_missing=0
  missing_dirs=""
  for dir in "$@"
  do
    if [ ! -d "$dir" ]; then

      # Is it perhaps a symbolic link?
      if [ -L "$dir" ]; then
        echo "Warning: $dir is a symbolic link!"
      elif [ "$missing_dirs" = "" ]; then
        missing_dirs="\t$dir"
        flag_dirs_missing=1
      else
        missing_dirs="$missing_dirs\n\t$dir"
        flag_dirs_missing=1
      fi
    fi
  done

  if [ $flag_dirs_missing -eq 1 ]; then
    echo -e "Error: some dirs were not found.\n$missing_dirs" 2>&1
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Function: check_files_exist
#
# Check that all files given as argument exists
function check_files_exist {
  if [ $# -eq 0 ]; then
    echo "Usage: $FUNCNAME <file 0> [<file 1> ... <file n>]"
    exit $E_BAD_ARGS
  fi

  flag_files_missing=0
  missing_files=""
  for file in "$@"
  do
    if [ ! -f "$file" ]; then
      if [ "$missing_files" = "" ]; then
        missing_files="\t$file"
      else
        missing_files="$missing_files\n\t$file"
      fi
      
      flag_files_missing=1
    fi
  done

  if [ $flag_files_missing -eq 1 ]; then
    echo -e "Error: some files were not found.\n$missing_files" 2>&1
    exit 1
  fi
}

