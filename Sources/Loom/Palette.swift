import AppKit
import SwiftUI
import ApplicationServices
import QuartzCore

struct PaletteView: View {
    let itemSize: CGFloat
    let layout: PaletteLayout
    let perform: (Action) -> Void
    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(Array(layout.visibleBounds.rows), id: \.self) { row in
                GridRow {
                    ForEach(Array(layout.visibleBounds.columns), id: \.self) { column in
                        let action = layout.visibleAction(at: row * PaletteLayout.columns + column)
                        if let action {
                            PaletteButton(action: action, size: itemSize) { perform(action) }
                                .frame(width: itemSize, height: itemSize)
                        } else {
                            Color.clear.frame(width: itemSize, height: itemSize).accessibilityHidden(true)
                        }
                    }
                }
            }
        }.padding(8).fixedSize()
    }
}

// Keep native button hit testing/actions while matching the system tiling
// palette's explicit blue-hover/white-icon treatment in a nonactivating window.
private final class PaletteButtonControl: NSButton {
    private var hoverTracking: NSTrackingArea?
    private var hovered = false
    private var paletteAction: Action?
    private var paletteSize: CGFloat = 34
    private var normalIcon: NSImage?
    private var hoverIcon: NSImage?
    override var allowsVibrancy: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func configure(action: Action, size: CGFloat) {
        let iconsChanged = paletteAction != action || paletteSize != size || normalIcon == nil
        paletteAction = action
        paletteSize = size
        wantsLayer = true
        layer?.cornerRadius = 7
        if iconsChanged { prepareIcons() }
        refreshStyle()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTracking = area
        if let window {
            hovered = bounds.contains(convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
        }
        refreshStyle()
    }
    func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        refreshStyle()
        displayIfNeeded()
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        prepareIcons()
        refreshStyle()
    }
    private func prepareIcons() {
        guard let paletteAction else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            normalIcon = PaletteIcon.image(for: paletteAction, itemSize: paletteSize, ink: PaletteChromeView.iconColor)
            hoverIcon = PaletteIcon.image(for: paletteAction, itemSize: paletteSize, ink: .white)
            // Rasterize both states before pointer entry, rather than on hover.
            for icon in [normalIcon, hoverIcon].compactMap({ $0 }) {
                var rect = CGRect(origin: .zero, size: icon.size)
                _ = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            }
        }
    }
    private func refreshStyle() {
        guard paletteAction != nil else { return }
        let active = hovered && isEnabled
        // Layer-backed AppKit views otherwise interpolate this color change.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = active ? NSColor(srgbRed: 82 / 255, green: 159 / 255, blue: 1, alpha: 1).cgColor : NSColor.clear.cgColor
        image = active ? hoverIcon : normalIcon
        CATransaction.commit()
        needsDisplay = true
    }
}

private struct PaletteButton: NSViewRepresentable {
    let action: Action
    let size: CGFloat
    let perform: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(perform) }
    func makeNSView(context: Context) -> NSButton {
        let button = PaletteButtonControl(image: PaletteIcon.image(for: action, itemSize: size, ink: PaletteChromeView.iconColor), target: context.coordinator, action: #selector(Coordinator.click))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.contentTintColor = nil
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.setButtonType(.momentaryChange)
        button.controlSize = .regular
        button.toolTip = action.title
        button.setAccessibilityLabel(action.title)
        button.configure(action: action, size: size)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.perform = perform
        (button as? PaletteButtonControl)?.configure(action: action, size: size)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
    final class Coordinator: NSObject {
        var perform: () -> Void
        init(_ perform: @escaping () -> Void) { self.perform = perform }
        @objc func click() { perform() }
    }
}

enum PaletteIcon {
    static func image(for action: Action, itemSize: CGFloat = 34, ink: NSColor? = nil) -> NSImage {
        let iconSize = PaletteGeometry.iconSize(itemSize: itemSize)
        let image = NSImage(size: iconSize, flipped: true) { bounds in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.scale(by: bounds.width / 25)
            transform.concat()
            (ink ?? .black).setStroke()
            if action == .restore {
                let arrow = NSBezierPath()
                arrow.lineWidth = 1.7
                arrow.lineCapStyle = .round
                arrow.lineJoinStyle = .round
                arrow.move(to: CGPoint(x: 9, y: 4))
                arrow.line(to: CGPoint(x: 2.5, y: 10))
                arrow.line(to: CGPoint(x: 9, y: 16))
                arrow.move(to: CGPoint(x: 3, y: 10))
                arrow.line(to: CGPoint(x: 15, y: 10))
                arrow.curve(to: CGPoint(x: 15, y: 20), controlPoint1: CGPoint(x: 24, y: 10), controlPoint2: CGPoint(x: 24, y: 20))
                arrow.line(to: CGPoint(x: 12, y: 20))
                arrow.stroke()
                return true
            }
            let box = CGRect(x: 1.5, y: 3.5, width: 22, height: 16)
            let outline = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1.4
            outline.stroke()
            let inner = box.insetBy(dx: 3, dy: 3)
            let fill = action == .center
                ? CGRect(x: inner.midX - inner.width * 0.3, y: inner.midY - inner.height * 0.3, width: inner.width * 0.6, height: inner.height * 0.6)
                : Layout.frame(action, window: .zero, visible: inner)
            (ink ?? .black).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 0.6, yRadius: 0.6).fill()
            return true
        }
        image.isTemplate = ink == nil
        return image
    }
}

