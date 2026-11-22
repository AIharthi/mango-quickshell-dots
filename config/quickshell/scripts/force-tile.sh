#!/usr/bin/env bash
set -euo pipefail

# Force MangoWC back into tiling mode:
# 1. Switch current tag layout back to 'tile'
# 2. If the focused window is currently floating, return it to tiled mode

mmsg dispatch setlayout,tile >/dev/null 2>&1 || true

focused_json=$(mmsg get focusing-client 2>/dev/null || true)
if [[ -n "$focused_json" ]] && echo "$focused_json" | grep -q '"is_floating"[[:space:]]*:[[:space:]]*true'; then
    mmsg dispatch togglefloating >/dev/null 2>&1 || true
fi
