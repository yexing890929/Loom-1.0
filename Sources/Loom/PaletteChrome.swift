import AppKit
import QuartzCore

// Geometry is authored, while the background blur and controls remain AppKit.
final class PaletteChromeView: NSView {
    static var iconColor: NSColor {
        NSColor(name: "LoomPaletteInk") { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(srgbRed: 0.90, green: 0.91, blue: 0.92, alpha: 1)
            }
            return NSColor(srgbRed: 49 / 255, green: 51 / 255, blue: 52 / 255, alpha: 1)
        }
    }
    private let placement: PaletteGeometry.ChromePlacement
    private let border = CAShapeLayer()
    init(placement: PaletteGeometry.ChromePlacement, content: NSView) {
        self.placement = placement
        super.init(frame: CGRect(origin: .zero, size: placement.frame.size))
        wantsLayer = true
        let material = NSVisualEffectView(frame: bounds)
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.isEmphasized = false
        material.wantsLayer = true
        let path = outline()
        let mask = CAShapeLayer()
        mask.frame = material.bounds
        mask.path = path
        material.layer?.mask = mask
        addSubview(material)
        content.frame = placement.bodyRect
        material.addSubview(content)
        border.frame = bounds
        border.path = path
        border.fillColor = NSColor.clear.cgColor
        border.lineWidth = 0.5
        layer?.addSublayer(border)
        updateBorder()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }
    private func updateBorder() {
        effectiveAppearance.performAsCurrentDrawingAppearance { border.strokeColor = NSColor.separatorColor.cgColor }
    }
    private func outline() -> CGPath {
        let body = placement.bodyRect.insetBy(dx: 0.5, dy: 0.5)
        let tip = CGPoint(x: placement.arrowTip.x, y: placement.pointsUp ? bounds.maxY - 0.5 : 0.5)
        let room = max(2, min(tip.x - body.minX, body.maxX - tip.x))
        let r = max(1, min(12, body.height / 2, room / 2))
        let half = max(1, min(11, room - r - 0.5))
        let p = CGMutablePath()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        if !placement.pointsUp {
            p.addLine(to: CGPoint(x: tip.x - half, y: body.minY))
            p.addCurve(to: tip, control1: CGPoint(x: tip.x - 5, y: body.minY), control2: CGPoint(x: tip.x - 3, y: tip.y))
            p.addCurve(to: CGPoint(x: tip.x + half, y: body.minY), control1: CGPoint(x: tip.x + 3, y: tip.y), control2: CGPoint(x: tip.x + 5, y: body.minY))
        }
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        if placement.pointsUp {
            p.addLine(to: CGPoint(x: tip.x + half, y: body.maxY))
            p.addCurve(to: tip, control1: CGPoint(x: tip.x + 5, y: body.maxY), control2: CGPoint(x: tip.x + 3, y: tip.y))
            p.addCurve(to: CGPoint(x: tip.x - half, y: body.maxY), control1: CGPoint(x: tip.x - 3, y: tip.y), control2: CGPoint(x: tip.x - 5, y: body.maxY))
        }
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        p.closeSubpath()
        return p
    }
}
