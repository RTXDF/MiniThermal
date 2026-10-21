import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("Expected PNG and SVG output paths") }
let pngURL = URL(fileURLWithPath: arguments[1])
let svgURL = URL(fileURLWithPath: arguments[2])
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: size, height: size)
let teal = NSColor(srgbRed: 0.08, green: 0.51, blue: 0.55, alpha: 1)
let orange = NSColor(srgbRed: 0.98, green: 0.60, blue: 0.28, alpha: 1)

let blade = NSBezierPath()
blade.move(to: NSPoint(x: 488, y: 469))
blade.curve(to: NSPoint(x: 430, y: 338), controlPoint1: NSPoint(x: 443, y: 424), controlPoint2: NSPoint(x: 414, y: 384))
blade.curve(to: NSPoint(x: 540, y: 307), controlPoint1: NSPoint(x: 443, y: 298), controlPoint2: NSPoint(x: 500, y: 284))
blade.curve(to: NSPoint(x: 560, y: 424), controlPoint1: NSPoint(x: 583, y: 332), controlPoint2: NSPoint(x: 589, y: 385))
blade.line(to: NSPoint(x: 536, y: 469))
blade.close()

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
let flip = AffineTransform(translationByX: 0, byY: CGFloat(size))
var coordinates = flip
coordinates.scale(x: 1, y: -1)
(coordinates as NSAffineTransform).concat()
teal.setFill()
NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184).fill()
NSColor.white.setFill()
for angle in [0.0, 90.0, 180.0, 270.0] {
    let copy = blade.copy() as! NSBezierPath
    var rotation = AffineTransform(translationByX: 512, byY: 512)
    rotation.rotate(byDegrees: CGFloat(angle))
    rotation.translate(x: -512, y: -512)
    copy.transform(using: rotation)
    copy.fill()
}
orange.setFill()
NSBezierPath(ovalIn: NSRect(x: 482, y: 482, width: 60, height: 60)).fill()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
try data.write(to: pngURL, options: .atomic)

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>MiniThermal flat application icon</title>
  <rect x="100" y="100" width="824" height="824" rx="184" fill="#14828C"/>
  <defs><path id="blade" d="M488 469 C443 424 414 384 430 338 C443 298 500 284 540 307 C583 332 589 385 560 424 L536 469 Z"/></defs>
  <g fill="white">
    <use href="#blade"/>
    <use href="#blade" transform="rotate(90 512 512)"/>
    <use href="#blade" transform="rotate(180 512 512)"/>
    <use href="#blade" transform="rotate(270 512 512)"/>
  </g>
  <circle cx="512" cy="512" r="30" fill="#FA9947"/>
</svg>
"""
try svg.write(to: svgURL, atomically: true, encoding: .utf8)
