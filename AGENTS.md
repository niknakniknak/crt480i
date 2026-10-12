# AGENTS.md: adding crt_480i to a MiSTer core

Instructions for a coding agent. Read this file, then `README.md` (the full guide), then the
closest example in `examples/`. Work in the order below and verify at every step.

## Goal

A separate "SD" (standard definition, 15 kHz) build of an existing MiSTer core whose native picture is medium-res (about
24-25 kHz, e.g. 512x384 at 60 Hz):
- the analog/VGA output carries **only** 15 kHz 480i from `rtl/crt_480i.sv`;
- HDMI carries the core's normal native picture, through `NATIVE_*` and the scaler.

**Hard safety rule:** nothing but `crt_480i` may drive `VGA_*` / `CE_PIXEL`. No switch, no
mux back to the native picture, no scaler on VGA. 24-25 kHz can damage a 15 kHz monitor.
Don't add an "Off" option, even if it seems convenient.

## Pick the closest example

| The core... | Start from |
|---|---|
| drives `VGA_*` from its own renderer, palette in a RAM with a spare port | `examples/atari-system2.patch` |
| uses `arcade_video` (and `screen_rotate` with `.*`) | `examples/toobin.patch` |
| has a clock that doesn't divide to ~10.67 MHz, blanks inside the picture, or runs `hps_io` on another clock | `examples/hard-drivin.patch` |

Always apply `examples/sys.patch` to the core's `sys/` (it adds the `NATIVE_*` outputs to
`emu`, feeds them to the HDMI scaler, and ties the scaler off VGA). If it fails on line
endings, use `git apply --ignore-whitespace`, or make the same edits by hand.

## Step 1: measure the core, from its RTL (not from docs or memory)

Write these down before editing anything:
1. The video clock that the pixel enable runs on, and the pixel enable itself.
2. H and V totals and the active area, from the counters (the module measures them at run
   time, but you need them to choose parameters and to check the limits in `README.md`).
3. The frame rate (49 Hz up to 62.86 Hz, or the module never locks; the module picks the
   line count itself, e.g. 625 at 50 Hz, 571 at 54.8 Hz, 525 at 60 Hz), the frame-period
   stability (must match within 4 clocks frame to frame) and the line rates: the ring needs
   `active lines - output lines x (source line rate / 15.7 kHz) + 3 < RING` (16.5 kHz above
   60 Hz), output lines = the smallest Height offered (active/2 at 1:1, 200 if Height can
   shrink the picture). 384 active lines at 25 kHz: about 84, inside the default 96; 448
   lines shrunk to 200: about 131, so `RING(160)`.
4. Where the palette lookup happens, the pixel **index** width before it, and the lookup's
   latency. The index must be aligned with the RGB it produces (same pixel).
5. Which status bits are free (for the menu), and anything between the core and `VGA_*`
   (analog alignment stages, rotation, a mixer).

## Step 2: choose parameters

- `CLK_HZ` = the module clock in Hz, accurate. **Required.** The module's `clk` must be the
  core's `CLK_VIDEO`, and so must the `NATIVE_*` stream (`NATIVE_CE` an enable on it).
- `CLK_DIV` so that clock / `CLK_DIV` is about 10-11 MHz (32/3, 64/6). At 48 MHz use
  `CLK_DIV(4), CLK_FRAC(1)`. Minimum 3. The build stops with a named error if the output
  pixel clock doesn't fit the line, or the `CLK_FRAC` rule is broken.
- `PW` = index width (+1 if you add a blank flag). `LUT_EXT(1)`.
- `LUT_LAT` = clocks from `lut_addr` to valid `lut_rgb`: 1 for a plain registered RAM
  read; 2 if you register the palette maths after it (do that if it multiplies or divides).

## Step 3: wire it (follow the example's structure)

- Give the module its own palette read: a spare RAM port, or a mirror RAM written with the
  same CPU writes (copy the write enables exactly).
- `VGA_R/G/B/HS/VS/DE`, `CE_PIXEL`, `VGA_F1 (= field)` from the module; `VGA_SL = 0`;
  `VGA_SCALER = 0`.
