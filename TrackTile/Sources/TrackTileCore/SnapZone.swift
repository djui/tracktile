import CoreGraphics

public enum SnapZone: String, CaseIterable, Sendable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight
    case maximize

    public var displayName: String {
        switch self {
        case .topLeft: "Top Left"
        case .top: "Top Half"
        case .topRight: "Top Right"
        case .left: "Left Half"
        case .center: "Center"
        case .right: "Right Half"
        case .bottomLeft: "Bottom Left"
        case .bottom: "Bottom Half"
        case .bottomRight: "Bottom Right"
        case .maximize: "Fill Screen"
        }
    }
}

public enum CenterSizing: Sendable, Equatable {
    /// Keeps the window's size, shrunk to fit if needed.
    case keepCurrent
    /// Sizes the window to this fraction (0...1) of the usable screen area.
    case fraction(CGFloat)
}

public struct LayoutOptions: Sendable, Equatable {
    /// Space between windows and around the screen edges, in points.
    public var gap: CGFloat
    public var centerSizing: CenterSizing

    public init(gap: CGFloat = 0, centerSizing: CenterSizing = .keepCurrent) {
        self.gap = gap
        self.centerSizing = centerSizing
    }
}

extension SnapZone {
    /// The target frame in Cocoa screen coordinates (bottom-left origin, y up).
    ///
    /// - Parameters:
    ///   - visibleFrame: The screen's `visibleFrame`, excluding menu bar and Dock.
    ///   - currentSize: The window's size, used by `.center` with `.keepCurrent`.
    public func frame(in visibleFrame: CGRect, currentSize: CGSize, options: LayoutOptions = .init()) -> CGRect {
        let gap = max(0, options.gap)
        let area = visibleFrame.insetBy(dx: gap, dy: gap)
        let halfWidth = (area.width - gap) / 2
        let halfHeight = (area.height - gap) / 2
        let leftX = area.minX
        let rightX = area.minX + halfWidth + gap
        let bottomY = area.minY
        let topY = area.minY + halfHeight + gap

        let rect: CGRect = switch self {
        case .topLeft: CGRect(x: leftX, y: topY, width: halfWidth, height: halfHeight)
        case .top: CGRect(x: leftX, y: topY, width: area.width, height: halfHeight)
        case .topRight: CGRect(x: rightX, y: topY, width: halfWidth, height: halfHeight)
        case .left: CGRect(x: leftX, y: bottomY, width: halfWidth, height: area.height)
        case .right: CGRect(x: rightX, y: bottomY, width: halfWidth, height: area.height)
        case .bottomLeft: CGRect(x: leftX, y: bottomY, width: halfWidth, height: halfHeight)
        case .bottom: CGRect(x: leftX, y: bottomY, width: area.width, height: halfHeight)
        case .bottomRight: CGRect(x: rightX, y: bottomY, width: halfWidth, height: halfHeight)
        case .maximize: area
        case .center: Self.centered(in: area, currentSize: currentSize, sizing: options.centerSizing)
        }
        return rect.rounded
    }

    private static func centered(in area: CGRect, currentSize: CGSize, sizing: CenterSizing) -> CGRect {
        let size: CGSize = switch sizing {
        case .keepCurrent:
            CGSize(width: min(currentSize.width, area.width), height: min(currentSize.height, area.height))
        case let .fraction(fraction):
            CGSize(width: area.width * min(max(fraction, 0.1), 1), height: area.height * min(max(fraction, 0.1), 1))
        }
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }
}

extension CGRect {
    var rounded: CGRect {
        CGRect(x: origin.x.rounded(), y: origin.y.rounded(), width: size.width.rounded(), height: size.height.rounded())
    }
}
