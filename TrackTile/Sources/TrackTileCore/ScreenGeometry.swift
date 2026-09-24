import CoreGraphics

/// Conversions between Cocoa screen coordinates (origin at the bottom-left of
/// the primary display, y up) and Accessibility/Quartz coordinates (origin at
/// the top-left of the primary display, y down).
public enum ScreenGeometry {
    public static func flip(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func flip(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}
