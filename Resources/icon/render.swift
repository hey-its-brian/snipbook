// Renders Snipbook app icon concepts with plain Core Graphics paths (no fonts or SF Symbols).
// Usage: swift render.swift <outdir> [concept]
//        swift render.swift --iconset <concept> <out.iconset>   (all macOS icon sizes)
import AppKit

let S: CGFloat = 1024
func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
// One Dark syntax palette, matching the editor theme.
let purple = hex(0xC678DD), red = hex(0xE06C75), green = hex(0x98C379), yellow = hex(0xE5C07B)
let blue = hex(0x61AFEF), cyan = hex(0x56B6C2), gray = hex(0x5C6370)

// macOS icon grid: 824pt body centered on a 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

func squircle(_ fill: (NSBezierPath) -> Void) {
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    fill(path)
    NSGraphicsContext.restoreGraphicsState()
}

func gradient(_ a: NSColor, _ b: NSColor, in rect: CGRect = body, angle: CGFloat = -90) {
    NSGradient(starting: a, ending: b)!.draw(in: rect, angle: angle)
}

func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
    c.setFill()
    NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
}

/// Stroked curly brace centered at (cx, cy). open = "{", otherwise "}".
func brace(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, open: Bool, color: NSColor, line: CGFloat) {
    let d: CGFloat = open ? 1 : -1
    let p = NSBezierPath()
    p.move(to: CGPoint(x: cx + d * w / 2, y: cy + h / 2))
    p.curve(to: CGPoint(x: cx, y: cy + h / 2 - w / 2),
            controlPoint1: CGPoint(x: cx + d * w * 0.1, y: cy + h / 2),
            controlPoint2: CGPoint(x: cx, y: cy + h / 2 - w * 0.2))
    p.line(to: CGPoint(x: cx, y: cy + w * 0.45))
    p.curve(to: CGPoint(x: cx - d * w / 2, y: cy),
            controlPoint1: CGPoint(x: cx, y: cy + w * 0.1), controlPoint2: CGPoint(x: cx - d * w * 0.2, y: cy))
    p.curve(to: CGPoint(x: cx, y: cy - w * 0.45),
            controlPoint1: CGPoint(x: cx - d * w * 0.2, y: cy), controlPoint2: CGPoint(x: cx, y: cy - w * 0.1))
    p.line(to: CGPoint(x: cx, y: cy - h / 2 + w / 2))
    p.curve(to: CGPoint(x: cx + d * w / 2, y: cy - h / 2),
            controlPoint1: CGPoint(x: cx, y: cy - h / 2 + w * 0.2),
            controlPoint2: CGPoint(x: cx + d * w * 0.1, y: cy - h / 2))
    p.lineWidth = line
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    color.setStroke()
    p.stroke()
}

/// Padlock with its body's bottom-left at (x, y), body width w.
func lock(x: CGFloat, y: CGFloat, w: CGFloat, bodyColor: NSColor, holeColor: NSColor) {
    let h = w * 0.78
    let shackle = NSBezierPath()
    let sw = w * 0.62, sx = x + (w - sw) / 2, top = y + h + sw * 0.55
    shackle.move(to: CGPoint(x: sx, y: y + h * 0.6))
    shackle.line(to: CGPoint(x: sx, y: top - sw / 2))
    shackle.appendArc(withCenter: CGPoint(x: x + w / 2, y: top - sw / 2), radius: sw / 2, startAngle: 180, endAngle: 0, clockwise: true)
    shackle.line(to: CGPoint(x: sx + sw, y: y + h * 0.6))
    shackle.lineWidth = w * 0.16
    shackle.lineCapStyle = .round
    bodyColor.setStroke(); shackle.stroke()
    bodyColor.setFill()
    NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), xRadius: w * 0.16, yRadius: w * 0.16).fill()
    holeColor.setFill()
    NSBezierPath(ovalIn: CGRect(x: x + w / 2 - w * 0.09, y: y + h * 0.42, width: w * 0.18, height: w * 0.18)).fill()
    NSBezierPath(roundedRect: CGRect(x: x + w / 2 - w * 0.04, y: y + h * 0.2, width: w * 0.08, height: h * 0.3), xRadius: w * 0.04, yRadius: w * 0.04).fill()
}

