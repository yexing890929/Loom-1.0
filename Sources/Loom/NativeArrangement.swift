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
        let visible = WindowManager().screen(for: target)?.visibleFrame
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let available = visible.map { CGRect(x: $0.minX, y: primaryTop - $0.maxY, width: $0.width, height: $0.height) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try invoke(action, target: target, pid: pid, available: available)
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
    // These waits run only on our worker queue during a user action. AXPress
    // acknowledges a request; focus and lazily-created menu children may lag it.
    private static func waitFor<T>(_ timeout: TimeInterval, probe: () -> T?) -> T? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        repeat {
            if let result = probe() { return result }
            if ProcessInfo.processInfo.systemUptime >= deadline { return nil }
            Thread.sleep(forTimeInterval: 0.02)
        } while true
    }
    private static func frame(_ window: AXUIElement) -> CGRect? {
        guard let position = value(window, kAXPositionAttribute),
              let size = value(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    private static func waitForGeometryToSettle(_ app: AXUIElement) {
        // Keep the transaction busy while the native animation is running.
        // Completion retries are separately limited to an observed partial pair.
        // This observes the target app, not all participating apps.
        let start = ProcessInfo.processInfo.systemUptime
        var previous: [CGRect] = []
        var stableSince = start
        repeat {
            let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
            let current = windows.compactMap { frame($0) }
            let now = ProcessInfo.processInfo.systemUptime
            if current != previous { previous = current; stableSince = now }
            if !current.isEmpty, now - start >= 0.3, now - stableSince >= 0.15 { return }
            if now - start >= 1 { return }
            Thread.sleep(forTimeInterval: 0.05)
        } while true
    }
    private struct Companion {
        let id: Int
        let frame: CGRect
    }
    private static func companion(to pid: pid_t, visible: CGRect) -> Companion? {
        // Window-server front-to-back order identifies the other visible window
        // raised by native arrangement, without reading any window contents.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int,
                  owner != Int(pid), owner != Int(ProcessInfo.processInfo.processIdentifier),
                  window[kCGWindowLayer as String] as? Int == 0,
                  let id = window[kCGWindowNumber as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 100, rect.height >= 100,
                  rect.intersects(visible) else { continue }
            return Companion(id: id, frame: rect)
        }
        return nil
    }
    private static func invoke(_ action: Action, target: AXUIElement, pid: pid_t,
                               available: CGRect?, completionCompanion: Int? = nil) throws {
        let originalCompanion = available.flatMap { companion(to: pid, visible: $0) }
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
        let focused: AXUIElement? = waitFor(0.5) {
            guard let window = element(value(app, kAXFocusedWindowAttribute)), CFEqual(window, target) else { return nil }
            return window
        }
        guard focused != nil else {
            throw LoomError(message: "目标窗口尚未激活，请点击该窗口后重试。")
        }
        guard let bar = element(value(app, kAXMenuBarAttribute)),
              let windowMenu = named(NativeArrangementCommand.windowMenu, in: bar) else { throw unavailable(action) }
        var opened = false
        var invoked = false
        defer {
            // Cancelling immediately after a successful press can race the
            // system's asynchronous menu action. Cancel only abandoned menus.
            if opened && !invoked { _ = AXUIElementPerformAction(windowMenu, "AXCancel" as CFString) }
        }
        // Most AppKit apps expose the hidden submenu. Open it only if lazy
        // population requires it, then always dismiss that menu on failure.
        var move = named(NativeArrangementCommand.moveAndResize, in: windowMenu)
        if move == nil {
            opened = AXUIElementPerformAction(windowMenu, kAXPressAction as CFString) == .success
            move = waitFor(0.4) { named(NativeArrangementCommand.moveAndResize, in: windowMenu) }
        }
        guard let move else { throw unavailable(action) }
        let names = NativeArrangementCommand.titles(for: action)
        var command = named(names, in: move, enabledOnly: true)
        if command == nil {
            if !opened { opened = AXUIElementPerformAction(windowMenu, kAXPressAction as CFString) == .success }
            _ = AXUIElementPerformAction(move, kAXPressAction as CFString)
            command = waitFor(0.4) { named(names, in: move, enabledOnly: true) }
        }
        guard let command else { throw unavailable(action) }
        // A user can change windows during menu discovery. Do not arrange the
        // new foreground window accidentally.
        guard let focused = element(value(app, kAXFocusedWindowAttribute)), CFEqual(focused, target) else {
            throw LoomError(message: "目标窗口已改变，请重新选择后再试。")
        }
        // Match the activation check above. AXFocusedApplication can still
        // describe a menu-owning process while its menu is tracking, rather
        // than the workspace's foreground application.
        let stillForeground = DispatchQueue.main.sync {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        }
        guard stillForeground else {
            throw LoomError(message: "前台应用已改变，已取消系统排布。")
        }
        if let completionCompanion, let available {
            guard companion(to: pid, visible: available)?.id == completionCompanion else { return }
        }
        guard AXUIElementPerformAction(command, kAXPressAction as CFString) == .success else {
            throw LoomError(message: "应用未接受系统排布命令，请从该应用的“窗口 → 移动与调整大小”菜单确认是否可用。")
        }
        invoked = true
        waitForGeometryToSettle(app)
        if (action == .arrangeTwo || action == .arrangeTwoVertical), let available,
           let primary = frame(target) {
            let horizontal = action == .arrangeTwo
            let slot = Layout.frame(horizontal ? .left : .top, window: primary, visible: available)
            if !NativeArrangementGeometry.matches(primary, slot) {
                guard DispatchQueue.main.sync(execute: { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }),
                      let focused = element(value(app, kAXFocusedWindowAttribute)), CFEqual(focused, target) else { return }
                // A successful native press can still leave the primary oversized.
                // Correct that actual window once, then read the accepted size.
                try WindowFrameAdjustment.apply(slot, in: available, resize: true,
                    read: { frame(target) }, setSize: { requested in
                        var size = requested
                        guard AXUIElementSetAttributeValue(target, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!) == .success else {
                            throw LoomError(message: "目标应用未接受半屏尺寸，请收起侧栏或关闭窗口中的额外面板后重试。")
                        }
                    }, setPosition: { requested in
                        var point = requested
                        guard AXUIElementSetAttributeValue(target, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!) == .success else {
                            throw LoomError(message: "目标应用未接受半屏位置。")
                        }
                    })
                waitForGeometryToSettle(app)
                guard let accepted = frame(target) else { throw LoomError(message: "无法确认排布后的窗口尺寸。") }
                if accepted.width > slot.width + 20 || accepted.height > slot.height + 20 {
                    // The application enforces its own minimum dimensions.
                    // Keep the accepted layout silently; further retries cannot
                    // overcome this constraint and should not interrupt the user.
                    return
                }
            }
        }
        // The native command can leave the companion at its old constrained
        // origin on its first pass. Complete only an observed partial pair,
        // once, with the same target and companion still present.
        if completionCompanion == nil, let available,
           let primary = frame(target), let other = companion(to: pid, visible: available),
           originalCompanion?.id == other.id,
           NativeArrangementGeometry.needsCompletion(action, primary: primary, companion: other.frame, visible: available),
           DispatchQueue.main.sync(execute: { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }) {
            try invoke(action, target: target, pid: pid, available: available, completionCompanion: other.id)
        }
    }
    private static func unavailable(_ action: Action) -> LoomError {
        LoomError(message: "此应用未提供可用的系统“\(action.title)”命令。请检查“窗口 → 移动与调整大小”；也可能是系统版本或当前窗口状态不支持。")
    }
}
