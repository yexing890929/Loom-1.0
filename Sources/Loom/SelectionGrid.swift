import AppKit
import QuartzCore

private final class SelectionGridPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionGridView: NSView {
    let grid: CGRect
    let columns: Int
    let rows: Int
    var select: ((CGRect) -> Void)?
    var cancel: (() -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    private let selectionFill = CAShapeLayer()
    private let outline = CAShapeLayer()
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(frame: CGRect, grid: CGRect, columns: Int, rows: Int) {
        self.grid = grid; self.columns = columns; self.rows = rows
        super.init(frame: frame)
        wantsLayer = true
        layer?.isGeometryFlipped = true
        selectionFill.fillColor = NSColor.white.withAlphaComponent(0.70).cgColor
        selectionFill.shadowOpacity = 0
        outline.fillColor = NSColor.clear.cgColor
        outline.strokeColor = NSColor.white.cgColor
        outline.lineWidth = 3
        outline.lineDashPattern = [4, 3]
        outline.shadowOpacity = 0
        layer?.addSublayer(selectionFill)
        layer?.addSublayer(outline)
        setAccessibilityLabel("网格框选：拖拽选择区域，松开应用；按 Escape 取消")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    func showPreview(at point: CGPoint) {
        selection = SelectionGridGeometry.selection(from: point, to: point, in: grid, columns: columns, rows: rows)
        updateOutline()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath: "lineDashPhase")
            animation.fromValue = 0
            animation.toValue = -14
            animation.duration = 0.75
            animation.repeatCount = .infinity
            outline.add(animation, forKey: "marchingAnts")
        }
    }
    func stopAnimation() { outline.removeAllAnimations() }
    private func updateOutline() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let selection {
            selectionFill.frame = selection
            outline.frame = selection
            let rect = CGRect(origin: .zero, size: selection.size).insetBy(dx: 1.5, dy: 1.5)
            let radius = min(8, min(rect.width, rect.height) / 4)
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            selectionFill.path = path
            outline.path = path
        }
        CATransaction.commit()
    }
    override func mouseMoved(with event: NSEvent) {
        guard start == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = SelectionGridGeometry.selection(from: point, to: point, in: grid, columns: columns, rows: rows)
        updateOutline()
    }
    override func resetCursorRects() { addCursorRect(grid, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.10).setFill()
        bounds.fill()
        NSColor.white.withAlphaComponent(0.5).setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = 1
        for column in 0...columns {
            let x = grid.minX + CGFloat(column) * grid.width / CGFloat(columns)
            lines.move(to: CGPoint(x: x, y: grid.minY)); lines.line(to: CGPoint(x: x, y: grid.maxY))
        }
        for row in 0...rows {
            let y = grid.minY + CGFloat(row) * grid.height / CGFloat(rows)
            lines.move(to: CGPoint(x: grid.minX, y: y)); lines.line(to: CGPoint(x: grid.maxX, y: y))
        }
        lines.stroke()
        let help = "拖拽框选窗口区域 · Esc 取消" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white]
        let size = help.size(withAttributes: attributes)
        let label = CGRect(x: grid.midX - size.width / 2, y: grid.maxY - size.height - 16, width: size.width, height: size.height)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: label.insetBy(dx: -12, dy: -6), xRadius: 8, yRadius: 8).fill()
        help.draw(in: label, withAttributes: attributes)
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard grid.contains(point) else { cancel?(); return }
        start = point
        update(point)
    }
    override func mouseDragged(with event: NSEvent) {
        guard start != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        update(point)
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        update(convert(event.locationInWindow, from: nil))
        start = nil
        guard let selection, let window else { return }
        let screenRect = window.convertToScreen(convert(selection, to: nil))
        select?(screenRect)
    }
    private func update(_ point: CGPoint) {
        guard let start else { return }
        selection = SelectionGridGeometry.selection(from: start, to: point, in: grid, columns: columns, rows: rows)
        updateOutline()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?() }
    }
    override func rightMouseDown(with event: NSEvent) { cancel?() }
}

final class SelectionGridController: NSObject, NSWindowDelegate {
    private var panel: SelectionGridPanel?
    private var observers: [NSObjectProtocol] = []
    private var sourcePID: pid_t?
    private var completion: ((CGRect) -> Void)?
    func present(on screen: NSScreen, sourcePID: pid_t, columns: Int, rows: Int, completion: @escaping (CGRect) -> Void) {
        dismiss()
        self.sourcePID = sourcePID
        self.completion = completion
        let window = SelectionGridPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.fullScreenAuxiliary, .transient]
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.delegate = self
        let visible = screen.visibleFrame
        let grid = CGRect(x: visible.minX - screen.frame.minX, y: screen.frame.maxY - visible.maxY, width: visible.width, height: visible.height)
        let view = SelectionGridView(frame: CGRect(origin: .zero, size: screen.frame.size), grid: grid,
                                     columns: SelectionGridGeometry.dimension(columns, default: 12), rows: SelectionGridGeometry.dimension(rows, default: 8))
        view.cancel = { [weak self] in self?.dismiss() }
        view.select = { [weak self] rect in
            guard let self else { return }
            let action = self.completion
            self.dismiss()
            action?(rect)
        }
        window.contentView = view
        view.showPreview(at: view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
        panel = window
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss() })
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }
    func windowDidResignKey(_ notification: Notification) { dismiss() }
    func dismiss() {
        let pid = sourcePID
        sourcePID = nil; completion = nil
        let old = panel; panel = nil
        (old?.contentView as? SelectionGridView)?.stopAnimation()
        old?.delegate = nil; old?.orderOut(nil)
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        if let pid, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        }
    }
    deinit {
        (panel?.contentView as? SelectionGridView)?.stopAnimation()
        panel?.orderOut(nil)
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
