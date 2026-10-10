import AppKit

/// Menu bar glyph from the app icon: a crescent moon, plus the agent prompt chevron while the Mac is held
/// awake. Drawn as a template image so macOS tints it for light/dark menu bars.
enum StatusIcon {
    private static var cache: [Bool: NSImage] = [:]

    static func image(awake: Bool) -> NSImage {
        if let i = cache[awake] { return i }
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1.5, y: 2, width: 14, height: 14)).fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 5.5, y: 4.5, width: 12.5, height: 12.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            if awake {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 9.5, y: 12.5))
                p.line(to: NSPoint(x: 13, y: 9.5))
                p.line(to: NSPoint(x: 9.5, y: 6.5))
                p.lineWidth = 1.9
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                NSColor.black.setStroke()
                p.stroke()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = awake ? "Agent Awake: keeping the Mac awake" : "Agent Awake: idle"
        cache[awake] = img
        return img
    }
}
