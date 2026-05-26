#!/usr/bin/env bash
#
# Generate ImvaultApp/AppIcon.icns from a tiny inline Swift script.
# Placeholder design: iMessage-blue squircle with a centered white
# `lock.doc.fill` SF Symbol — same glyph the in-app FDA onboarding uses.
# Re-run after editing the SWIFT block below to refresh the icon.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUT_ICNS="${REPO_ROOT}/ImvaultApp/AppIcon.icns"
TMP_DIR="$(mktemp -d)"
trap "rm -rf '$TMP_DIR'" EXIT

ICONSET="${TMP_DIR}/AppIcon.iconset"
SOURCE_PNG="${TMP_DIR}/icon-1024.png"
SWIFT_FILE="${TMP_DIR}/draw-icon.swift"

cat > "$SWIFT_FILE" <<'SWIFT'
import AppKit

let size: CGFloat = 1024
let canvas = NSImage(size: NSSize(width: size, height: size))
canvas.lockFocus()

// Squircle background. iOS/macOS use a continuous "superellipse" curve; a
// regular rounded rect at ~22% corner radius gets close enough for a
// placeholder icon.
let cornerRadius = size * 0.22
let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 1.0).setFill() // iMessage blue (#007AFF)
bgPath.fill()

// SF Symbol glyph in white, centered with margin.
let symbolPointSize: CGFloat = size * 0.55
let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
guard let glyph = NSImage(systemSymbolName: "lock.doc.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) else {
    FileHandle.standardError.write("FAIL: lock.doc.fill symbol not available\n".data(using: .utf8)!)
    exit(1)
}

// Tint the symbol to white. SF Symbols are templates; setting fill via a
// drawing block with the right blend gives a clean white render.
let glyphRect = NSRect(
    x: (size - glyph.size.width) / 2,
    y: (size - glyph.size.height) / 2,
    width: glyph.size.width,
    height: glyph.size.height
)

let context = NSGraphicsContext.current!.cgContext
context.saveGState()
context.clip(to: glyphRect, mask: glyph.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
NSColor.white.setFill()
glyphRect.fill()
context.restoreGState()

canvas.unlockFocus()

guard let cg = canvas.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: cg)
guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
let outPath = CommandLine.arguments[1]
try data.write(to: URL(fileURLWithPath: outPath))
SWIFT

echo "[icon] rendering 1024x1024 source..."
swift "$SWIFT_FILE" "$SOURCE_PNG"

echo "[icon] generating iconset sizes..."
mkdir -p "$ICONSET"
# macOS iconset standard sizes: 16, 32, 128, 256, 512, each at 1x and 2x.
# Generate each from the 1024 source via sips.
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE_PNG" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE_PNG" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done

echo "[icon] building $OUT_ICNS ..."
iconutil --convert icns "$ICONSET" --output "$OUT_ICNS"

echo "[icon] done. (file size: $(du -h "$OUT_ICNS" | awk '{print $1}'))"
