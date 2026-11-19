import AppKit
import SwiftUI
import ApplicationServices

struct PaletteView: View {
    let itemSize: CGFloat
    let layout: PaletteLayout
    let perform: (Action) -> Void
    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(Array(layout.visibleBounds.rows), id: \.self) { row in
                GridRow {
                    ForEach(Array(layout.visibleBounds.columns), id: \.self) { column in
                        let action = layout.cells[row * PaletteLayout.columns + column]
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

// AppKit draws the bezel, hover, pressed and disabled states. Only the layout
// pictogram is authored; the surrounding control has no custom background colors.
private struct PaletteButton: NSViewRepresentable {
    let action: Action
    let size: CGFloat
    let perform: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(perform) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: PaletteIcon.image(for: action, itemSize: size), target: context.coordinator, action: #selector(Coordinator.click))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.setButtonType(.momentaryChange)
        button.controlSize = .regular
        button.toolTip = action.title
        button.setAccessibilityLabel(action.title)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.perform = perform
        button.image = PaletteIcon.image(for: action, itemSize: size)
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
    static func image(for action: Action, itemSize: CGFloat = 34) -> NSImage {
        let iconSize = PaletteGeometry.iconSize(itemSize: itemSize)
        if action == .restore {
            let image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: action.title)!
            image.size = iconSize
            return image
        }
        let image = NSImage(size: iconSize, flipped: true) { bounds in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.scale(by: bounds.width / 25)
            transform.concat()
            NSColor.black.setStroke()
            let box = CGRect(x: 1.5, y: 3.5, width: 22, height: 16)
            let outline = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1.4
            outline.stroke()
            let inner = box.insetBy(dx: 3, dy: 3)
            let fill = action == .center
                ? CGRect(x: inner.midX - inner.width * 0.3, y: inner.midY - inner.height * 0.3, width: inner.width * 0.6, height: inner.height * 0.6)
                : Layout.frame(action, window: .zero, visible: inner)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: fill, xRadius: 0.6, yRadius: 0.6).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

private final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// A transparent hit surface prevents the target app's own hover menu competing
// with Loom. Real button clicks are relayed after removing this surface.
private final class GreenButtonSurface: NSView {
    var relay: ((NSEvent) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { relay?(event) }
    override func rightMouseDown(with event: NSEvent) { relay?(event) }
    override func otherMouseDown(with event: NSEvent) { relay?(event) }
}

final class PaletteController: NSObject, NSPopoverDelegate {
    private struct Target {
        let window: AXUIElement
        let button: AXUIElement
        let frame: CGRect // Cocoa screen coordinates
    }
    private var axObserver: AXObserver?
    private var showGeneration = UUID()
    private var target: Target?
    private var popover: NSPopover?
    private var panel: NSWindow? { popover?.isShown == true ? popover?.contentViewController?.view.window : nil }
    private var shield: PalettePanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observers: [NSObjectProtocol] = []
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
                   self.popover != nil {
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
        guard enabled else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
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
    private func handle(_ event: NSEvent) {
        guard enabled, WindowManager.trusted else { dismiss(); return }
        if event.type == .keyDown, event.keyCode == 53, popover != nil {
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
        if popover?.isShown == true { return }
        guard !event.modifierFlags.contains(.command) else { dismiss(); return }
        if event.type == .keyDown || event.type == .scrollWheel || event.type == .leftMouseDragged { dismiss(); return }
        guard NSEvent.pressedMouseButtons == 0 else { dismiss(); return }
        let point = NSEvent.mouseLocation
        if let target {
            if target.frame.insetBy(dx: -2, dy: -2).contains(point) { return }
            dismiss()
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHitTest >= 0.06 else { return }
        lastHitTest = now
        guard let hit = hitTest(point) else { return }
        target = hit
        observe(hit)
        showShield(hit)
        let generation = UUID()
        showGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.showGeneration == generation else { return }
            self.show()
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return PaletteGeometry.cocoaFrame(CGRect(origin: origin, size: size), primaryTop: NSScreen.screens.first?.frame.maxY ?? 0)
    }
    private func hitTest(_ point: CGPoint) -> Target? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let axPoint = PaletteGeometry.axPoint(point, primaryTop: NSScreen.screens.first?.frame.maxY ?? 0)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(axPoint.x), Float(axPoint.y), &found) == .success else { return nil }
        var current = found
        for _ in 0..<4 {
            guard let node = current else { break }
            AXUIElementSetMessagingTimeout(node, 0.08)
            let subrole = value(node, kAXSubroleAttribute) as? String
            if subrole == kAXFullScreenButtonSubrole || subrole == kAXZoomButtonSubrole {
                var pid: pid_t = 0
                guard AXUIElementGetPid(node, &pid) == .success, pid == front.processIdentifier,
                      (value(node, kAXEnabledAttribute) as? Bool) != false,
                      let window = axElement(value(node, kAXWindowAttribute)), let bounds = frame(node), bounds.contains(point),
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
            if notification as String == kAXFocusedWindowChangedNotification, owner.popover != nil { return }
            owner.dismiss()
        }, &observer) == .success, let observer else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXUIElementDestroyedNotification, kAXMovedNotification, kAXResizedNotification] {
            AXObserverAddNotification(observer, target.window, notification as CFString, context)
        }
        let app = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, context)
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
        let gridSize = layout.visibleBounds.size(itemSize: itemSize)
        let size = CGSize(width: gridSize.width + 16, height: gridSize.height + 16)
        guard let anchor = shield?.contentView, anchor.window != nil else { dismiss(); return }
        let host = NSHostingView(rootView: PaletteView(itemSize: itemSize, layout: layout) { [weak self] action in
            guard let self else { return }
            self.execute(action, on: target.window)
        })
        host.frame = CGRect(origin: .zero, size: size)
        let controller = NSViewController()
        controller.view = host
        controller.preferredContentSize = size
        let popup = NSPopover()
        popup.contentViewController = controller
        popup.contentSize = size
        // Aqua alone overrides NSPopover's vibrant content appearance and can
        // flatten its material. Use the corresponding native vibrant appearance.
        let resolved = (appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
        popup.appearance = NSAppearance(named: resolved == .darkAqua ? .vibrantDark : .vibrantLight)
        popup.behavior = .applicationDefined
        popup.animates = false
        popup.delegate = self
        popover = popup
        // NSPopover owns all visible chrome: native background, arrow, corners,
        // border, shadow and edge placement. No custom material or layer clipping.
        popup.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        if popup.isShown {
            // The palette is nonactivating: the source app keeps its colored
            // traffic lights and keyboard focus while the user chooses a layout.
            // Do not move the popover window after AppKit has placed its arrow.
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                activate(target.window)
            }
        } else { dismiss() }
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
        guard popover?.isShown == true, let target else { return false }
        execute(action, on: target.window)
        return true
    }
    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === popover else { return }
        dismiss()
    }
    func dismiss() {
        showGeneration = UUID()
        if let axObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes) }
        axObserver = nil
        pendingShow?.cancel(); pendingShow = nil
        let closing = popover
        popover = nil
        closing?.delegate = nil
        closing?.close()
        shield?.orderOut(nil); shield = nil
        target = nil
    }
    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
    }
    deinit {
        if let axObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes) }
        pendingShow?.cancel()
        popover?.delegate = nil
        popover?.close()
        shield?.orderOut(nil)
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
