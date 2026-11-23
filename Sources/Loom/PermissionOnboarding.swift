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

// Figma frames are 1200 × 800 at 2×; render at 600 × 400 logical points.
struct PermissionOnboardingView: View {
    @ObservedObject var model: PermissionOnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPostponeReminder = false
    var resources: URL? = Bundle.main.resourceURL?.appendingPathComponent("Onboarding")
    let finish: () -> Void
    private let secondary = Color(red: 128 / 255, green: 128 / 255, blue: 128 / 255)

    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 0) {
                // Shared identity: never replace or fade the Loom icon on a state change.
                ZStack(alignment: .topLeading) {
                    asset("AppIcon")
                        .resizable()
                        .frame(width: 188, height: 188)
                        .position(x: 300, y: 114)
                    if model.trusted {
                        asset("Success")
                            .resizable()
                            .frame(width: 45.333333, height: 45.333333)
                            .position(x: 344, y: 153)
                            .transition(.opacity)
                    }
                }
                .frame(height: 196)
                .accessibilityHidden(true)
                ZStack {
                    page(trusted: model.trusted)
                        .id(model.trusted)
                        .transition(.opacity)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 600, height: 400)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.36), value: model.trusted)
        .alert("稍后可在设置中授权", isPresented: $showPostponeReminder) {
            Button("知道了") { finish() }
        } message: {
            Text("之后可点击菜单栏中的 Loom 图标 → 设置 → 权限 → 打开系统设置，在“辅助功能”中开启 Loom。")
        }
    }

    private func asset(_ name: String) -> Image {
        guard let url = resources?.appendingPathComponent(name).appendingPathExtension("png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing onboarding asset: \(name)")
        }
        return Image(nsImage: image)
    }

    private func page(trusted: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(trusted ? "Good！ Loom 已准备就绪" : "允许 Loom 管理窗口")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(height: 25)
                    .accessibilityAddTraits(.isHeader)
                Text(trusted
                     ? "你现在可以通过菜单栏图标或快捷键调整窗口，让我们开始吧！"
                     : "Loom 需要辅助功能权限来移动窗口和调整大小，不读取窗口内容，请尽管放心～")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 20)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
            VStack(spacing: 16) {
                Button {
                    if trusted { finish() } else { model.authorize() }
                } label: {
                    Text(trusted ? "开始使用" : "前往授权")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 222, height: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                if !trusted {
                    Button("稍后设置") { showPostponeReminder = true }
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(secondary)
                        .buttonStyle(.plain)
                        .frame(height: 17)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.bottom, trusted ? 52 : 30)
        }
        .disabled(trusted != model.trusted)
        .accessibilityHidden(trusted != model.trusted)
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(configuration.isPressed ? Color(white: 0.2) : .black, in: Capsule())
    }
}

final class PermissionOnboardingController: NSWindowController, NSWindowDelegate {
    private let model: PermissionOnboardingModel
    init(onTrustChanged: @escaping (Bool) -> Void) {
        model = PermissionOnboardingModel(onTrustChanged: onTrustChanged)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
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
