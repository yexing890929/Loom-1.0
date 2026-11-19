import AppKit
import ApplicationServices

// Direct native fullscreen only. Desktop half layouts are handled by WindowManager.
@MainActor
enum NativeFullScreen {
    private static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    static func perform(_ action: Action, on target: AXUIElement?) throws {
        guard WindowManager.trusted else { throw LoomError(message: "请先在系统设置中允许 Loom 使用辅助功能。") }
        guard action == .fullScreen, let window = target else { throw LoomError(message: "请先选择要进入全屏幕的应用窗口。") }
        AXUIElementSetMessagingTimeout(window, 0.3)
        guard let role = value(window, kAXRoleAttribute) as? String, role == kAXWindowRole else {
            throw LoomError(message: "目标窗口已关闭或不支持全屏幕。")
        }
        if (value(window, "AXFullScreen") as? Bool) == true { return }
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(window, "AXFullScreen" as CFString, &settable)
        guard settable.boolValue else { throw LoomError(message: "这个窗口不支持进入 macOS 全屏幕模式。") }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else {
            throw LoomError(message: "目标应用已退出。")
        }
        app.activate(options: [])
        guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else {
            throw LoomError(message: "无法选中目标窗口，请先点击该窗口后重试。")
        }
        guard AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanTrue) == .success else {
            throw LoomError(message: "应用未接受全屏幕操作，请重新选择窗口后重试。")
        }
    }
}