private final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// A transparent hit surface reduces competing hover handling. System popup
// arbitration below handles apps/OS versions where this surface is insufficient.
// Real button clicks are relayed after removing this surface.
private final class GreenButtonSurface: NSView {
    var relay: ((NSEvent) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { relay?(event) }
    override func rightMouseDown(with event: NSEvent) { relay?(event) }
    override func otherMouseDown(with event: NSEvent) { relay?(event) }
}

final class PaletteController: NSObject {
    private struct Target {
        let window: AXUIElement
        let button: AXUIElement
        let frame: CGRect // Cocoa screen coordinates
    }
    private var axObserver: AXObserver?
    private var showGeneration = UUID()
    private var target: Target?
    private var panel: PalettePanel?
    private var shield: PalettePanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var systemPopupWatch: Timer?
    private let popupQueue = DispatchQueue(label: "dev.loom.popup-check", qos: .userInitiated)
    private let hitTestQueue = DispatchQueue(label: "dev.loom.green-button-hit-test", qos: .userInitiated)
    private var hitTestInFlight = false
    private var popupCheckInFlight = false
    var menuTracking = false {
        didSet {
            guard menuTracking != oldValue else { return }
            if menuTracking {
                dismiss()
                removeMonitors()
            } else if enabled {
                installMonitors()
            }
        }
    }
    private var pendingShow: DispatchWorkItem?
    private var lastHitTest: TimeInterval = 0
    private var enabled = false
    private var delay = 0.3
    private var itemSize: CGFloat = 34
    private var layout = PaletteLayout.standard
    private var appearance: NSAppearance?
    private let system = AXUIElementCreateSystemWide()
    var perform: ((Action, AXUIElement) -> Void)?

