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

private struct PaletteButton: View {
    let action: Action
    let size: CGFloat
    let perform: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: perform) {
            Group {
                if action == .restore {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 16, weight: .medium))
                } else {
                    GeometryReader { geometry in
                        let box = CGRect(x: 1, y: 3, width: geometry.size.width - 2, height: geometry.size.height - 6)
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 2).strokeBorder(.primary, lineWidth: 1.4)
                                .frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY)
                            let inner = box.insetBy(dx: 3, dy: 3)
                            let fill = action == .center
                                ? CGRect(x: inner.midX - inner.width * 0.3, y: inner.midY - inner.height * 0.3, width: inner.width * 0.6, height: inner.height * 0.6)
                                : Layout.frame(action, window: .zero, visible: inner)
                            RoundedRectangle(cornerRadius: 0.6).fill(.primary)
                                .frame(width: fill.width, height: fill.height).offset(x: fill.minX, y: fill.minY)
                        }
                    }.frame(width: 25, height: 23)
                }
            }.frame(width: size, height: size).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .foregroundStyle(hovered ? Color.white : Color.primary)
            .background(hovered ? Color.accentColor : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovered = $0 }.help(action.title).accessibilityLabel(action.title)
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

final class PaletteController {
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
    private var pendingShow: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?
    private var lastHitTest: TimeInterval = 0
    private var enabled = false
    private var delay = 0.3
    private var itemSize: CGFloat = 34
    private var appearance: NSAppearance?
    private let system = AXUIElementCreateSystemWide()
    var perform: ((Action, AXUIElement) -> Void)?

    init() {
        AXUIElementSetMessagingTimeout(system, 0.08)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.dismiss() })
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
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: target.frame.midX, y: target.frame.midY)) }) else { dismiss(); return }
        let rect = PaletteGeometry.panelFrame(anchor: target.frame, size: size, visible: screen.visibleFrame)
        let host = NSHostingView(rootView: PaletteView(itemSize: itemSize) { [weak self] action in
            guard let self else { return }
            self.dismiss()
            self.perform?(action, target.window)
        })
        let material = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        material.material = .popover; material.blendingMode = .behindWindow; material.state = .active
        material.wantsLayer = true; material.layer?.cornerRadius = 10; material.layer?.masksToBounds = true
        host.frame = material.bounds; host.autoresizingMask = [.width, .height]
        material.addSubview(host)
        let result = makePanel(rect)
        result.appearance = appearance
        result.hasShadow = true; result.contentView = material
        panel = result
        result.orderFrontRegardless()
    }
    func dismiss() {
        showGeneration = UUID()
        if let axObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes) }
        axObserver = nil
        pendingShow?.cancel(); pendingShow = nil
        pendingClose?.cancel(); pendingClose = nil
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
        if let axObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes) }
        pendingShow?.cancel(); pendingClose?.cancel()
        panel?.orderOut(nil); shield?.orderOut(nil)
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
