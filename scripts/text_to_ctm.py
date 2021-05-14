#!/usr/bin/env python3

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
#-------------------------------------------------------------------------------#

import argparse

def ctm_to_text(args):
    
    text = open(args.text_file).read().splitlines()
    name = args.ref_name
    duration= args.duration
    print("Audio file duration length:",duration)
    tolerance = duration * .001
    print("Tolerance:",tolerance)
    
    words = text[0].split(" ")
    
    splitter = (duration - tolerance) / len(words)
    print("Number of words in text file:",len(words))
    
    new_ctm = ""
    start = 0.00
     
    for word in words:
        if word != '':
            new_ctm += name + ' 1 ' + str('{:.2f}'.format(start))+ ' ' +  str('{:.2f}'.format(start + splitter)) + ' ' + word + ' 1\n'
            start += splitter
    open(args.output_ctm,'a').write(new_ctm)

if __name__ == "__main__":
    
    parser = argparse.ArgumentParser(description='Convert text to Fake ctm format.')
    parser.add_argument('text_file', type=str, help='Input reference text file')
    parser.add_argument('ref_name', type=str, help='Reference name')
    parser.add_argument('duration', type=float, help='Reference audio file duration')
    parser.add_argument('output_ctm', type=str, help='Output fake ctm file')

    args = parser.parse_args()
    ctm_to_text(parser.parse_args())