func codeLines(x: CGFloat, top: CGFloat, unit: CGFloat, rows: [[(CGFloat, NSColor)]], indent: [CGFloat]) {
    let h = unit * 0.9, gap = unit * 0.55
    for (i, row) in rows.enumerated() {
        var cx = x + indent[i] * unit * 1.6
        let y = top - CGFloat(i) * (h + gap) - h
        for (len, color) in row {
            bar(cx, y, len * unit, h, color)
            cx += len * unit + unit * 0.5
        }
    }
}

// MARK: - Concepts

func midnight() {
    squircle { _ in
        gradient(hex(0x353B47), hex(0x1B1E24))
        // window dots
        for (i, c) in [red, yellow, green].enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: CGRect(x: 190 + CGFloat(i) * 58, y: 790, width: 38, height: 38)).fill()
        }
        codeLines(x: 190, top: 720, unit: 44, rows: [
            [(3.5, purple), (5, yellow)],
            [(3, purple), (4.5, blue), (2, gray)],
            [(4, red), (2, cyan), (4, green)],
            [(2.5, purple)],
            [(2.5, purple)],
        ], indent: [0, 1, 2, 1, 0])
        // lock badge
        hex(0x1B1E24).setFill()
        NSBezierPath(ovalIn: CGRect(x: 610, y: 150, width: 250, height: 250)).fill()
        let clip = NSBezierPath(ovalIn: CGRect(x: 628, y: 168, width: 214, height: 214))
        NSGraphicsContext.saveGraphicsState(); clip.addClip()
        gradient(hex(0xF5D38A), hex(0xD9A441))
        NSGraphicsContext.restoreGraphicsState()
        lock(x: 690, y: 205, w: 90, bodyColor: hex(0x1B1E24), holeColor: hex(0xE5B95C))
    }
}

func braces() {
    squircle { _ in
        gradient(hex(0x8E5CF7), hex(0x3B7BF0))
        // soft glow
        NSGradient(starting: .white.withAlphaComponent(0.22), ending: .white.withAlphaComponent(0))!
            .draw(fromCenter: CGPoint(x: 400, y: 760), radius: 0, toCenter: CGPoint(x: 400, y: 760), radius: 620, options: [])
        brace(cx: 330, cy: 512, w: 130, h: 470, open: true, color: .white, line: 64)
        brace(cx: 694, cy: 512, w: 130, h: 470, open: false, color: .white, line: 64)
        for (i, c) in [yellow, green, hex(0xFF8FA3)].enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: CGRect(x: 424 + CGFloat(i) * 64, y: 486, width: 48, height: 48)).fill()
        }
    }
}

