import AppKit

enum StatusItemRenderer {
    static func ringOutlineImage(standup: NSColor, category: NSColor?) -> NSImage {
        let outer: CGFloat = 14
        let stroke: CGFloat = 2
        let gap: CGFloat = 1.5
        let inner: CGFloat = outer - 2 * stroke - 2 * gap
        let h: CGFloat = 18
        let image = NSImage(size: NSSize(width: outer, height: h))
        image.lockFocus()
        let y = (h - outer) / 2
        if category == nil {
            standup.setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: y, width: outer, height: outer)).fill()
        } else {
            let strokeRect = NSRect(x: stroke / 2, y: y + stroke / 2, width: outer - stroke, height: outer - stroke)
            let ring = NSBezierPath(ovalIn: strokeRect)
            ring.lineWidth = stroke
            standup.setStroke()
            ring.stroke()
            let ix = (outer - inner) / 2
            let iy = y + (outer - inner) / 2
            category!.setFill()
            NSBezierPath(ovalIn: NSRect(x: ix, y: iy, width: inner, height: inner)).fill()
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}
