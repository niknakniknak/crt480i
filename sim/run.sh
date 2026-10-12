#!/bin/bash
# One bench run (Icarus Verilog 11+). Examples:
#   ./run.sh                              32 MHz, CLK_DIV 3, deflicker off, 1:1 height
#   ./run.sh -DDEFL=4 -DVHEIGHT=6         Full deflicker, stretched to 240 lines per field
#   ./run.sh -DCLK64 -DLUT2 -DMIDRESET    64 MHz, CLK_DIV 6, 2-clock palette, reset mid-line
#   ./run.sh -DCLK48 -DFRAC               48 MHz, CLK_DIV 4 + CLK_FRAC (4.5 clocks a pixel)
#   ./run.sh -DVTOTAL=500                 a 50 Hz source (625 half-lines)
# All defines are listed at the top of tb_crt_480i.sv; ./sweep.sh runs the whole matrix.
# A pass ends with "RESULT: PASS" ("... recovered" after a disturbance is also a pass).
cd "$(dirname "$0")"
iverilog -g2012 -o tb.vvp "$@" tb_crt_480i.sv ../rtl/crt_480i.sv && vvp -n tb.vvp | grep -a "^source\|kHz\|FAIL\|quiet\|recovered\|RESULT"
rm -f tb.vvp