func folder() {
    squircle { _ in
        gradient(hex(0xF4F6FA), hex(0xD9DEE7))
        // back of folder with tab
        let back = NSBezierPath()
        back.move(to: CGPoint(x: 190, y: 250))
        back.line(to: CGPoint(x: 190, y: 720))
        back.appendArc(from: CGPoint(x: 190, y: 760), to: CGPoint(x: 230, y: 760), radius: 36)
        back.line(to: CGPoint(x: 410, y: 760))
        back.line(to: CGPoint(x: 460, y: 700))
        back.line(to: CGPoint(x: 800, y: 700))
        back.appendArc(from: CGPoint(x: 834, y: 700), to: CGPoint(x: 834, y: 660), radius: 34)
        back.line(to: CGPoint(x: 834, y: 250))
        back.close()
        hex(0x3E8EEA).setFill(); back.fill()
        // paper peeking out
        hex(0xFFFFFF).setFill()
        NSBezierPath(roundedRect: CGRect(x: 240, y: 380, width: 544, height: 320), xRadius: 18, yRadius: 18).fill()
        codeLines(x: 280, top: 670, unit: 24, rows: [[(4, purple), (6, blue)], [(5, red), (4, green)]], indent: [0, 1])
        // front
        let front = NSBezierPath(roundedRect: CGRect(x: 180, y: 220, width: 664, height: 420), xRadius: 40, yRadius: 40)
        NSGraphicsContext.saveGraphicsState(); front.addClip()
        gradient(hex(0x6CB6FF), hex(0x3F8CEB))
        NSGraphicsContext.restoreGraphicsState()
        brace(cx: 400, cy: 430, w: 70, h: 250, open: true, color: .white, line: 38)
        brace(cx: 624, cy: 430, w: 70, h: 250, open: false, color: .white, line: 38)
        bar(470, 412, 84, 36, .white.withAlphaComponent(0.9))
    }
}

func notebook() {
    squircle { _ in
        gradient(hex(0x2B7A6F), hex(0x17423D))
        // book cover and pages
        hex(0x0F2E2A, 0.5).setFill()
        NSBezierPath(roundedRect: CGRect(x: 232, y: 176, width: 580, height: 680), xRadius: 40, yRadius: 40).fill()
        hex(0xFBF7EE).setFill()
        let page = CGRect(x: 250, y: 200, width: 540, height: 640)
        NSBezierPath(roundedRect: page, xRadius: 34, yRadius: 34).fill()
        // binding
        let binding = NSBezierPath(roundedRect: CGRect(x: 250, y: 200, width: 70, height: 640), xRadius: 34, yRadius: 34)
        hex(0xE8DFCB).setFill(); binding.fill()
        hex(0xE8DFCB).setFill(); NSBezierPath(rect: CGRect(x: 290, y: 200, width: 30, height: 640)).fill()
        codeLines(x: 360, top: 740, unit: 30, rows: [
            [(3.5, purple), (5, hex(0xC18401))],
            [(3, purple), (4.5, hex(0x4078F2))],
            [(4, hex(0xE45649)), (4, hex(0x50A14F))],
            [(2.5, purple)],
            [(4.5, hex(0x0184BC)), (3, hex(0xA0A1A7))],
            [(2.5, purple)],
        ], indent: [0, 1, 2, 1, 1, 0])
        // ribbon bookmark
        let r = NSBezierPath()
        r.move(to: CGPoint(x: 660, y: 860))
        r.line(to: CGPoint(x: 660, y: 540))
        r.line(to: CGPoint(x: 700, y: 580))
        r.line(to: CGPoint(x: 740, y: 540))
        r.line(to: CGPoint(x: 740, y: 860))
        r.close()
        hex(0xE0533D).setFill(); r.fill()
    }
}

let concepts: [(String, () -> Void)] = [("1-midnight", midnight), ("2-braces", braces), ("3-folder", folder), ("4-notebook", notebook)]

func render(_ draw: () -> Void, size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    ctx.cgContext.scaleBy(x: CGFloat(size) / S, y: CGFloat(size) / S)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let args = CommandLine.arguments
if args[1] == "--iconset" {
    let draw = concepts.first { $0.0 == args[2] }!.1
    let out = URL(fileURLWithPath: args[3])
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
            let png = render(draw, size: base * scale).representation(using: .png, properties: [:])!
            try! png.write(to: out.appendingPathComponent(name))
        }
    }
} else {
    let out = URL(fileURLWithPath: args[1])
    let only = args.count > 2 ? args[2] : nil
    for (name, draw) in concepts where only == nil || name == only {
        let png = render(draw, size: 1024).representation(using: .png, properties: [:])!
        try! png.write(to: out.appendingPathComponent("\(name).png"))
    }
}