- The core's existing HDMI path (`arcade_video`, `video_freak`, `screen_rotate`) drives
  `NATIVE_*` instead of `VGA_*`. Connect these instances **explicitly**; `.*` would silently
  hook them to the 480i `VGA_*` signals. Tie `arcade_video`'s `forced_scandoubler` to 0.
- `video_freak`: `CE_PIXEL`/`VGA_VS`/`VGA_DE_IN` from the native stream, `VGA_DE` output to
  `NATIVE_DE`.
- Remove analog-only alignment stages and their menu entries. On VGA they would now do
  nothing, and the module has its own H/V position.
- Menu: a "CRT 480i" page with Deflicker, Height, H-Position, V-Position (see `README.md`),
  decoded with `$signed()` from sign-extended status fields.
- If `hps_io` is not on the module clock, synchronise the menu bits (two flops).
- Copy `rtl/crt_480i.sv` into the core (the patches don't carry it) and add it to
  `files.qip`. Take files that are no longer used out of `files.qip` and the `.qsf`, and
  delete them in the fork.

## Traps that have each cost a build cycle

- **Never pass the 480i output through `arcade_video` / `video_mixer` / `video_cleaner`.**
  They move VSync onto the next HSync, which destroys the interlace. The symptom looks like
  "deflicker doesn't work" and "not as clean".
- **Index alignment.** An index one pixel early or late gives shifted colours, and the
  testbench can't see it. Check it against the RGB pipeline stage by stage.
- **Slow palette into the capture.** It fails timing, or passes by a hair and sparkles.
  Register it and set `LUT_LAT(2)`.
- **Blank pixels inside the picture** become palette entry 0 in index mode. Carry a blank
  flag bit and force black after the lookup.
- **RBF naming.** MiSTer loads the alphabetically last `<rbf>_*.rbf` or `<rbf>.rbf`. Name the
  build so it can't be matched as `<stock-name>_...`, and check every MRA in the folder.
- **HDMI pink/green with Gamma on.** MiSTer's gamma (`sys/gamma_corr.sv`, in `arcade_video`)
  needs at least 4 `CLK_VIDEO` clocks per pixel; at 3 (e.g. 48 MHz, 16 MHz pixels) the colours
  break. Either grey Gamma out (`hps_io` `gamma_bus[21] = 0`) or give `arcade_video` at least
  4 clocks per pixel.
- Quartus 17 on the core: Verilog-2001 in `.v` files. The module is `.sv` and is fine.

## Verify

1. **Module unchanged?** Don't edit `rtl/crt_480i.sv`. If you must, run `sim/sweep.sh`
   (every line must end `RESULT: PASS`) and `sim/mutants.sh` (every mutant must FAIL)
   before building anything.
2. **Your source timing:** edit the top of `sim/tb_crt_480i.sv`: the raster (`HACT`,
   `VACT`, `HTOT`, `VTOT`, sync positions) and one clock block (`CLKHZ`, `PIXDIV`, `CDIV`,
   `FRAC`, `HST`, `HSP`) to match your core. Then run `sim/run.sh` (add `-DLUT2` for
   `LUT_LAT 2`, `-DPACKED` for `LUT_EXT 0`), and `-DDEFL=4 -DVHEIGHT=6`. They must pass.
   The first line printed is the half-line count it expects for your frame rate.
3. **Build** and read the timing report. Negative slack on your new paths (the palette read,
   the module) is a real finding; fix it before hardware.
4. **Read your diff back** against the upstream core. Check four things:
   - `VGA_*` has exactly one source, the module;
   - the native path is unchanged apart from its output names;
   - no leftover dead code;
   - no comments describing removed features.

## Done means

- VGA shows 480i (CRT: lines interlaced, fields alternate) and nothing else, including
  during core load and reset (black, no sync, until locked: about 5 frames).
- HDMI shows the normal picture, with the core's Aspect, Scale and Orientation working.
- The menu has the CRT 480i page; the removed options are gone.
- Timing report checked; testbench passes for this core's raster.
- Releases follow the GPL (the core's licence and this module's, GPL-2.0-or-later).
