import AppKit
import SwiftUI
import ApplicationServices

struct PaletteView: View {
    let itemSize: CGFloat
    let perform: (Action) -> Void
    private let actions: [Action] = [.maximize, .left, .right, .top, .bottom, .center, .restore]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(actions, id: \.self) { action in
                PaletteButton(action: action, size: itemSize) { perform(action) }
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
        let button = NSButton(image: icon(), target: context.coordinator, action: #selector(Coordinator.click))
        button.bezelStyle = .recessed
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.setButtonType(.momentaryPushIn)
        button.controlSize = .regular
        button.toolTip = action.title
        button.setAccessibilityLabel(action.title)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.perform = perform
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
    final class Coordinator: NSObject {
        var perform: () -> Void
        init(_ perform: @escaping () -> Void) { self.perform = perform }
        @objc func click() { perform() }
    }
    private func icon() -> NSImage {
        if action == .restore {
            return NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: action.title)!
        }
        let image = NSImage(size: NSSize(width: 25, height: 23), flipped: true) { _ in
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
    private var pendingClose: DispatchWorkItem?
    private var lastHitTest: TimeInterval = 0
    private var enabled = false
    private var delay = 0.3
    private var itemSize: CGFloat = 34
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
                   app.processIdentifier == ProcessInfo.processInfo.processIdentifier, self.popover != nil { return }
                self.dismiss()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss() })
    }
    func configure(enabled: Bool, delay: Double, itemSize: CGFloat, appearance: NSAppearance?) {
        self.enabled = enabled
        self.delay = min(max(delay, 0.15), 1)
        self.itemSize = min(max(itemSize, 30), 44)
        self.appearance = appearance
        dismiss()
        removeMonitors()
        guard enabled else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53, self.target != nil { self.dismiss(); return nil }
            self.handle(event)
            return event
        }
    }
    private func handle(_ event: NSEvent) {
        guard enabled, WindowManager.trusted, !event.modifierFlags.contains(.command) else { dismiss(); return }
        if event.type == .keyDown || event.type == .scrollWheel || event.type == .leftMouseDragged { dismiss(); return }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            if event.window !== panel && event.window !== shield { dismiss() }
            return
        }
        guard NSEvent.pressedMouseButtons == 0 else { dismiss(); return }
        let point = NSEvent.mouseLocation
        if let target {
            let inside = panel.map { PaletteGeometry.containsPointer(point, anchor: target.frame, panel: $0.frame) }
                ?? target.frame.insetBy(dx: -2, dy: -2).contains(point)
            if inside { pendingClose?.cancel(); pendingClose = nil; return }
            if panel != nil {
                if pendingClose == nil {
                    let close = DispatchWorkItem { [weak self] in self?.dismiss() }
                    pendingClose = close
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: close)
                }
                return
            }
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
        guard AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            Unmanaged<PaletteController>.fromOpaque(context).takeUnretainedValue().dismiss()
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
        let size = CGSize(width: itemSize * 7 + 4 * 6 + 16, height: itemSize + 16)
        guard let anchor = shield?.contentView, anchor.window != nil else { dismiss(); return }
        let host = NSHostingView(rootView: PaletteView(itemSize: itemSize) { [weak self] action in
            guard let self else { return }
            self.dismiss()
            self.perform?(action, target.window)
        })
        host.frame = CGRect(origin: .zero, size: size)
        let controller = NSViewController()
        controller.view = host
        controller.preferredContentSize = size
        let popup = NSPopover()
        popup.contentViewController = controller
        popup.contentSize = size
        popup.appearance = appearance
        popup.behavior = .applicationDefined
        popup.animates = false
        popup.delegate = self
        popover = popup
        // NSPopover owns all visible chrome: native background, arrow, corners,
        // border, shadow and edge placement. No custom material or layer clipping.
        popup.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        if !popup.isShown { dismiss() }
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
        pendingClose?.cancel(); pendingClose = nil
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
        pendingShow?.cancel(); pendingClose?.cancel()
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