    override init() {
        super.init()
        AXUIElementSetMessagingTimeout(system, 0.08)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if name == NSWorkspace.didActivateApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   self.panel != nil {
                    var targetPID: pid_t = 0
                    if let window = self.target?.window { AXUIElementGetPid(window, &targetPID) }
                    if app.processIdentifier == targetPID || app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
                }
                self.dismiss()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss() })
    }
    func configure(enabled: Bool, delay: Double, itemSize: CGFloat, layout: PaletteLayout, appearance: NSAppearance?) {
        self.enabled = enabled
        self.delay = min(max(delay, 0.15), 1)
        self.itemSize = min(max(itemSize, 30), 44)
        self.appearance = appearance
        self.layout = layout
        dismiss()
        removeMonitors()
        guard enabled, !menuTracking else { return }
        installMonitors()
    }
    private func installMonitors() {
        removeMonitors()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            if event.type == .mouseMoved, let panel = self.panel, event.window === panel,
               let content = panel.contentView {
                self.updateHover(in: content, screenPoint: NSEvent.mouseLocation)
                return event
            }
            // Events in Loom's settings or native menu must never initiate
            // cross-process AX hit testing before AppKit handles their hover.
            if event.type == .mouseMoved, event.window != nil, self.panel == nil { return event }
            if event.type == .keyDown, event.keyCode == 53, self.target != nil {
                let window = self.target?.window
                self.dismiss()
                if let window { self.activate(window) }
                return nil
            }
            if let panel = self.panel, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
               event.window === panel, !self.isControlClick(event) {
                let targetWindow = self.target?.window
                self.dismiss()
                if let targetWindow { self.activate(targetWindow) }
                return nil
            }
            self.handle(event)
            return event
        }
    }
    private func isControlClick(_ event: NSEvent) -> Bool {
        guard let content = event.window?.contentView else { return false }
        var hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
        while let view = hit {
            if view is NSControl { return true }
            hit = view.superview
        }
        return false
    }
    private func updateHover(in view: NSView, screenPoint: CGPoint) {
        if let button = view as? PaletteButtonControl, let window = button.window {
            let point = button.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
            button.setHovered(button.bounds.contains(point))
        }
        for child in view.subviews { updateHover(in: child, screenPoint: screenPoint) }
    }
    private func handle(_ event: NSEvent) {
        guard !menuTracking else { return }
        guard enabled, layout.hasVisibleActions else { return }
        if event.type == .keyDown, event.keyCode == 53, panel != nil {
            let targetWindow = target?.window
            dismiss()
            if let targetWindow { activate(targetWindow) }
            return
        }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            if event.window !== panel && event.window !== shield { dismiss() }
            return
        }
        // Once open, this is a click-dismissed palette, not a hover tooltip.
        // Mouse movement, modifiers and scrolling must not expire its lifetime.
        if let panel, panel.isVisible {
            if event.type == .mouseMoved, let content = panel.contentView {
                updateHover(in: content, screenPoint: NSEvent.mouseLocation)
            }
            return
        }
        guard !event.modifierFlags.contains(.command) else { dismiss(); return }
        if event.type == .keyDown || event.type == .scrollWheel || event.type == .leftMouseDragged { dismiss(); return }
        guard NSEvent.pressedMouseButtons == 0 else { dismiss(); return }
        let point = NSEvent.mouseLocation
        if let target {
            if target.frame.insetBy(dx: -2, dy: -2).contains(point) { return }
            dismiss()
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHitTest >= 0.06, !hitTestInFlight,
              let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastHitTest = now
        hitTestInFlight = true
        let generation = showGeneration
        let pid = front.processIdentifier
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        hitTestQueue.async { [weak self] in
            guard let self else { return }
            let hit = WindowManager.trusted ? self.hitTest(point, pid: pid, primaryTop: primaryTop) : nil
            let competing = hit.map {
                PaletteSystemPopup.isVisible(button: $0.button, window: $0.window, buttonFrame: $0.frame, primaryTop: primaryTop)
            } ?? false
            DispatchQueue.main.async {
                self.hitTestInFlight = false
                guard self.showGeneration == generation, self.enabled, !self.menuTracking, self.panel == nil,
                      !competing, let hit,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                      hit.frame.contains(NSEvent.mouseLocation), NSEvent.pressedMouseButtons == 0,
                      !NSEvent.modifierFlags.contains(.command) else { return }
                self.scheduleShow(hit)
            }
        }
    }
    private func scheduleShow(_ hit: Target) {
        target = hit
        observe(hit)
        showShield(hit)
        startSystemPopupWatch()
        let generation = UUID()
        showGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.showGeneration == generation else { return }
            self.show()
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func startSystemPopupWatch() {
        systemPopupWatch?.invalidate()
        // This guard exists only during a pending/open palette. AX notifications
        // handle immediate menu opening; the timer covers unreported OS popups.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let target = self.target, !self.popupCheckInFlight else { return }
            self.popupCheckInFlight = true
            let generation = self.showGeneration
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            // AX messaging can wait for another process. Never block pointer
            // tracking or native menu tracking on those synchronous IPC calls.
            self.popupQueue.async { [weak self] in
                let visible = PaletteSystemPopup.isVisible(button: target.button, window: target.window, buttonFrame: target.frame, primaryTop: primaryTop)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.popupCheckInFlight = false
                    if self.showGeneration == generation, visible { self.dismiss() }
                }
            }
        }
        systemPopupWatch = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    private func axElement(_ object: CFTypeRef?) -> AXUIElement? {
        guard let object, CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        return (object as! AXUIElement)
    }
    private func frame(_ element: AXUIElement, primaryTop: CGFloat? = nil) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return PaletteGeometry.cocoaFrame(CGRect(origin: origin, size: size), primaryTop: primaryTop ?? NSScreen.screens.first?.frame.maxY ?? 0)
    }
    private func hitTest(_ point: CGPoint, pid: pid_t, primaryTop: CGFloat) -> Target? {
        let axPoint = PaletteGeometry.axPoint(point, primaryTop: primaryTop)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(axPoint.x), Float(axPoint.y), &found) == .success else { return nil }
        var current = found
        for _ in 0..<4 {
            guard let node = current else { break }
            AXUIElementSetMessagingTimeout(node, 0.08)
            let subrole = value(node, kAXSubroleAttribute) as? String
            if subrole == kAXFullScreenButtonSubrole || subrole == kAXZoomButtonSubrole {
                var ownerPID: pid_t = 0
                guard AXUIElementGetPid(node, &ownerPID) == .success, ownerPID == pid,
                      (value(node, kAXEnabledAttribute) as? Bool) != false,
                      let window = axElement(value(node, kAXWindowAttribute)), let bounds = frame(node, primaryTop: primaryTop), bounds.contains(point),
                      (value(window, "AXFullScreen") as? Bool) != true else { return nil }
                return Target(window: window, button: node, frame: bounds)
            }
            current = axElement(value(node, kAXParentAttribute))
        }
        return nil
    }
    private func observe(_ target: Target) {
        var pid: pid_t = 0
        AXUIElementGetPid(target.window, &pid)
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, _, notification, context in
            guard let context else { return }
            let owner = Unmanaged<PaletteController>.fromOpaque(context).takeUnretainedValue()
            // Yield immediately when the target application's native menu opens.
            if notification as String == kAXMenuOpenedNotification { owner.dismiss(); return }
            if notification as String == kAXFocusedWindowChangedNotification, owner.panel != nil { return }
            owner.dismiss()
        }, &observer) == .success, let observer else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXUIElementDestroyedNotification, kAXMovedNotification, kAXResizedNotification] {
            AXObserverAddNotification(observer, target.window, notification as CFString, context)
        }
        let app = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, context)
        AXObserverAddNotification(observer, app, kAXMenuOpenedNotification as CFString, context)
        axObserver = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    private func makePanel(_ rect: CGRect) -> PalettePanel {
        let result = PalettePanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        result.isOpaque = false; result.backgroundColor = .clear
        result.hidesOnDeactivate = false
        result.isReleasedWhenClosed = false
        result.level = .popUpMenu
        result.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        result.acceptsMouseMovedEvents = true
        return result
    }
    private func showShield(_ target: Target) {
        let surface = GreenButtonSurface(frame: CGRect(origin: .zero, size: target.frame.size))
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.001).cgColor
        surface.relay = { [weak self] event in
            let original = event.cgEvent?.copy()
            self?.dismiss()
            original?.post(tap: .cghidEventTap)
        }
        let result = makePanel(target.frame)
        result.hasShadow = false; result.contentView = surface
        shield = result
        result.orderFrontRegardless()
    }
    private func show() {
        pendingShow = nil
        guard enabled, WindowManager.trusted, let target, target.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation),
              !NSEvent.modifierFlags.contains(.command), let currentFrame = frame(target.button),
              abs(currentFrame.minX - target.frame.minX) < 2, abs(currentFrame.minY - target.frame.minY) < 2 else { dismiss(); return }
        guard !PaletteSystemPopup.isVisible(button: target.button, window: target.window, buttonFrame: target.frame) else { dismiss(); return }
        let gridSize = layout.visibleBounds.size(itemSize: itemSize)
        let size = CGSize(width: gridSize.width + 16, height: gridSize.height + 16)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: target.frame.midX, y: target.frame.midY)) }) else { dismiss(); return }
        let placement = PaletteGeometry.chromePlacement(anchor: target.frame, contentSize: size, visible: screen.visibleFrame)
        let host = NSHostingView(rootView: PaletteView(itemSize: itemSize, layout: layout) { [weak self] action in
            guard let self else { return }
            self.execute(action, on: target.window)
        })
        let window = makePanel(placement.frame)
        window.appearance = appearance
        window.hasShadow = true
        window.contentView = PaletteChromeView(placement: placement, content: host)
        panel = window
        window.orderFrontRegardless()
        window.invalidateShadow()
        // The background watcher handles subsequent popup checks; synchronous
        // AX requests here would stall the first hover immediately after opening.
    }
    private func activate(_ window: AXUIElement) {
        var pid: pid_t = 0
        if AXUIElementGetPid(window, &pid) == .success {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }
    private func execute(_ action: Action, on window: AXUIElement) {
        dismiss()
        activate(window)
        perform?(action, window)
    }
    @discardableResult func performIfShown(_ action: Action) -> Bool {
        guard panel?.isVisible == true, let target else { return false }
        execute(action, on: target.window)
        return true
    }
    func dismiss() {
        systemPopupWatch?.invalidate(); systemPopupWatch = nil
        showGeneration = UUID()
        if let axObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes) }
        axObserver = nil
        pendingShow?.cancel(); pendingShow = nil
        panel?.orderOut(nil); panel = nil
        shield?.orderOut(nil); shield = nil
        target = nil
    }
    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
    }
    deinit {
        systemPopupWatch?.invalidate()
        if let axObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes) }
        pendingShow?.cancel()
        panel?.orderOut(nil)
        shield?.orderOut(nil)
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
