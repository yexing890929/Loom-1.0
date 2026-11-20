import AppKit
import SwiftUI
import ServiceManagement
import Carbon

enum AppTheme: String, CaseIterable {
    case system = "系统", light = "浅色", dark = "深色"
    var appearance: NSAppearance? {
        switch self { case .system: return nil; case .light: return NSAppearance(named: .aqua); case .dark: return NSAppearance(named: .darkAqua) }
    }
}

final class SettingsModel: ObservableObject {
    @Published var trusted = WindowManager.trusted
    @Published var recording: Action?
    @Published var shortcutError: String?
    @Published var message = ""
    @Published var revision = 0
    @Published var login = SMAppService.mainApp.status == .enabled
    @Published var showName = UserDefaults.standard.bool(forKey: "showMenuBarName") {
        didSet { UserDefaults.standard.set(showName, forKey: "showMenuBarName"); onAppearanceChanged?() }
    }
    @Published var theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "浅色") ?? .light {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme"); onAppearanceChanged?() }
    }
    @Published var paletteEnabled = UserDefaults.standard.object(forKey: "paletteEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(paletteEnabled, forKey: "paletteEnabled"); onPaletteChanged?() }
    }
    @Published var paletteDelay = UserDefaults.standard.object(forKey: "paletteDelay") as? Double ?? 0.3 {
        didSet { UserDefaults.standard.set(paletteDelay, forKey: "paletteDelay"); onPaletteChanged?() }
    }
    @Published var paletteItemSize = UserDefaults.standard.object(forKey: "paletteItemSize") as? Double ?? 34 {
        didSet { UserDefaults.standard.set(paletteItemSize, forKey: "paletteItemSize"); onPaletteChanged?() }
    }
    @Published var paletteLayout = PaletteLayout(data: UserDefaults.standard.data(forKey: "paletteGridV1")) {
        didSet { UserDefaults.standard.set(paletteLayout.data, forKey: "paletteGridV1"); onPaletteChanged?() }
    }
    func movePaletteAction(_ action: Action, to destination: Int) {
        var updated = paletteLayout
        if updated.move(action, to: destination) { paletteLayout = updated }
    }
    var onPaletteChanged: (() -> Void)?
    var onAppearanceChanged: (() -> Void)?
    let shortcuts: Shortcuts
    var monitor: Any?
    init(_ shortcuts: Shortcuts) { self.shortcuts = shortcuts }
    func record(_ action: Action) {
        stopRecording(); recording = action; message = "请按下快捷键，Esc 取消。"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stopRecording(); self.message = ""; return nil }
            self.saveRecordedShortcut(Shortcut.capture(event), for: action)
            return nil
        }
    }
    func saveRecordedShortcut(_ shortcut: Shortcut, for action: Action) {
        stopRecording()
        message = ""
        do { try shortcuts.update(shortcut, for: action); revision += 1 }
        catch { shortcutError = error.localizedDescription }
    }
    func stopRecording() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = nil }
    func clear(_ action: Action) {
        stopRecording()
        do { try shortcuts.update(nil, for: action); revision += 1; message = "快捷键已清除。" } catch { message = error.localizedDescription }
    }
    func reset(_ action: Action) {
        stopRecording()
        do {
            try shortcuts.update(Shortcuts.defaults[action], for: action)
            revision += 1
            message = ""
        } catch { shortcutError = error.localizedDescription }
    }
    func toggleLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { message = "登录启动设置失败：\(error.localizedDescription)" }
        login = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval { message = "请在系统设置的登录项中允许 Loom。"; SMAppService.openSystemSettingsLoginItems() }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let page: Page
    enum Page: String, CaseIterable {
        case general = "通用", palette = "悬浮面板", shortcuts = "快捷键", permissions = "权限", about = "关于"
        var symbol: String {
            switch self { case .general: return "gearshape"; case .palette: return "rectangle.3.group"; case .shortcuts: return "keyboard"; case .permissions: return "lock.shield"; case .about: return "info.circle" }
        }
    }
    var body: some View {
        Form {
            switch page {
            case .general:
                Section("启动") {
                    SettingsRow("开机自启动") {
                        Toggle("开机自启动", isOn: Binding(get: { model.login }, set: { model.toggleLogin($0) }))
                            .labelsHidden().toggleStyle(.switch)
                    }
                }
                Section {
                    SettingsRow("菜单栏") {
                        Picker("菜单栏", selection: $model.showName) {
                            Text("图标").tag(false)
                            Text("图标和名称").tag(true)
                        }.labelsHidden().fixedSize()
                    }
                    SettingsRow("主题", alignment: .top) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                Button { model.theme = theme } label: {
                                    ThemeThumbnail(theme: theme, selected: model.theme == theme)
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(theme.rawValue + "主题")
                                    .accessibilityAddTraits(model.theme == theme ? .isSelected : [])
                            }
                        }
                    }
                } header: {
                    Text("外观")
                }
                Section {
                    SettingsRow("应用") { Button("退出 Loom") { NSApp.terminate(nil) } }
                }
            case .palette:
                Section {
                    SettingsRow("绿点悬浮面板") {
                        Toggle("绿点悬浮面板", isOn: $model.paletteEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    SettingsRow("悬停延迟") {
                        Slider(value: $model.paletteDelay, in: 0.15...1, step: 0.05).frame(width: 160)
                        Text(String(format: "%.2f 秒", model.paletteDelay)).monospacedDigit().frame(width: 64, alignment: .trailing)
                    }.disabled(!model.paletteEnabled)
                    SettingsRow("图标大小") {
                        Slider(value: $model.paletteItemSize, in: 30...44, step: 2).frame(width: 160)
                    }.disabled(!model.paletteEnabled)
                } header: {
                    settingsHeading("悬浮面板", subtitle: "将指针停在前台应用窗口的绿色按钮上，快速选择窗口布局。")
                } footer: {
                    Text("弹出前按住 Command 可使用系统绿点菜单。面板弹出后保持显示，点击布局或空白处关闭；也可按 Esc 取消。需要辅助功能权限。")
                }
                Section {
                    PaletteGridEditor(layout: model.paletteLayout, itemSize: model.paletteItemSize, move: { action, destination in
                        model.movePaletteAction(action, to: destination)
                    }, toggleVisibility: { action in
                        model.paletteLayout.toggleVisibility(action)
                    })
                    .frame(width: model.paletteItemSize >= 44 ? nil : model.paletteLayout.size(itemSize: model.paletteItemSize).width,
                           height: model.paletteLayout.size(itemSize: model.paletteItemSize).height)
                    .frame(maxWidth: .infinity, alignment: .center)
                    HStack {
                        Spacer()
                        Button("恢复默认布局") { model.paletteLayout = .standard }
                    }
                } header: {
                    settingsHeading("布局预览", subtitle: "拖拽图标到任意格子；拖到已有图标的格子时交换位置。修改即时应用并自动保存。")
                }
            case .shortcuts:
                shortcutSection("分屏布局", actions: [.left, .right, .top, .bottom], introductoryText: "点击快捷键开始录制，按 Esc 取消。清除后仍可从菜单栏使用。")
                shortcutSection("窗口操作", actions: [.maximize, .center, .restore, .nextDisplay])
                shortcutSection("多窗口排布", actions: Action.arrangementActions)
                shortcutSection("全屏幕", actions: Action.fullScreenActions)
            case .permissions:
                Section {
                    SettingsRow("辅助功能") { Text(model.trusted ? "已授权" : "未授权").foregroundStyle(.secondary) }
                    SettingsRow("系统权限") {
                        Button("打开系统设置") { WindowManager.openPermissionSettings() }
                            .fixedSize()
                    }
                } header: {
                    settingsHeading("辅助功能权限", subtitle: "Loom 使用辅助功能权限读取窗口位置并调整大小，不读取窗口内容。请在“系统设置 → 隐私与安全性 → 辅助功能”中开启 Loom。")
                }
            case .about:
                Section {
                    SettingsRow("版本") { Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0").foregroundStyle(.secondary) }
                    SettingsRow("运行方式") { Text("本地菜单栏应用").foregroundStyle(.secondary) }
                } header: {
                    settingsHeading("Loom", subtitle: "通过快捷键和菜单栏，让当前窗口快速就位。")
                }
            }
            if !model.message.isEmpty {
                Section { Text(model.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }.formStyle(.grouped)
            .frame(minWidth: 550, minHeight: 520)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.trusted = WindowManager.trusted
                model.login = SMAppService.mainApp.status == .enabled
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in model.stopRecording() }
            .onDisappear { model.stopRecording() }
            .alert("无法设置快捷键", isPresented: Binding(get: { model.shortcutError != nil }, set: { if !$0 { model.shortcutError = nil } })) {
                Button("知道了", role: .cancel) { model.shortcutError = nil }
            } message: { Text(model.shortcutError ?? "") }
    }
    private func settingsHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(subtitle).font(.callout).fontWeight(.regular).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.textCase(nil)
    }
    private func shortcutSection(_ title: String, actions: [Action], introductoryText: String? = nil) -> some View {
        Section {
            ForEach(actions, id: \.self) { action in
                SettingsRow(action.title) {
                    HStack {
                        Button(model.recording == action ? "请按组合键" : model.shortcuts.bindings[action]?.label ?? "录制快捷键") { model.record(action) }
                            .fixedSize(horizontal: true, vertical: true)
                        if model.shortcuts.bindings[action] != Shortcuts.defaults[action] {
                            Button { model.reset(action) } label: { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(.borderless)
                                .help("恢复默认快捷键")
                                .accessibilityLabel("恢复" + action.title + "默认快捷键")
                        }
                        Button { model.clear(action) } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.borderless).disabled(model.shortcuts.bindings[action] == nil)
                            .help("清除快捷键").accessibilityLabel("清除" + action.title + "快捷键")
                    }
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 16) {
                if let introductoryText {
                    Text(introductoryText).font(.callout).fontWeight(.regular)
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text(title)
            }.textCase(nil)
        }
    }
}

// Center the complete accessory group, rather than using Form's text-baseline
// alignment for LabeledContent. Equal insets keep the row's center symmetric.
struct SettingsRow<Content: View>: View {
    let title: String
    let content: Content
    let alignment: VerticalAlignment
    init(_ title: String, alignment: VerticalAlignment = .center, @ViewBuilder content: () -> Content) {
        self.title = title
        self.alignment = alignment
        self.content = content()
    }
    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .center)
        .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
    }
}

struct ThemeThumbnail: View {
    let theme: AppTheme
    let selected: Bool
    private var dark: Bool { theme == .dark }
    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                HStack(spacing: 0) {
                    Color(white: dark ? 0.16 : 0.99)
                    Color(white: theme == .system || dark ? 0.14 : 1)
                }
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        ForEach([Color.red, .yellow, .green].indices, id: \.self) { index in
                            Circle().fill([Color.red, .yellow, .green][index]).frame(width: 6, height: 6)
                        }
                        Spacer(minLength: 0)
                    }.padding(6).background(Color.primary.opacity(0.08))
                    HStack(alignment: .top, spacing: 7) {
                        VStack(spacing: 4) {
                            ForEach(0..<3) { _ in Capsule().fill(Color.gray.opacity(0.25)).frame(width: 14, height: 4) }
                        }.frame(width: 24)
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(0..<2) { _ in RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.22)).frame(height: 6) }
                        }
                    }.padding(5)
                    Spacer(minLength: 0)
                }
            }.frame(width: 76, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            Text(theme.rawValue).font(.caption).foregroundStyle(selected ? Color.accentColor : .primary)
        }
    }
}

