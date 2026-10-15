// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Watson. GPL v2 or later.
// Self-checking bench for crt_480i against a medium-res reference raster (640x416, 512x384
// active by default). Defines, all optional:
//   clock    CLK64 (CLK_DIV 6) | CLK48 (CLK_DIV 4) [+ CDIV5 | FRAC] | default 32 MHz (CLK_DIV 3)
//   source   NARROW (448 wide) | WIDE (544, past W_MAX) | TALL (448 lines) | FAST (70 Hz: must
//            never lock) | SKEW (changes off the pixel enable)
//   rate     VTOTAL=n, HTOTAL=n (frame rate: VTOTAL=500 is 50 Hz, 456 54.8, 435 57.5, 417 59.95;
//            HTOTAL=610 VTOTAL=418 62.75) | NOLOCK (that rate is outside the window: must never lock)
//            | RATECHG (VTOTAL changes to 500, 50 Hz, mid-run: it must unlock and relock at 625)
//   module   DEFL=0..4, VHEIGHT=0..6, HOFF=n, VOFF=n, LUT2, PACKED (LUT_EXT=0),
//            HLMIN=n (HL_MIN, default 525), VISL=n (VIS_LINES, default 240)
//   events   MIDRESET (source reset mid-line) | VSLOSS (the source VSync stops, then returns) |
//            MENUCHG (Height and V-Position change mid-run, then change back) |
//            LJIT (every other frame, the line before the last active one is 1 clk longer)
//   output   DUMP="file" (every locked output pixel, for bit-exact comparisons)
`timescale 1ns/1ps
`ifndef DEFL
`define DEFL 0
`endif
`ifndef VHEIGHT
`define VHEIGHT 0
`endif
`ifndef HOFF
`define HOFF 0
`endif
`ifndef VOFF
`define VOFF 0
`endif
`ifndef HLMIN
`define HLMIN 525
`endif
`ifndef VISL
`define VISL 240
`endif
module tb;

// ---------------------------------------------------------------- clock and module timing
reg clk = 0;
`ifdef CLK64
always #7.8125 clk = ~clk;
localparam integer CLKHZ = 64_000_000, PIXDIV = 3, CDIV = 6, FRAC = 0, HST = 111, HSP = 50;
`elsif CLK48
always #10.4167 clk = ~clk;
`ifdef CDIV5
localparam integer CLKHZ = 48_000_000, PIXDIV = 2, CDIV = 5, FRAC = 0, HST = 87,  HSP = 45;
`elsif FRAC
localparam integer CLKHZ = 48_000_000, PIXDIV = 2, CDIV = 4, FRAC = 1, HST = 111, HSP = 50;
`else
localparam integer CLKHZ = 48_000_000, PIXDIV = 2, CDIV = 4, FRAC = 0, HST = 158, HSP = 56;
`endif
`else
always #15.625 clk = ~clk;
localparam integer CLKHZ = 32_000_000, PIXDIV = 1, CDIV = 3, FRAC = 0, HST = 111, HSP = 50;
`endif
localparam integer CDIV_MAX = CDIV + FRAC;          // longest output pixel, clocks

// ---------------------------------------------------------------- reference raster
// 640x416 total, 512x384 active, sync at h 544-607 / v 392-399: a typical 25 kHz medium-res
// timing, one pixel every PIXDIV+1 clocks.
`ifdef NARROW
localparam integer HACT = 448;
`elsif WIDE
localparam integer HACT = 544;
`else
localparam integer HACT = 512;
`endif
`ifdef TALL
// 52 Hz; Height 200 then shrinks (step > 1). The ring holds the backlog at the first active line:
// active lines - output lines x (source line rate / output line rate) + 3 = 448 - 200 x 1.6 + 3,
// about 131 lines, so this source needs a bigger RING than the default 96.
localparam integer VACT = 448, VTOT0 = 480, RINGN = 160;
`elsif FAST
localparam integer VACT = 320, VTOT0 = 356, RINGN = 96;   // 70 Hz: out of the lock window
`define NOLOCK
`else
localparam integer VACT = 384, VTOT0 = 416, RINGN = 96;   // 60.1 Hz
`endif
`ifdef VTOTAL
localparam integer VTOT = `VTOTAL;
`else
localparam integer VTOT = VTOT0;
`endif
`ifdef HTOTAL
localparam integer HTOT = `HTOTAL;
`else
localparam integer HTOT = 640;
`endif
localparam integer HS0 = HACT + 32, VS0 = VACT + 8;
integer vtot = VTOT;                                // RATECHG changes it
localparam integer WOUT = HACT > 512 ? 512 : HACT;  // pixels per output line
// active lines per field, and the first active line (centred, offset, then clamped)
localparam integer NOUT0 = `VHEIGHT ? 192 + 8*`VHEIGHT : VACT/2;
localparam integer NOUT  = NOUT0 > `VISL ? `VISL : NOUT0;
// Half-lines a frame expected (the rule in the module header, worked here in real numbers): lines a
// field L = floor(15075 / fps + 11), HL = 2L + 1, at least HL_MIN. The extra lines of a slower frame
// go half above the visible window: it starts floor((HL - 525) / 4) lines lower (higher below 525).
integer TFS, HLX, VRAW, VEXP;                                   // source frame (clk), expected
real    fps_s, lx;
task expect_rate; begin
    TFS   = HTOT * vtot * (PIXDIV + 1);
    fps_s = 1.0 * CLKHZ / TFS;
    lx    = 15075.0 / fps_s + 11.0;
    HLX   = 2 * $rtoi(lx) + 1;
    if( HLX < `HLMIN ) HLX = `HLMIN;
    VRAW  = 21 + (HLX >= 525 ? (HLX - 525)/4 : -((525 - HLX + 3)/4)) + (`VISL - NOUT)/2 + `VOFF;
    VEXP  = VRAW < 6 ? 6 : VRAW > (HLX-1)/2 - NOUT ? (HLX-1)/2 - NOUT : VRAW;
    $display("source %.3f Hz (%0d clk), 15075/fps+11 = %.3f: %0d half-lines, first active line %0d", fps_s, TFS, lx, HLX, VEXP);
end endtask
initial expect_rate;

reg reset = 1, vs_kill = 0;
reg [1:0] cediv = 0;
reg       ce_pix = 0;
reg [10:0] h_count = HTOT-1;
reg  [9:0] v_count = VTOT-1;
reg [7:0] sframe = 0;                               // source frame number
reg       jdone = 0;
`ifdef LJIT
wire      jstall = sframe[0] && !jdone && v_count == VACT-2 && h_count == HACT && cediv == PIXDIV;
`else
wire      jstall = 0;
`endif
always @(posedge clk) begin
    jdone  <= v_count == 0 ? 1'b0 : jdone | jstall;
    cediv  <= reset || (cediv == PIXDIV && !jstall) ? 2'd0 : jstall ? cediv : cediv + 1'd1;
    ce_pix <= !reset && !jstall && cediv == PIXDIV;
    if( reset ) begin h_count <= HTOT-1; v_count <= vtot-1; end
    else if( cediv == PIXDIV && !jstall ) begin
        if( h_count == HTOT-1 ) begin h_count <= 0; v_count <= v_count >= vtot-1 ? 10'd0 : v_count + 1'd1; end
        else h_count <= h_count + 1'd1;
    end
end
wire hblank = h_count >= HACT, vblank = v_count >= VACT;
wire hsync  = h_count >= HS0 && h_count < HS0 + 64;
wire vsync  = v_count >= VS0 && v_count < VS0 + 8 && !vs_kill;

reg       vsync_l = 0;
always @(posedge clk) begin
    vsync_l <= vsync;
    if( vsync & ~vsync_l ) sframe <= sframe + 1'd1;
end

// Source pattern, 6 significant bits per channel:
//   R: deflicker off: line[5:0]. On: pat(line) = 40 or 160 by parity, + line[6:1], so every
//      line differs and a wrong or stale line changes the blend.
//   G: x[5:0].  B: {frame[1:0], line[8:6], x[6]}; a blend of lines of one frame keeps B[7:6].
function integer pat(input integer n); pat = ((n & 1) ? 160 : 40) + ((n >> 1) & 63); endfunction
reg [7:0] r0, g0, b0, r, g, b;
reg       de0, hs0, vs0, de, hs, vs;
`ifdef SKEW
always @(posedge clk) { r, g, b, de, hs, vs } <= { r0, g0, b0, de0, hs0, vs0 };
`else
always @* { r, g, b, de, hs, vs } = { r0, g0, b0, de0, hs0, vs0 };
`endif
always @(posedge clk) if( ce_pix ) begin
    de0 <= ~hblank & ~vblank;
    hs0 <= hsync;
    vs0 <= vsync;
    r0  <= (`DEFL == 0) ? { v_count[5:0], 2'b0 } : pat(v_count);
    g0  <= { h_count[5:0], 2'b0 };
    b0  <= { sframe[1:0], v_count[8:6], h_count[6], 2'b0 };
end

// ---------------------------------------------------------------- the module
wire       ce_o, hs_o, vs_o, de_o, hb_o, vb_o, field, locked;
reg  [2:0] vheight = `VHEIGHT;                      // menu settings (MENUCHG changes them)
reg  [6:0] voffset = `VOFF;
wire [7:0] r_o, g_o, b_o;
wire       active = locked;                         // the checks below are for the locked stream

wire [23:0] lut_addr;
reg  [23:0] lut_rgb;
`ifdef LUT2
localparam integer LUTL = 2;
reg  [23:0] lut_q;
always @(posedge clk) begin lut_q <= lut_addr; lut_rgb <= lut_q; end   // 2-clk identity palette
`else
localparam integer LUTL = 1;
always @(posedge clk) lut_rgb <= lut_addr;                             // 1-clk identity palette
`endif
`ifdef PACKED
localparam integer LUTE = 0;
`else
localparam integer LUTE = 1;
`endif

crt_480i #(.CLK_HZ(CLKHZ), .CLK_DIV(CDIV), .RING(RINGN), .CLK_FRAC(FRAC), .H_START(HST), .HS_PIX(HSP),
           .PW(24), .LUT_EXT(LUTE), .LUT_LAT(LUTL), .HL_MIN(`HLMIN), .VIS_LINES(`VISL)) u_dut (
    .clk(clk), .ce_in(ce_pix), .pix_in({r, g, b}), .vs_in(vs), .de_in(de),
    .hoffset(7'(`HOFF)), .voffset(voffset), .deflicker(3'(`DEFL)), .vheight(vheight),
    .lut_addr(lut_addr), .lut_rgb(lut_rgb),
    .ce_out(ce_o), .r_out(r_o), .g_out(g_o), .b_out(b_o),
    .hs_out(hs_o), .vs_out(vs_o), .de_out(de_o), .hb_out(hb_o), .vb_out(vb_o),
    .field(field), .locked(locked)
);

// ---------------------------------------------------------------- error accounting
// Picture errors (fail) may be forgiven in the one field a disturbance lands in; timing and
// safety errors (tfail) never are.
integer t = 0;
always @(posedge clk) t <= t + 1;
integer errors = 0, terrors = 0, fields = 0, last_err_field = -1;
integer dist_field = -1;              // field of the last disturbance (reset, VSync loss)
integer stat_from  = 1;               // timing statistics only from this field on
task fail(input [8*80-1:0] msg); begin
    errors = errors + 1;
    last_err_field = fields;
    if( errors + terrors < 25 ) $display("FAIL t=%0d field=%0d: %0s", t, fields, msg);
end endtask
task tfail(input [8*80-1:0] msg); begin
    terrors = terrors + 1;
    if( errors + terrors < 25 ) $display("FAIL t=%0d field=%0d: %0s", t, fields, msg);
end endtask

// until locked: black with both syncs idle (checked from the first clock, on the outputs)
integer quiet_clks = 0, ever_run = 0;
always @(posedge clk) begin
    if( locked ) ever_run = 1;
    else begin
        quiet_clks = quiet_clks + 1;
        if( hs_o || vs_o || de_o || r_o || g_o || b_o ) tfail("output not quiet while unlocked");
    end
end

// ---------------------------------------------------------------- the locked stream
reg        hs_p = 0, vs_p = 0, de_p = 0;
integer    last_hs = 0, last_vs = 0, lines_in_field = 0, vs_lines = 0;
integer    hs_period = 0, vs_period, vs_phase;
integer    act_lines = 0, px_in_line = 0, hpx = 0;
integer    cur_line = -1, fld_frame = -1, prev_frame = -1;
integer    s_line, s_x, s_frame;
integer    min_hp = 1<<30, max_hp = 0, min_vp = 1<<30, max_vp = 0, ph0 = 0, ph1 = 0;

always @(posedge clk) if( active && ce_o ) begin
    hs_p <= hs_o; vs_p <= vs_o; de_p <= de_o;
    hpx = (hs_o & ~hs_p) ? 0 : hpx + 1;
    // ---- HSync cadence
    if( hs_o & ~hs_p ) begin
        hs_period = t - last_hs;
        last_hs   = t;
        lines_in_field = lines_in_field + 1;
        vs_lines  = vs_lines + 1;
        if( fields > stat_from ) begin
            if( hs_period < min_hp ) min_hp = hs_period;
            if( hs_period > max_hp ) max_hp = hs_period;
        end
    end
    // ---- a field ends on the VSync rise
    if( vs_o & ~vs_p ) begin
        vs_period = t - last_vs;
        last_vs   = t;
        vs_phase  = t - last_hs;               // VSync position within the line, clk
        if( fields > 1 ) begin
            if( act_lines != NOUT ) fail("active lines per field wrong");
            if( prev_frame >= 0 && fld_frame != ((prev_frame + 1) & 3) ) fail("field skipped or repeated a source frame");
            if( lines_in_field != (HLX-1)/2 && lines_in_field != (HLX+1)/2 ) fail("lines per field not (HL-1)/2 or (HL+1)/2");
        end
        if( fields > stat_from ) begin
            if( vs_period < min_vp ) min_vp = vs_period;
            if( vs_period > max_vp ) max_vp = vs_period;
            if( vs_phase < hs_period/4 ) ph0 = ph0 + 1; else ph1 = ph1 + 1;
            // the field that starts with a mid-line VSync must be field 1 (the odd lines)
            if( (vs_phase >= hs_period/4) != field ) tfail("mid-line VSync on the wrong field");
        end
        prev_frame = fld_frame;
        fields     = fields + 1;
        act_lines  = 0; lines_in_field = 0; vs_lines = 0;
        cur_line   = -1; fld_frame = -1;
    end
    // ---- position: centred horizontally; vertically, field 1's lines half a line lower
    if( de_o & ~de_p && fields > 1 ) begin
        if( hpx != HST + (512 - WOUT) / 2 + `HOFF ) fail("picture not at its horizontal position");
        if( act_lines == 0 && vs_lines != VEXP - 3 + field ) fail("first active line not where expected");
    end
    // ---- pixels
    if( de_o && `VHEIGHT != 0 ) begin : vfl
        integer L, pos, posr, n, fr, d, h, na, nb, ra, rc, rb, r0, rwa, rwb, sm, wa, wb, wc, ex, step;
        if( !de_p ) begin
            act_lines = act_lines + 1;
            px_in_line = 0;
        end
        step = (VACT * ((1<<24) / (2*NOUT))) >> 8;                  // same fixed point as the RTL
        L    = 2*(act_lines-1) + field;
        pos  = L * step;
        posr = pos + 32768;                                          // nearest line
        n    = posr >> 16;
        fr   = (posr >> 8) & 255;
        d    = fr - 128;
        na   = n == 0   ? n : n-1;
        nb   = n >= VACT-1 ? n : n+1;
        ra   = `DEFL == 0 ? (na & 63) * 4 : pat(na);
        rc   = `DEFL == 0 ? (n  & 63) * 4 : pat(n);
        rb   = `DEFL == 0 ? (nb & 63) * 4 : pat(nb);
        // deflicker-then-interpolate, far line dropped (written independently of the RTL ROM)
        h    = `DEFL == 0 ? 0 : `DEFL == 1 ? 32 : `DEFL == 2 ? 48 : 64;       // kernel side weight
        r0   = (256 - (d < 0 ? -d : d)) * (256 - 2*h) + (d < 0 ? -d : d) * h;
        if( `DEFL == 3 ) begin                  // Medium+: the earlier tent, half-width 1.5 lines
            r0  = 384 - (d < 0 ? -d : d);
            rwa = 384 - (256 + d);  if( rwa < 0 ) rwa = 0;
            rwb = 384 - (256 - d);  if( rwb < 0 ) rwb = 0;
        end else if( d >= 0 ) begin
            rwa = h * (256 - d);
            rwb = (256 - d) * h + d * (256 - 2*h);
        end else begin
            rwb = h * (256 + d);
            rwa = (256 + d) * h + (-d) * (256 - 2*h);
        end
        sm   = r0 + rwa + rwb;
        wa   = (rwa*256 + sm/2) / sm;
        wb   = (rwb*256 + sm/2) / sm;
        wc   = 256 - wa - wb;
        ex   = (ra*wa + rc*wc + rb*wb + 128) >> 8;
        if( r_o != ex ) fail("vertical stretch value wrong");
        if( g_o[7:2] != (px_in_line & 63) ) fail("pixel out of order (stretch)");
        if( fld_frame < 0 ) fld_frame = b_o[7:6];
        else if( b_o[7:6] != fld_frame ) fail("stretch: stale line from another frame");
        px_in_line = px_in_line + 1;
    end else if( de_o && `DEFL != 0 ) begin : dfl
        integer sl, ra, rc, rb, ex;
        if( !de_p ) begin
            act_lines = act_lines + 1;
            px_in_line = 0;
        end
        sl = 2*(act_lines-1) + field;
        rc = pat(sl);
        ra = sl == 0      ? rc : pat(sl-1);
        rb = sl == VACT-1 ? rc : pat(sl+1);
        ex = (`DEFL == 1) ? (ra + 6*rc + rb) / 8 : (`DEFL == 2) ? (3*ra + 10*rc + 3*rb) / 16 :
             (`DEFL == 3) ? (13*ra + 38*rc + 13*rb) / 64 : (ra + 2*rc + rb) / 4;
        if( r_o != ex ) fail("deflicker blend value wrong");
        if( g_o[7:2] != (px_in_line & 63) ) fail("pixel out of order (deflicker)");
        if( fld_frame < 0 ) fld_frame = b_o[7:6];
        else if( b_o[7:6] != fld_frame ) fail("deflicker: stale line from another frame");
        px_in_line = px_in_line + 1;
    end else if( de_o ) begin
        s_line  = { b_o[5:3], r_o[7:2] };
        s_x     = { b_o[2], g_o[7:2] };
        s_frame = b_o[7:6];
        if( !de_p ) begin                      // line start
            if( cur_line >= 0 && s_line != cur_line + 2 ) fail("line did not step by 2");
            if( cur_line < 0 && s_line != field ) fail("first line of the field wrong");
            if( fld_frame < 0 ) fld_frame = s_frame;
            else if( s_frame != fld_frame ) fail("pixels from two source frames in one field");
            cur_line   = s_line;
            px_in_line = 0;
            act_lines  = act_lines + 1;
        end
        if( s_line != cur_line ) fail("line changed within a line");
        if( (s_x & 7'h7f) != (px_in_line & 7'h7f) ) fail("pixel out of order");
        px_in_line = px_in_line + 1;
    end else if( de_p ) begin
        if( px_in_line != WOUT ) fail("line width wrong");
    end
end

`ifdef DUMP
integer dump_f;
initial dump_f = $fopen(`DUMP, "w");
always @(posedge clk) if( active && ce_o && fields > 2 )
    $fwrite(dump_f, "%h%h%h%b%b%b%b\n", r_o, g_o, b_o, hs_o, vs_o, de_o, field);
`endif

// ---------------------------------------------------------------- the run
localparam integer TF_MAX = CLKHZ / 49;
integer t0;
initial begin
    #1000 reset = 0;
`ifdef NOLOCK
    repeat( 3_000_000 ) @(posedge clk);
    $display("quiet (unlocked, no sync) clocks: %0d", quiet_clks);
    if( ever_run ) tfail("locked onto a source outside the frame-rate window");
    if( errors + terrors ) $display("RESULT: FAIL (%0d errors)", errors + terrors); else $display("RESULT: PASS");
    $finish;
`endif
`ifdef MIDRESET
    repeat( 2_000_000 ) @(posedge clk);
    wait( de && v_count == 100 && h_count == 200 );   // part-way along an active line
    reset = 1; repeat( 5000 ) @(posedge clk); reset = 0;
    dist_field = fields; stat_from = fields + 2;
`endif
`ifdef VSLOSS
    wait( fields == 6 );
    vs_kill = 1; t0 = t;
    wait( !u_dut.run );
    $display("VSync lost: unlocked after %0d clk (limit %0d)", t - t0, TF_MAX + TF_MAX/4);
    if( t - t0 > TF_MAX + TF_MAX/4 ) tfail("still locked long after the source VSync stopped");
    repeat( 3 * TF_MAX ) @(posedge clk);
    vs_kill = 0;
    wait( u_dut.run );
    dist_field = fields; stat_from = fields + 2;
`endif
`ifdef RATECHG
    wait( fields == 6 );
    @(posedge clk) wait( v_count == VACT + 2 );   // in vertical blank, before VSync
    vtot = 500; expect_rate;
    wait( !locked );
    wait( locked );
    dist_field = fields; stat_from = fields + 2;
    min_hp = 1<<30; max_hp = 0; min_vp = 1<<30; max_vp = 0; ph0 = 0; ph1 = 0;
`endif
`ifdef MENUCHG
    wait( fields == 6 );
    repeat( 150_000 ) @(posedge clk);            // part-way through a field
    vheight = `VHEIGHT ? 3'd0 : 3'd5; voffset = 7'(`VOFF + 7);
    wait( fields == 9 );
    repeat( 90_000 ) @(posedge clk);
    vheight = `VHEIGHT; voffset = `VOFF;         // back: every later field must be exact again
    // A change can move the field start from late in the source frame to early (or back), which
    // gives one long or short field while the menu is changed. Timing counts again from here.
    dist_field = fields; stat_from = fields + 3;
    min_hp = 1<<30; max_hp = 0; min_vp = 1<<30; max_vp = 0; ph0 = 0; ph1 = 0;
`endif
    wait( fields == 20 );
    $display("fields checked       : %0d", fields - 2);
    $display("last field with an error: %0d (of %0d)", last_err_field, fields);
    $display("HSync period (clk)   : %0d..%0d  (%.3f kHz)", min_hp, max_hp, CLKHZ / 1000.0 / ((min_hp + max_hp) / 2.0));
    $display("VSync period (clk)   : %0d..%0d  (%.3f Hz, source %0d clk)", min_vp, max_vp, CLKHZ / ((min_vp + max_vp) / 2.0), TFS);
    $display("VSync line phase     : %0d fields at line start, %0d mid-line", ph0, ph1);
    if( max_hp - min_hp > 3 ) tfail("HSync jitter too large");
    // the line rate a 15 kHz CRT holds, whatever the source frame rate
    if( CLKHZ / ((min_hp + max_hp) / 2.0) < 15000.0 || CLKHZ / ((min_hp + max_hp) / 2.0) > 16500.0 )
        tfail("line rate outside 15.0..16.5 kHz");
    // one field per source frame: the field period is the source frame (within the start jitter)
    if( min_vp < TFS - 2*CDIV_MAX || max_vp > TFS + 2*CDIV_MAX ) tfail("field period is not the source frame");
    // the field start lands on an output-pixel boundary: up to 2 output pixels of jitter, no drift
    if( max_vp - min_vp > 2*CDIV_MAX ) tfail("field period drifts");
    if( ph0 == 0 || ph1 == 0 || (ph0 - ph1 > 1) || (ph1 - ph0 > 1) ) tfail("VSync does not alternate line start / mid-line");
    // a disturbance breaks the field it lands in (and, stretched, possibly the next): no later one
    if( dist_field >= 0 && errors && last_err_field <= dist_field + 2 ) begin
        $display("picture errors only in the disturbed field (%0d): recovered", errors);
        errors = 0;
    end
    $display("quiet (unlocked, no sync) clocks: %0d", quiet_clks);
    if( errors + terrors ) $display("RESULT: FAIL (%0d errors)", errors + terrors); else $display("RESULT: PASS");
    $finish;
end

initial begin
    #1_000_000_000;                     // 1 s of simulated time is far too long: something is stuck
    $display("RESULT: FAIL (timeout, fields=%0d, active=%0d)", fields, active);
    $finish;
end

endmodule
