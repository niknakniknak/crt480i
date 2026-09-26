#!/bin/bash
# The whole test matrix, several runs at a time (Icarus Verilog 11+). One line per run in
# sweep.txt; each run's full log is in log/<name>.log. Every line should end in RESULT: PASS.
cd "$(dirname "$0")"
mkdir -p log
one() {
    n=$1; shift
    iverilog -g2012 -o log/$n.vvp "$@" tb_crt_480i.sv ../rtl/crt_480i.sv > log/$n.log 2>&1 &&
        vvp -n log/$n.vvp >> log/$n.log 2>&1
    rm -f log/$n.vvp
    echo "$n: $(grep -a 'recovered\|RESULT' log/$n.log | tr '\n' ' ')"
}
export -f one
xargs -P "${JOBS:-$(nproc)}" -L 1 bash -c 'one "$@"' _ > sweep.txt <<'L'
c3_d0
c3_d4h6 -DDEFL=4 -DVHEIGHT=6
c3_d1h1R -DDEFL=1 -DVHEIGHT=1 -DMIDRESET
c3_d2R -DDEFL=2 -DMIDRESET
c3_sk -DSKEW -DDEFL=2
c3_d3h4 -DDEFL=3 -DVHEIGHT=4
c6_d0L2 -DCLK64 -DLUT2
c6_d2h3L2R -DCLK64 -DLUT2 -DDEFL=2 -DVHEIGHT=3 -DMIDRESET
c6_d3 -DCLK64 -DDEFL=3
c6_d3h5 -DCLK64 -DDEFL=3 -DVHEIGHT=5
c4_pk -DCLK48 -DPACKED -DDEFL=4
c4_pkL2 -DCLK48 -DPACKED -DLUT2 -DDEFL=1
c5_d2h2 -DCLK48 -DCDIV5 -DDEFL=2 -DVHEIGHT=2
fr_d0 -DCLK48 -DFRAC
fr_d4h6 -DCLK48 -DFRAC -DDEFL=4 -DVHEIGHT=6
fr_d3L2R -DCLK48 -DFRAC -DLUT2 -DDEFL=3 -DMIDRESET
fr_d1h2 -DCLK48 -DFRAC -DDEFL=1 -DVHEIGHT=2
fr_sk_d2 -DCLK48 -DFRAC -DSKEW -DDEFL=2
nar_d0 -DNARROW
nar_d2h4 -DNARROW -DDEFL=2 -DVHEIGHT=4
wide_d0 -DWIDE
wide_d4 -DWIDE -DDEFL=4
tall_d0 -DTALL
tall_d0h1 -DTALL -DVHEIGHT=1
tall_d2h1 -DTALL -DDEFL=2 -DVHEIGHT=1
tall_d3h3 -DTALL -DDEFL=3 -DVHEIGHT=3
tall_c6d1h6 -DTALL -DCLK64 -DDEFL=1 -DVHEIGHT=6
off_h7v-5 -DHOFF=7 -DVOFF=-5
off_d2h6v15 -DDEFL=2 -DVHEIGHT=6 -DVOFF=15
off_h6v-16 -DVHEIGHT=6 -DVOFF=-16 -DHOFF=-32
off_c6d1v15 -DCLK64 -DDEFL=1 -DVOFF=15 -DHOFF=31
vsl_d0 -DVSLOSS
vsl_fr_d4 -DVSLOSS -DCLK48 -DFRAC -DDEFL=4
vsl_c6_d2 -DVSLOSS -DCLK64 -DDEFL=2
fast -DFAST
menu_d2 -DMENUCHG -DDEFL=2
menu_c6h4 -DMENUCHG -DCLK64 -DVHEIGHT=4 -DDEFL=1
fast_c6 -DFAST -DCLK64
L
sort -o sweep.txt sweep.txt; cat sweep.txt
