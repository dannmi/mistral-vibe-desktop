#!/bin/bash
# Generates Resources/AppIcon.icns from an SVG using macOS built-in tools.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
SVG="$WORK/icon.svg"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

# Mistral "M" letterform in pixel style: two verticals with a V dipping to
# the middle, colored in Mistral's yellow-to-red vertical flow, with per-row
# gradients, rounded blocks, soft depth shadows and a subtle glow background.
cat > "$SVG" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2E2F36"/>
      <stop offset="1" stop-color="#0D0E12"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.42" r="0.55">
      <stop offset="0" stop-color="#FF7A00" stop-opacity="0.16"/>
      <stop offset="1" stop-color="#FF7A00" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="g0" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFE873"/>
      <stop offset="1" stop-color="#FFC90A"/>
    </linearGradient>
    <linearGradient id="g1" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFD24D"/>
      <stop offset="1" stop-color="#FFAF00"/>
    </linearGradient>
    <linearGradient id="g2" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FF9E2E"/>
      <stop offset="1" stop-color="#FF7300"/>
    </linearGradient>
    <linearGradient id="g3" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FF6242"/>
      <stop offset="1" stop-color="#F51F00"/>
    </linearGradient>
    <linearGradient id="g4" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FF4225"/>
      <stop offset="1" stop-color="#E00900"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" rx="230" fill="url(#bg)"/>
  <rect width="1024" height="1024" rx="230" fill="url(#glow)"/>
  <rect x="3" y="3" width="1018" height="1018" rx="228" fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="3"/>
  <g transform="translate(176,176)">
    <g fill="#000000" fill-opacity="0.32">
      <rect x="0"   y="12"  width="112" height="112" rx="26"/>
      <rect x="560" y="12"  width="112" height="112" rx="26"/>
      <rect x="0"   y="152" width="112" height="112" rx="26"/>
      <rect x="140" y="152" width="112" height="112" rx="26"/>
      <rect x="420" y="152" width="112" height="112" rx="26"/>
      <rect x="560" y="152" width="112" height="112" rx="26"/>
      <rect x="0"   y="292" width="112" height="112" rx="26"/>
      <rect x="280" y="292" width="112" height="112" rx="26"/>
      <rect x="560" y="292" width="112" height="112" rx="26"/>
      <rect x="0"   y="432" width="112" height="112" rx="26"/>
      <rect x="560" y="432" width="112" height="112" rx="26"/>
      <rect x="0"   y="572" width="112" height="112" rx="26"/>
      <rect x="560" y="572" width="112" height="112" rx="26"/>
    </g>
    <rect x="0"   y="0"   width="112" height="112" rx="26" fill="url(#g0)"/>
    <rect x="560" y="0"   width="112" height="112" rx="26" fill="url(#g0)"/>
    <rect x="0"   y="140" width="112" height="112" rx="26" fill="url(#g1)"/>
    <rect x="140" y="140" width="112" height="112" rx="26" fill="url(#g1)"/>
    <rect x="420" y="140" width="112" height="112" rx="26" fill="url(#g1)"/>
    <rect x="560" y="140" width="112" height="112" rx="26" fill="url(#g1)"/>
    <rect x="0"   y="280" width="112" height="112" rx="26" fill="url(#g2)"/>
    <rect x="280" y="280" width="112" height="112" rx="26" fill="url(#g2)"/>
    <rect x="560" y="280" width="112" height="112" rx="26" fill="url(#g2)"/>
    <rect x="0"   y="420" width="112" height="112" rx="26" fill="url(#g3)"/>
    <rect x="560" y="420" width="112" height="112" rx="26" fill="url(#g3)"/>
    <rect x="0"   y="560" width="112" height="112" rx="26" fill="url(#g4)"/>
    <rect x="560" y="560" width="112" height="112" rx="26" fill="url(#g4)"/>
  </g>
</svg>
EOF

# Prefer rsvg-convert / Inkscape if present; otherwise fall back to qlmanage.
render() { # $1 size  $2 out
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "$1" -h "$1" "$SVG" -o "$2"
  elif command -v inkscape >/dev/null 2>&1; then
    inkscape "$SVG" -w "$1" -h "$1" -o "$2" >/dev/null 2>&1
  else
    # qlmanage renders SVG via QuickLook, then sips resizes.
    qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null 2>&1 || true
    local png="$WORK/icon.svg.png"
    [ -f "$png" ] || { echo "No SVG renderer available (install librsvg: brew install librsvg)"; exit 1; }
    sips -z "$1" "$1" "$png" --out "$2" >/dev/null
  fi
}

for s in 16 32 64 128 256 512 1024; do render "$s" "$WORK/$s.png"; done
cp "$WORK/16.png"   "$ICONSET/icon_16x16.png"
cp "$WORK/32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$WORK/32.png"   "$ICONSET/icon_32x32.png"
cp "$WORK/64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$WORK/128.png"  "$ICONSET/icon_128x128.png"
cp "$WORK/256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$WORK/256.png"  "$ICONSET/icon_256x256.png"
cp "$WORK/512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$WORK/512.png"  "$ICONSET/icon_512x512.png"
cp "$WORK/1024.png" "$ICONSET/icon_512x512@2x.png"

mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote $ROOT/Resources/AppIcon.icns"
rm -rf "$WORK"
