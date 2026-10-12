#!/bin/bash
# mutants.sh: each mutant is the module with one deliberate defect; every run must FAIL.
# The mutants are made here from ../rtl/crt_480i.sv (one exact text substitution each; the script
# stops if a substitution no longer matches), into MUT_DIR (default /tmp/crt480i_mut).
#   m1 read before write   m2 sync while unlocked   m3 picture while unlocked
#   m4 no bottom clamp     m5 no VSync-loss unlock  m6 no frame-rate window
#   m7 field flag inverted m8 wrong lines per field
#   m9 output line period from 525 half-lines (tlo), at 50 Hz
#   m10 Bresenham at 525 half-lines, at 50 Hz      m11 visible window not moved for a slower frame
#   m12 no 525 floor (523 at 60.1 Hz)              m13 window up to 63 Hz again (62.9 Hz, a 16.51 kHz line, locks)
cd "$(dirname "$0")"
S=${MUT_DIR:-/tmp/crt480i_mut}
mkdir -p $S
python3 - ../rtl/crt_480i.sv $S <<'PY' || exit 1
import sys
src = open(sys.argv[1]).read()
M = {
 'm1':  ("m_src    <= ta + hsrc * tls + (tls << 1);", "m_src    <= ta + hsrc * tls + (tls << 1) - (tls << 5);"),
 'm2':  ("hs_out = run & hs_o;", "hs_out = hs_o;"),
 'm3':  ("r_out  = run ? r_o  : 8'd0;", "r_out  = r_o;"),
 'm4':  ("v_hi     <= hl_n[10:1] - out_lines;", "v_hi     <= 10'd400;"),
 'm5':  ("end else if( fcnt > TF_MAX )", "end else if( 1'b0 )"),
 'm6':  ("fcnt >= TF_MIN && fcnt <= TF_MAX &&", "1'b1 &&"),
 'm7':  ("f_o  <= fpar;", "f_o  <= ~fpar;"),
 'm8':  ("rs_c  <= f_vfull ? pos_0r[16 +: SW] : {{SW-1{1'b0}}, fpar};", "rs_c  <= f_vfull ? pos_0r[16 +: SW] : {{SW-1{1'b0}}, ~fpar};"),
 'm9':  ("dv_d <= hl_n;", "dv_d <= 11'd525;"),
 'm10': ("{12'd0, hl_n}", "23'd525", 3),            # all three Bresenham terms
 'm11': ("v_add    <= (hl_n - 11'd525) >> 2;", "v_add    <= 10'd0;"),
 'm12': ("hl_f < 14'd262 ? 11'd525 :", "hl_f < 14'd2 ? 11'd525 :"),
 'm13': ("TF_MIN = (TL_MIN * 525 + 1) / 2,", "TF_MIN = CLK_HZ / 63,"),
}
for m, (a, b, *n) in M.items():
    n = n[0] if n else 1                           # how many times it must match
    if src.count(a) != n: sys.exit(f"{m}: substitution does not match the module {n} time(s): {a}")
    open(f"{sys.argv[2]}/{m}.sv", "w").write(src.replace(a, b))
PY
one() { m=$1; shift; iverilog -g2012 -o $S/$m.vvp "$@" tb_crt_480i.sv $S/$m.sv > $S/$m.log 2>&1 && vvp -n $S/$m.vvp >> $S/$m.log 2>&1
        rm -f $S/$m.vvp
        echo "$m ($*): $(grep -a 'RESULT' $S/$m.log) | $(grep -a FAIL $S/$m.log | head -1 | cut -c1-90)"; }
export -f one; export S
xargs -P "${JOBS:-$(nproc)}" -L 1 bash -c 'one "$@"' _ > $S/mutants.txt <<'L'
m1 -DDEFL=2
m2
m3
m4 -DVHEIGHT=6 -DVOFF=15
m5 -DVSLOSS
m6 -DFAST
m7
m8
m9 -DVTOTAL=500
m10 -DVTOTAL=500
m11 -DVTOTAL=500
m12
m13 -DHTOTAL=610 -DVTOTAL=417 -DNOLOCK
L
sort -V $S/mutants.txt
