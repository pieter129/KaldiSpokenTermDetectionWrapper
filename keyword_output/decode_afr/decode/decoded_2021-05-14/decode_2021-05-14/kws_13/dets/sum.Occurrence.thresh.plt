## GNUPLOT command file
set terminal postscript color
set style data lines
set title 'Threshold Plot for Occurrence'
set xlabel 'Detection Score'
set grid
set size ratio 0.85
plot [0.999999:1.000001]  \
  '/home/pieteruys/work/kws/github_kws/kws_test/bitbucket_vs_kws/keyword_output/decode_afr/decode/decoded_2021-05-14/decode_2021-05-14/kws_13/dets/sum.Occurrence.dat.1' using 1:4 title 'PMiss' with lines lt 2, \
  '/home/pieteruys/work/kws/github_kws/kws_test/bitbucket_vs_kws/keyword_output/decode_afr/decode/decoded_2021-05-14/decode_2021-05-14/kws_13/dets/sum.Occurrence.dat.1' using 1:5 title 'PFA' with lines lt 3, \
  '/home/pieteruys/work/kws/github_kws/kws_test/bitbucket_vs_kws/keyword_output/decode_afr/decode/decoded_2021-05-14/decode_2021-05-14/kws_13/dets/sum.Occurrence.dat.1' using 1:6 title 'TWV' with lines lt 4, \
  1 title 'Actual TWV 1.000' with lines lt 5, \
  '/home/pieteruys/work/kws/github_kws/kws_test/bitbucket_vs_kws/keyword_output/decode_afr/decode/decoded_2021-05-14/decode_2021-05-14/kws_13/dets/sum.Occurrence.dat.2' using 1:2 title 'Max TWV 1.000, scr 1.000' with points lt 6
