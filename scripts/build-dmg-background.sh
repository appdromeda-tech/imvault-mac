#!/usr/bin/env bash
#
# Generate scripts/dmg-background.png — the install-window background image
# used by create-dmg. Shows a curved arrow pointing from the .app slot on
# the left to the Applications shortcut on the right, with a "Drag to install"
# label so novice users know what to do.
#
# Re-run after editing the SWIFT block below to refresh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_PNG="${SCRIPT_DIR}/dmg-background.png"
TMP_SWIFT="$(mktemp -t bg-swift).swift"
trap "rm -f '$TMP_SWIFT'" EXIT

cat > "$TMP_SWIFT" <<'SWIFT'
import AppKit

// Window dimensions used by create-dmg in release.sh.
let width: CGFloat = 600
let height: CGFloat = 400

let canvas = NSImage(size: NSSize(width: width, height: height))
canvas.lockFocus()

// Subtle gradient background.
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.97, green: 0.97, blue: 0.99, alpha: 1.0),  // near-white at top
    NSColor(srgbRed: 0.91, green: 0.93, blue: 0.96, alpha: 1.0),  // very light blue at bottom
])!
gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 270)

// Icon slot positions (mirrors the --icon / --app-drop-link coordinates in
// release.sh). create-dmg's coordinate system has (0,0) at the top-left of
// the window; AppKit drawing here has (0,0) at the bottom-left. We draw the
// arrow in AppKit coords; the icon slots sit at AppKit-y = 180 (which is
// create-dmg's y = 220 since height - 180 = 220 ... but create-dmg
// effectively uses the SAME origin as Finder, so we just pick visual y).
//
// In release.sh we tell create-dmg to place the icons at y=180. The arrow
// here is drawn at the same vertical center (height/2 = 200) so it lines
// up between them visually.
let arrowY = height / 2 - 20
let leftX: CGFloat = 215   // right edge of the .app slot
let rightX: CGFloat = 385  // left edge of the Applications slot

// Curved arrow.
let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: leftX, y: arrowY))
arrowPath.curve(
    to: NSPoint(x: rightX, y: arrowY),
    controlPoint1: NSPoint(x: leftX + 50, y: arrowY + 40),
    controlPoint2: NSPoint(x: rightX - 50, y: arrowY + 40)
)
arrowPath.lineWidth = 4
arrowPath.lineCapStyle = .round
NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 0.85).setStroke()
arrowPath.stroke()

// Arrowhead.
let headSize: CGFloat = 14
let head = NSBezierPath()
head.move(to: NSPoint(x: rightX, y: arrowY))
head.line(to: NSPoint(x: rightX - headSize, y: arrowY + headSize / 2 + 2))
head.move(to: NSPoint(x: rightX, y: arrowY))
head.line(to: NSPoint(x: rightX - headSize, y: arrowY - headSize / 2 - 2))
head.lineWidth = 4
head.lineCapStyle = .round
head.lineJoinStyle = .round
NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 0.85).setStroke()
head.stroke()

// "Drag to install" label below the arrow.
let label = "Drag to install"
let labelFont = NSFont.systemFont(ofSize: 18, weight: .medium)
let labelColor = NSColor(srgbRed: 0.25, green: 0.30, blue: 0.40, alpha: 1.0)
let attrs: [NSAttributedString.Key: Any] = [
    .font: labelFont,
    .foregroundColor: labelColor,
]
let attrLabel = NSAttributedString(string: label, attributes: attrs)
let labelSize = attrLabel.size()
let labelRect = NSRect(
    x: (width - labelSize.width) / 2,
    y: arrowY - labelSize.height - 16,
    width: labelSize.width,
    height: labelSize.height
)
attrLabel.draw(in: labelRect)

canvas.unlockFocus()

guard let cg = canvas.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: cg)
guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
let outPath = CommandLine.arguments[1]
try data.write(to: URL(fileURLWithPath: outPath))
SWIFT

echo "[dmg-bg] rendering 600x400 background to $OUT_PNG ..."
swift "$TMP_SWIFT" "$OUT_PNG"
echo "[dmg-bg] done. ($(du -h "$OUT_PNG" | awk '{print $1}'))"
