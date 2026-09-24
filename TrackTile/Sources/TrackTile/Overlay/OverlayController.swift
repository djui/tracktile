import AppKit
import SwiftUI

@MainActor
@Observable
final class OverlayModel {
    /// Outline frame in the panel's SwiftUI coordinates (top-left origin).
    var rect: CGRect?
    var label: String?
    var isRejected = false
    var shakes: CGFloat = 0
}

/// Shows the live outline of where the window will land.
///
/// A single click-through panel covers the target screen; the outline inside
/// it animates between candidate frames.
@MainActor
final class OverlayController {
    private let model = OverlayModel()
    private let panel: NSPanel
    private var screenFrame: CGRect = .zero
    private var hideGeneration = 0

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: OutlineView(model: model))
    }

    /// Places the outline on the window's current frame without animating, so
    /// the first zone animates out of the window itself.
    func begin(from windowFrame: CGRect, on screen: NSScreen) {
        hideGeneration += 1
        attach(to: screen)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.isRejected = false
            model.label = nil
            model.rect = local(windowFrame)
        }
        panel.orderFrontRegardless()
    }

    func show(_ frame: CGRect, label: String, on screen: NSScreen) {
        hideGeneration += 1
        attach(to: screen)
        model.isRejected = false
        model.label = label
        model.rect = local(frame)
        panel.orderFrontRegardless()
    }

    func hide() {
        hideGeneration += 1
        let generation = hideGeneration
        withAnimation(.easeOut(duration: 0.15)) {
            model.rect = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    /// Shakes a red outline to signal that the window can't be snapped.
    func reject(_ frame: CGRect?, on screen: NSScreen) {
        hideGeneration += 1
        attach(to: screen)
        let visible = screen.visibleFrame
        let rect = frame ?? CGRect(x: visible.midX - 120, y: visible.midY - 80, width: 240, height: 160)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.isRejected = true
            model.label = "Can't snap this window"
            model.rect = local(rect)
        }
        panel.orderFrontRegardless()
        withAnimation(.linear(duration: 0.4)) {
            model.shakes += 1
        }
        let generation = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation else { return }
                self.hide()
            }
        }
    }

    private func attach(to screen: NSScreen) {
        guard screen.frame != screenFrame else { return }
        screenFrame = screen.frame
        panel.setFrame(screen.frame, display: false)
    }

    private func local(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

private struct OutlineView: View {
    let model: OverlayModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let rect = model.rect {
                outline
                    .frame(width: rect.width, height: rect.height)
                    .modifier(ShakeEffect(shakes: model.shakes))
                    .offset(x: rect.minX, y: rect.minY)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(duration: 0.25, bounce: 0.15), value: model.rect)
    }

    private var tint: Color { model.isRejected ? .red : .accentColor }

    private var outline: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(tint.opacity(0.12)))
            .overlay(shape.strokeBorder(tint.opacity(0.9), lineWidth: 3))
            .overlay {
                if let label = model.label {
                    Text(label)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
    }
}

private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(shakes * .pi * 6), y: 0))
    }
}
