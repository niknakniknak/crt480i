#!/bin/bash
# Builds skill/crt-480i/SKILL.md from AGENTS.md (one source for both; run after editing it).
cd "$(dirname "$0")"
mkdir -p skill/crt-480i
{ cat <<'H'
---
name: crt-480i
description: Add the crt_480i module to a MiSTer core so its medium-res (24-25 kHz) picture plays on a 15 kHz CRT as 480i on VGA, while HDMI keeps the normal picture. Use when porting crt_480i to a core, building an "SD" (15 kHz) version of a medium-res core, or debugging one. The kit (rtl/, sim/, examples/, README.md) must be available in the workspace.
---
H
  sed '1s/^# AGENTS.md: adding/# Adding/' AGENTS.md; } > skill/crt-480i/SKILL.md
echo "skill/crt-480i/SKILL.md: $(wc -l < skill/crt-480i/SKILL.md) lines"
