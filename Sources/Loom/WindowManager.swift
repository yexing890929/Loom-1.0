import AppKit
import ApplicationServices

struct LoomError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class WindowManager {
    private struct Saved { let window: AXUIElement; let frame: CGRect }
    private var saved: [Saved] = []
    static var trusted: Bool { AXIsProcessTrusted() }
    static func openPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func rect(_ window: AXUIElement) -> CGRect? {
        var p: CFTypeRef?; var s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    func perform(_ action: Action, on target: AXUIElement?) throws {
        guard Self.trusted else { throw LoomError(message: "请先在系统设置中允许 Loom 使用辅助功能。") }
        guard let window = target, let original = rect(window) else { throw LoomError(message: "没有可调整的窗口。请先选择一个普通应用窗口。") }
        AXUIElementSetMessagingTimeout(window, 0.5)
        var full: CFTypeRef?
        AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &full)
        guard (full as? Bool) != true else { throw LoomError(message: "请先退出窗口的系统全屏模式。") }
        var movable = DarwinBoolean(false); var sizable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &movable)
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizable)
        guard movable.boolValue, (action == .center || sizable.boolValue) else { throw LoomError(message: "这个窗口不支持所需的位置或大小调整。") }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        func convert(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryTop - r.maxY, width: r.width, height: r.height) }
        let screens = NSScreen.screens.sorted { a, b in a.frame.minX == b.frame.minX ? a.frame.minY > b.frame.minY : a.frame.minX < b.frame.minX }
        let frames = screens.map { convert($0.frame) }
        guard let index = Layout.screenIndex(for: original, screens: frames) else { throw LoomError(message: "未找到可用显示器。") }
        let visible = convert(screens[index].visibleFrame)
        saved.removeAll { rect($0.window) == nil }
        let record = saved.firstIndex { CFEqual($0.window, window) }
        var desired: CGRect
        var destination = visible
        if action == .restore {
            guard let record else { throw LoomError(message: "这个窗口还没有可还原的位置。") }
            desired = saved[record].frame
            if let owner = Layout.screenIndex(for: desired, screens: frames), frames[owner].intersects(desired) {
                destination = convert(screens[owner].visibleFrame)
            }
            desired = Layout.fit(desired, in: destination)
        } else if action == .nextDisplay {
            guard screens.count > 1 else { throw LoomError(message: "目前只有一台显示器。") }
            destination = convert(screens[(index + 1) % screens.count].visibleFrame)
            desired = Layout.transfer(original, from: visible, to: destination)
        } else { desired = Layout.frame(action, window: original, visible: visible) }
        if action != .restore, record == nil { saved.append(Saved(window: window, frame: original)) }
        var size = desired.size
        if action != .center {
            guard AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!) == .success else { throw LoomError(message: "应用未接受窗口大小调整。") }
        }
        // Read back once: the app may enforce a minimum size.
        if let actual = rect(window) { desired.size = actual.size }
        var point = Layout.fit(desired, in: destination).origin
        guard AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!) == .success else { throw LoomError(message: "应用未接受窗口位置调整。") }
        if action == .restore, let record { saved.remove(at: record) }
    }
}
