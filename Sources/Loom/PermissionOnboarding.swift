import AppKit
import SwiftUI

enum PermissionOnboardingPolicy {
    static let dismissedKey = "permissionOnboardingDismissedV1"
    static func shouldPresent(hasLaunched: Bool, dismissed: Bool, trusted: Bool) -> Bool {
        !dismissed && (!hasLaunched || !trusted)
    }
}

final class PermissionOnboardingModel: ObservableObject {
    @Published private(set) var trusted: Bool
    private var check: Timer?
    private var activationObserver: NSObjectProtocol?
    private let onTrustChanged: (Bool) -> Void
    private let permission: () -> Bool
    private let openSettings: () -> Void

    init(permission: @escaping () -> Bool = { WindowManager.trusted },
         openSettings: @escaping () -> Void = { WindowManager.openPermissionSettings() },
         onTrustChanged: @escaping (Bool) -> Void) {
        self.permission = permission
        self.openSettings = openSettings
        trusted = permission()
        self.onTrustChanged = onTrustChanged
    }
    func start() {
        stop()
        refresh()
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }
    func authorize() {
        refresh()
        guard !trusted else { return }
        openSettings()
        check?.invalidate()
        // AX offers no permission-change notification. Check only during this
        // explicit authorization session; stop as soon as it succeeds or closes.
        check = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
    }
    private func refresh() {
        trusted = permission()
        onTrustChanged(trusted)
        if trusted { check?.invalidate(); check = nil }
    }
    func stop() {
        check?.invalidate(); check = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }
    deinit { stop() }
}

private struct PermissionOnboardingView: View {
    @ObservedObject var model: PermissionOnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPostponeReminder = false
    let finish: () -> Void
    var body: some View {
        ZStack {
            page(trusted: model.trusted)
                .id(model.trusted)
                .transition(.opacity)
        }
        .frame(width: 440, height: 350)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: model.trusted)
        .alert("稍后可在设置中授权", isPresented: $showPostponeReminder) {
            Button("知道了") { finish() }
        } message: {
            Text("之后可点击菜单栏中的 Loom 图标 → 设置 → 权限 → 打开系统设置，在“辅助功能”中开启 Loom。")
        }
    }
    // Replace the complete page so the symbol, copy and actions crossfade
    // together; do not interpolate strings or slide individual buttons around.
    private func page(trusted: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: trusted ? "checkmark.circle.fill" : "macwindow")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(trusted ? Color.green : Color.accentColor)
                .frame(height: 60)
                .accessibilityHidden(true)
            Text(trusted ? "Loom 已准备就绪" : "允许 Loom 管理窗口")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(trusted
                 ? "通过菜单栏图标或快捷键调整窗口。"
                 : "Loom 需要辅助功能权限来移动窗口和调整大小，不读取窗口内容。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            VStack(spacing: 10) {
                Button {
                    if trusted { finish() } else { model.authorize() }
                } label: {
                    Text(trusted ? "开始使用" : "前往授权")
                        .font(.body.weight(.medium))
                        .frame(width: 200, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                if !trusted {
                    Button("稍后设置") { showPostponeReminder = true }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .controlSize(.large)
            .frame(height: 82, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .disabled(trusted != model.trusted)
        .accessibilityHidden(trusted != model.trusted)
    }
}

final class PermissionOnboardingController: NSWindowController, NSWindowDelegate {
    private let model: PermissionOnboardingModel
    init(onTrustChanged: @escaping (Bool) -> Void) {
        model = PermissionOnboardingModel(onTrustChanged: onTrustChanged)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 350),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Loom"
        window.identifier = NSUserInterfaceItemIdentifier("loom.permission-onboarding")
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenNone)
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: PermissionOnboardingView(model: model) { [weak self] in self?.close() })
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present() {
        model.start()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        model.stop()
        UserDefaults.standard.set(true, forKey: PermissionOnboardingPolicy.dismissedKey)
    }
}