final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, willSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? "Loom 设置"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let manager = WindowManager()
    let palette = PaletteController()
    let shortcuts = Shortcuts()
    lazy var settings = SettingsModel(shortcuts)
    var status: NSStatusItem!
    var window: NSWindow?
    var menuTarget: AXUIElement?
    var permissionOnboarding: PermissionOnboardingController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.isVisible = true
        if let button = status.button {
            // Draw a template mark directly so the menu entry does not depend on SF Symbol availability.
            let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { bounds in
                NSColor.black.setStroke()
                let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 2.5), xRadius: 2, yRadius: 2)
                frame.lineWidth = 1.5
                frame.stroke()
                let divisions = NSBezierPath()
                divisions.lineWidth = 1.2
                divisions.move(to: NSPoint(x: 9, y: 3))
                divisions.line(to: NSPoint(x: 9, y: 15))
                divisions.move(to: NSPoint(x: 2, y: 9))
                divisions.line(to: NSPoint(x: 16, y: 9))
                divisions.stroke()
                return true
            }
            icon.isTemplate = true
            button.image = icon
            button.imagePosition = .imageOnly
            button.title = ""
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            button.toolTip = "Loom · 窗口布局与设置"
            button.setAccessibilityLabel("Loom 窗口管理菜单")
        }
        status.button?.target = self
        status.button?.action = #selector(toggleQuickPanel)
        palette.perform = { [weak self] action, window in self?.run(action, target: window) }
        settings.onPaletteChanged = { [weak self] in self?.configurePalette() }
        settings.onAppearanceChanged = { [weak self] in self?.applyAppearance() }
        applyAppearance()
        shortcuts.onAction = { [weak self] action in
            guard let self else { return }
            // Registered Carbon hotkeys are consumed before NSEvent's keyDown
            // monitor; route them through the same validation while recording.
            if let recording = self.settings.recording, let shortcut = self.shortcuts.bindings[action] {
                self.settings.saveRecordedShortcut(shortcut, for: recording)
                return
            }
            if self.palette.performIfShown(action) { return }
            self.run(action, target: self.manager.focusedWindow())
        }
        let failures = shortcuts.activate()
        if !failures.isEmpty { settings.message = "以下快捷键未能注册，请重新设置：" + failures.joined(separator: "、") }
        if PermissionOnboardingPolicy.shouldPresent(
            hasLaunched: UserDefaults.standard.bool(forKey: "hasLaunched"),
            dismissed: UserDefaults.standard.bool(forKey: PermissionOnboardingPolicy.dismissedKey),
            trusted: WindowManager.trusted
        ) {
            let guide = PermissionOnboardingController { [weak self] trusted in self?.settings.trusted = trusted }
            permissionOnboarding = guide
            guide.present()
        } else if !failures.isEmpty { showSettings() }
        UserDefaults.standard.set(true, forKey: "hasLaunched")
    }
    private func applyAppearance() {
        status.length = settings.showName ? NSStatusItem.variableLength : NSStatusItem.squareLength
        status.button?.title = settings.showName ? " Loom" : ""
        status.button?.imagePosition = settings.showName ? .imageLeading : .imageOnly
        NSApp.appearance = settings.theme.appearance
        configurePalette()
    }
    private func configurePalette() {
        palette.configure(enabled: settings.paletteEnabled, delay: settings.paletteDelay, itemSize: settings.paletteItemSize, layout: settings.paletteLayout, appearance: settings.theme.appearance)
    }
    @objc func toggleQuickPanel() {
        guard let button = status.button else { return }
        palette.dismiss()
        menuTarget = manager.focusedWindow()
        let menu = NSMenu()
        // A nil menu appearance inherits the status bar's wallpaper-dependent
        // contrast, which can be dark even when macOS uses Light appearance.
        // Resolve the application's system appearance at every menu opening.
        let resolvedName = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
        menu.appearance = settings.theme.appearance ?? NSAppearance(named: resolvedName)
        menu.autoenablesItems = false
        menu.minimumWidth = 240
        menu.font = NSFont.menuFont(ofSize: 13)
        for (index, action) in Action.allCases.filter({ !$0.isNativeFullScreen && !$0.isNativeArrangement }).enumerated() {
            if index == 4 { menu.addItem(.separator()) }
            let entry = NSMenuItem(title: action.title, action: #selector(selectLayout(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = action.rawValue
            let symbol: String
            switch action {
            case .left: symbol = "rectangle.lefthalf.filled"
            case .right: symbol = "rectangle.righthalf.filled"
            case .top: symbol = "rectangle.tophalf.filled"
            case .bottom: symbol = "rectangle.bottomhalf.filled"
            case .maximize: symbol = "rectangle.fill"
            case .center: symbol = "rectangle.center.inset.filled"
            case .restore: symbol = "arrow.uturn.backward"
            case .nextDisplay: symbol = "arrow.right"
            case .fullScreen: symbol = "arrow.up.left.and.arrow.down.right"
            case .arrangeTwo, .arrangeThree, .arrangeFour: symbol = "rectangle.split.2x2"
            }
            entry.image = [.left, .right, .top, .bottom, .maximize].contains(action)
                ? layoutMenuIcon(for: action)
                : NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            entry.image?.size = NSSize(width: 16, height: 16)
            if let binding = shortcuts.bindings[action] { applyShortcut(binding, to: entry) }
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        for action in Action.arrangementActions {
            let entry = NSMenuItem(title: action.title, action: #selector(selectLayout(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = action.rawValue
            entry.image = layoutMenuIcon(for: action)
            if let binding = shortcuts.bindings[action] { applyShortcut(binding, to: entry) }
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let fullScreenItem = NSMenuItem(title: Action.fullScreen.title, action: #selector(selectLayout(_:)), keyEquivalent: "")
        fullScreenItem.target = self
        fullScreenItem.representedObject = Action.fullScreen.rawValue
        fullScreenItem.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)
        if let binding = shortcuts.bindings[.fullScreen] { applyShortcut(binding, to: fullScreenItem) }
        menu.addItem(fullScreenItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "设置", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 Loom", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "rectangle.portrait.and.arrow.right", accessibilityDescription: nil)
        menu.addItem(quitItem)
        // Use the same image canvas for every row, including SF Symbols.
        for item in menu.items { item.image?.size = NSSize(width: 16, height: 16) }
        // Native menu tracking supplies material, corner radius, selection, keyboard
        // navigation, dismissal and screen-edge constraints as one system surface.
        palette.menuTracking = true
        defer { palette.menuTracking = false }
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX - 10, y: button.bounds.minY - 4), in: button)
    }
    private func layoutMenuIcon(for action: Action) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: NSRect(x: 2.6, y: 3.6, width: 10.8, height: 8.8), xRadius: 1.2, yRadius: 1.2)
            outline.lineWidth = 1.2
            outline.stroke()
            // Keep an empty gutter between the frame and the represented area.
            // AppKit coordinates are bottom-up, so top layouts use maxY.
            let interior = NSRect(x: 4, y: 5, width: 8, height: 6)
            if action.isNativeArrangement {
                let left = NSRect(x: interior.minX, y: interior.minY, width: 3.5, height: interior.height)
                let right = left.offsetBy(dx: 4.5, dy: 0)
                func draw(_ rect: NSRect, color: NSColor) {
                    color.setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 0.3, yRadius: 0.3).fill()
                }
                func halves(_ rect: NSRect, color: NSColor) {
                    draw(NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2.5), color: color)
                    draw(NSRect(x: rect.minX, y: rect.maxY - 2.5, width: rect.width, height: 2.5), color: color)
                }
                if action == .arrangeFour { halves(left, color: .black); halves(right, color: .black) }
                else {
                    draw(left, color: .black)
                    let secondary = NSColor.black.withAlphaComponent(0.45)
                    if action == .arrangeThree { halves(right, color: secondary) }
                    else { draw(right, color: secondary) }
                }
                return true
            }
            var fill = interior
            switch action {
            case .left: fill.size.width /= 2
            case .right: fill.size.width /= 2; fill.origin.x = interior.midX
            case .top: fill.size.height /= 2; fill.origin.y = interior.midY
            case .bottom: fill.size.height /= 2
            default: break
            }
            NSColor.black.setFill()
            NSBezierPath(roundedRect: fill, xRadius: 0.5, yRadius: 0.5).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = action.title
        return image
    }
    private func applyShortcut(_ shortcut: Shortcut, to item: NSMenuItem) {
        let special: [UInt32: String] = [
            123: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            124: String(UnicodeScalar(NSRightArrowFunctionKey)!),
            125: String(UnicodeScalar(NSDownArrowFunctionKey)!),
            126: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            36: "\r", 51: "\u{8}", 49: " ", 53: "\u{1b}"
        ]
        item.keyEquivalent = special[shortcut.key] ?? shortcut.label.filter { !"⌃⌥⇧⌘".contains($0) }.lowercased()
        var flags: NSEvent.ModifierFlags = []
        if shortcut.modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if shortcut.modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if shortcut.modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        item.keyEquivalentModifierMask = flags
    }
    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let action = Action(rawValue: name) else { return }
        run(action, target: menuTarget)
    }
    func run(_ action: Action, target: AXUIElement?) {
        if action.isNativeArrangement {
            Task { @MainActor in
                do { try await NativeArrangement.perform(action, on: target) }
                catch { showWindowError(error) }
            }
        } else if action.isNativeFullScreen {
            Task { @MainActor in
                do { try NativeFullScreen.perform(action, on: target) }
                catch { showWindowError(error) }
            }
        } else {
            do { try manager.perform(action, on: target) }
            catch { showWindowError(error) }
        }
    }
    private func showWindowError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "暂时无法调整窗口"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "知道了")
        if !WindowManager.trusted { alert.addButton(withTitle: "打开系统设置") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { WindowManager.openPermissionSettings() }
    }
    @objc func showSettings() {
        if permissionOnboarding?.window?.isVisible == true { permissionOnboarding?.close() }
        palette.dismiss()
        if window == nil {
            let tabs = SettingsTabs()
            tabs.tabStyle = .toolbar
            for page in SettingsView.Page.allCases {
                let host = NSHostingController(rootView: SettingsView(model: settings, page: page))
                host.title = page.rawValue
                let item = NSTabViewItem(viewController: host)
                item.label = page.rawValue
                item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.rawValue)
                tabs.addTabViewItem(item)
            }
            let w = NSWindow(contentViewController: tabs)
            w.toolbarStyle = .preference
            w.setContentSize(NSSize(width: 550, height: 580))
            w.title = "通用"; w.identifier = NSUserInterfaceItemIdentifier("loom.settings"); w.appearance = nil; w.styleMask = [.titled, .closable];
            w.contentMinSize = NSSize(width: 550, height: 580)
            w.contentMaxSize = NSSize(width: 550, height: 580)
            w.collectionBehavior.insert(.fullScreenNone)
            w.standardWindowButton(.miniaturizeButton)?.isEnabled = false
            w.standardWindowButton(.zoomButton)?.isEnabled = false
             w.isReleasedWhenClosed = false; w.delegate = self; w.center(); window = w
        }
        settings.trusted = WindowManager.trusted
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { settings.stopRecording() }
    func applicationWillTerminate(_ notification: Notification) {
        permissionOnboarding?.close()
        palette.dismiss()
    }
    @objc func quit() { NSApp.terminate(nil) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
