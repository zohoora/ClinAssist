import AppKit

/// Creates the custom ClinAssist menu bar icon programmatically
/// Based on the interlocking medical cross design
@MainActor
enum MenuBarIcon {
    
    /// Creates the menu bar template icon
    /// - Parameter state: The current app state to determine visual state
    /// - Returns: An NSImage configured as a template for the menu bar
    static func createIcon(for state: AppState = .idle) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            drawIcon(in: rect, state: state)
            return true
        }
        image.isTemplate = true
        return image
    }
    
    /// Creates a colored variant of the icon (for Dock or non-menu bar use)
    static func createColoredIcon(size: CGFloat = 64) -> NSImage {
        let imageSize = NSSize(width: size, height: size)
        return NSImage(size: imageSize, flipped: false) { rect in
            drawColoredIcon(in: rect)
            return true
        }
    }
    
    // MARK: - Private Drawing Methods
    
    private static func drawIcon(in rect: NSRect, state: AppState) {
        let inset: CGFloat = 1.5
        let drawRect = rect.insetBy(dx: inset, dy: inset)
        let center = NSPoint(x: drawRect.midX, y: drawRect.midY)
        
        // Draw an elegant interlocking cross design
        // Using two offset crosses to create the characteristic interlock effect
        let armLength: CGFloat = drawRect.width * 0.42
        let armWidth: CGFloat = drawRect.width * 0.28
        let strokeWidth: CGFloat = 1.2
        let offset: CGFloat = 1.5
        
        NSColor.black.setStroke()
        
        // Background cross (offset up-left) - draw only the parts that should be "behind"
        drawCrossOutline(
            center: NSPoint(x: center.x - offset, y: center.y + offset),
            armLength: armLength,
            armWidth: armWidth,
            strokeWidth: strokeWidth
        )
        
        // Foreground cross (offset down-right)
        drawCrossOutline(
            center: NSPoint(x: center.x + offset, y: center.y - offset),
            armLength: armLength,
            armWidth: armWidth,
            strokeWidth: strokeWidth
        )
        
        // Add state-specific indicators
        switch state {
        case .recording:
            // Filled dot in bottom-right corner for recording
            let indicatorSize: CGFloat = 4
            let indicatorRect = NSRect(
                x: rect.maxX - indicatorSize - 0.5,
                y: rect.minY + 0.5,
                width: indicatorSize,
                height: indicatorSize
            )
            NSColor.black.setFill()
            NSBezierPath(ovalIn: indicatorRect).fill()
            
        case .monitoring:
            // Small arc/wave for monitoring
            let wavePath = NSBezierPath()
            wavePath.move(to: NSPoint(x: rect.maxX - 5, y: rect.minY + 2))
            wavePath.curve(
                to: NSPoint(x: rect.maxX - 1, y: rect.minY + 2),
                controlPoint1: NSPoint(x: rect.maxX - 4, y: rect.minY + 5),
                controlPoint2: NSPoint(x: rect.maxX - 2, y: rect.minY + 5)
            )
            wavePath.lineWidth = 1.0
            wavePath.stroke()
            
        case .buffering, .processing:
            // Small ring for processing states
            let ringSize: CGFloat = 4
            let ringRect = NSRect(
                x: rect.maxX - ringSize - 0.5,
                y: rect.minY + 0.5,
                width: ringSize,
                height: ringSize
            )
            let ringPath = NSBezierPath(ovalIn: ringRect)
            ringPath.lineWidth = 1.0
            ringPath.stroke()
            
        case .paused:
            // Two small vertical bars for paused
            let barWidth: CGFloat = 1.5
            let barHeight: CGFloat = 4
            let barSpacing: CGFloat = 1.5
            let barY = rect.minY + 1
            let barX = rect.maxX - (barWidth * 2 + barSpacing) - 0.5
            
            NSColor.black.setFill()
            NSBezierPath(rect: NSRect(x: barX, y: barY, width: barWidth, height: barHeight)).fill()
            NSBezierPath(rect: NSRect(x: barX + barWidth + barSpacing, y: barY, width: barWidth, height: barHeight)).fill()
            
        case .idle:
            break
        }
    }
    
    private static func drawCrossOutline(
        center: NSPoint,
        armLength: CGFloat,
        armWidth: CGFloat,
        strokeWidth: CGFloat
    ) {
        let path = NSBezierPath()
        
        let hw = armWidth / 2  // half width
        let al = armLength     // arm length from center
        
        // Draw cross shape clockwise from top-left corner of top arm
        path.move(to: NSPoint(x: center.x - hw, y: center.y + hw))
        path.line(to: NSPoint(x: center.x - hw, y: center.y + al))
        path.line(to: NSPoint(x: center.x + hw, y: center.y + al))
        path.line(to: NSPoint(x: center.x + hw, y: center.y + hw))
        path.line(to: NSPoint(x: center.x + al, y: center.y + hw))
        path.line(to: NSPoint(x: center.x + al, y: center.y - hw))
        path.line(to: NSPoint(x: center.x + hw, y: center.y - hw))
        path.line(to: NSPoint(x: center.x + hw, y: center.y - al))
        path.line(to: NSPoint(x: center.x - hw, y: center.y - al))
        path.line(to: NSPoint(x: center.x - hw, y: center.y - hw))
        path.line(to: NSPoint(x: center.x - al, y: center.y - hw))
        path.line(to: NSPoint(x: center.x - al, y: center.y + hw))
        path.close()
        
        path.lineWidth = strokeWidth
        path.lineJoinStyle = .miter
        path.stroke()
    }
    
    private static func drawColoredIcon(in rect: NSRect) {
        // Background - dark charcoal like the inspiration
        let bgColor = NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.18, alpha: 1.0)
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.height * 0.22)
        bgColor.setFill()
        bgPath.fill()
        
        // Subtle border
        let borderColor = NSColor(calibratedRed: 0.45, green: 0.47, blue: 0.50, alpha: 1.0)
        borderColor.setStroke()
        bgPath.lineWidth = rect.width * 0.015
        bgPath.stroke()
        
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let armLength = rect.width * 0.30
        let armWidth = rect.width * 0.17
        let strokeWidth = rect.width * 0.028
        let offset = rect.width * 0.055
        
        // Silver/gray cross (offset up-left)
        let silverColor = NSColor(calibratedRed: 0.68, green: 0.70, blue: 0.73, alpha: 1.0)
        drawColoredCross(
            center: NSPoint(x: center.x - offset, y: center.y + offset),
            armLength: armLength,
            armWidth: armWidth,
            strokeWidth: strokeWidth,
            color: silverColor
        )
        
        // Blue cross (offset down-right)
        let blueColor = NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.85, alpha: 1.0)
        drawColoredCross(
            center: NSPoint(x: center.x + offset, y: center.y - offset),
            armLength: armLength,
            armWidth: armWidth,
            strokeWidth: strokeWidth,
            color: blueColor
        )
    }
    
    private static func drawColoredCross(
        center: NSPoint,
        armLength: CGFloat,
        armWidth: CGFloat,
        strokeWidth: CGFloat,
        color: NSColor
    ) {
        let path = NSBezierPath()
        
        let hw = armWidth / 2
        let al = armLength
        
        path.move(to: NSPoint(x: center.x - hw, y: center.y + hw))
        path.line(to: NSPoint(x: center.x - hw, y: center.y + al))
        path.line(to: NSPoint(x: center.x + hw, y: center.y + al))
        path.line(to: NSPoint(x: center.x + hw, y: center.y + hw))
        path.line(to: NSPoint(x: center.x + al, y: center.y + hw))
        path.line(to: NSPoint(x: center.x + al, y: center.y - hw))
        path.line(to: NSPoint(x: center.x + hw, y: center.y - hw))
        path.line(to: NSPoint(x: center.x + hw, y: center.y - al))
        path.line(to: NSPoint(x: center.x - hw, y: center.y - al))
        path.line(to: NSPoint(x: center.x - hw, y: center.y - hw))
        path.line(to: NSPoint(x: center.x - al, y: center.y - hw))
        path.line(to: NSPoint(x: center.x - al, y: center.y + hw))
        path.close()
        
        color.setStroke()
        path.lineWidth = strokeWidth
        path.lineJoinStyle = .miter
        path.stroke()
    }
}

