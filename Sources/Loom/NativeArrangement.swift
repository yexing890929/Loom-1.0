import AppKit
@preconcurrency import ApplicationServices

// macOS chooses the other windows and applies its own tiling preferences.
// All menu IPC runs off the main thread; there is no idle polling or key synthesis.
enum NativeArrangement {
    private static let queue = DispatchQueue(label: "dev.loom.native-arrangement", qos: .userInitiated)
    @MainActor private static var busy = false

    @MainActor static func perform(_ action: Action, on target: AXUIElement?) async throws {
        guard #available(macOS 15.0, *) else { throw LoomError(message: "系统多窗口排布需要 macOS 15 或更新版本。") }
        guard !busy else { throw LoomError(message: "正在执行系统排布，请稍后再试。") }
        guard action.isNativeArrangement else { return }
        guard WindowManager.trusted else { throw LoomError(message: "请先在系统设置中允许 Loom 使用辅助功能。") }
        guard let target else { throw LoomError(message: "请先选择要参与排布的应用窗口。") }
        var pid: pid_t = 0
        guard AXUIElementGetPid(target, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            throw LoomError(message: "目标应用已退出或窗口已关闭。")
        }
        busy = true
        defer { busy = false }
        guard app.activate(options: []) else { throw LoomError(message: "无法激活目标应用。") }
        // Activation is asynchronous. Wait only for this explicit operation,
        // yielding the main thread so pointer tracking remains responsive.
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw LoomError(message: "目标应用尚未激活，请点击窗口后重试。")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try invoke(action, target: target, pid: pid)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func children(_ owner: AXUIElement) -> [AXUIElement] {
        (value(owner, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
    private static func items(_ owner: AXUIElement) -> [AXUIElement] {
        children(owner).flatMap { child -> [AXUIElement] in
            if value(child, kAXRoleAttribute) as? String == kAXMenuRole { return children(child) }
            return [child]
        }
    }
    private static func named(_ names: [String], in owner: AXUIElement, enabledOnly: Bool = false) -> AXUIElement? {
        items(owner).first { item in
            guard let title = value(item, kAXTitleAttribute) as? String,
                  NativeArrangementCommand.matches(title, names: names) else { return false }
            return !enabledOnly || (value(item, kAXEnabledAttribute) as? Bool) == true
        }
    }
    private static func invoke(_ action: Action, target: AXUIElement, pid: pid_t) throws {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        AXUIElementSetMessagingTimeout(target, 0.2)
        guard value(target, kAXRoleAttribute) as? String == kAXWindowRole,
              (value(target, kAXMinimizedAttribute) as? Bool) != true,
              (value(target, "AXFullScreen") as? Bool) != true else {
            throw LoomError(message: "请选择普通桌面窗口；系统全屏或最小化窗口不能参与此排布。")
        }
        guard AXUIElementPerformAction(target, kAXRaiseAction as CFString) == .success else {
            throw LoomError(message: "无法选中目标窗口，请点击该窗口后重试。")
        }
        guard let focused = element(value(app, kAXFocusedWindowAttribute)), CFEqual(focused, target) else {
            throw LoomError(message: "目标窗口尚未激活，请点击该窗口后重试。")
        }
        guard let bar = element(value(app, kAXMenuBarAttribute)),
              let windowMenu = named(NativeArrangementCommand.windowMenu, in: bar) else { throw unavailable(action) }
        var opened = false
        defer {
            if opened { _ = AXUIElementPerformAction(windowMenu, "AXCancel" as CFString) }
        }
        // Most AppKit apps expose the hidden submenu. Open it only if lazy
        // population requires it, then always dismiss that menu on failure.
        var move = named(NativeArrangementCommand.moveAndResize, in: windowMenu)
        if move == nil {
            opened = AXUIElementPerformAction(windowMenu, kAXPressAction as CFString) == .success
            move = named(NativeArrangementCommand.moveAndResize, in: windowMenu)
        }
        guard let move else { throw unavailable(action) }
        let names = NativeArrangementCommand.titles(for: action)
        var command = named(names, in: move, enabledOnly: true)
        if command == nil {
            if !opened { opened = AXUIElementPerformAction(windowMenu, kAXPressAction as CFString) == .success }
            _ = AXUIElementPerformAction(move, kAXPressAction as CFString)
            command = named(names, in: move, enabledOnly: true)
        }
        guard let command else { throw unavailable(action) }
        // A user can change windows during menu discovery. Do not arrange the
        // new foreground window accidentally.
        guard let focused = element(value(app, kAXFocusedWindowAttribute)), CFEqual(focused, target) else {
            throw LoomError(message: "目标窗口已改变，请重新选择后再试。")
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var foregroundPID: pid_t = 0
        guard let foreground = element(value(system, kAXFocusedApplicationAttribute)),
              AXUIElementGetPid(foreground, &foregroundPID) == .success, foregroundPID == pid else {
            throw LoomError(message: "前台应用已改变，已取消系统排布。")
        }
        guard AXUIElementPerformAction(command, kAXPressAction as CFString) == .success else {
            throw LoomError(message: "应用未接受系统排布命令，请从该应用的“窗口 → 移动与调整大小”菜单确认是否可用。")
        }
    }
    private static func unavailable(_ action: Action) -> LoomError {
        LoomError(message: "此应用未提供可用的系统“\(action.title)”命令。请检查“窗口 → 移动与调整大小”；也可能是系统版本或当前窗口状态不支持。")
    }
}
