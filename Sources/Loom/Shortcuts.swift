import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    let key: UInt32
    let modifiers: UInt32
    var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        let names: [UInt32: String] = [123:"←",124:"→",125:"↓",126:"↑",36:"↩",51:"⌫",53:"Esc",49:"Space"]
        if let name = names[key] { return text + name }
        return text + Self.keyName(key)
    }
    private static func keyName(_ key: UInt32) -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "Key \(key)" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
        var dead: UInt32 = 0; var length = 0; var chars = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(layout, UInt16(key), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 8, &length, &chars)
        return status == noErr && length > 0 ? String(utf16CodeUnits: chars, count: length).uppercased() : "Key \(key)"
    }
    static func capture(_ event: NSEvent) -> Shortcut {
        var flags: UInt32 = 0
        if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
        if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
        return Shortcut(key: UInt32(event.keyCode), modifiers: flags)
    }
}

final class Shortcuts {
    static let defaults: [Action: Shortcut] = Dictionary(uniqueKeysWithValues:
        ([Action.left: UInt32(123), .right: 124, .top: 126, .bottom: 125, .maximize: 36, .center: 8, .restore: 51, .nextDisplay: 45])
            .map { ($0.key, Shortcut(key: $0.value, modifiers: UInt32(controlKey | optionKey))) })
    private var refs: [Action: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    var bindings: [Action: Shortcut] = [:]
    var onAction: ((Action) -> Void)?
    let signature: OSType = 0x4C4F4F4D
    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<Shortcuts>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == owner.signature, id.id > 0, Int(id.id) <= Action.allCases.count else { return OSStatus(eventNotHandledErr) }
            owner.onAction?(Action.allCases[Int(id.id) - 1])
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if let data = UserDefaults.standard.data(forKey: "shortcuts"), let stored = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            for (name, shortcut) in stored { if let action = Action(rawValue: name) { bindings[action] = shortcut } }
            if bindings.count != stored.count {
                // Remove retired actions without changing retained or cleared bindings.
                let retained = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
                if let data = try? JSONEncoder().encode(retained) { UserDefaults.standard.set(data, forKey: "shortcuts") }
            }
        } else { bindings = Self.defaults }
        // Add new actions once without overwriting custom bindings or restoring
        // shortcuts that the user deliberately cleared on subsequent launches.
        if !UserDefaults.standard.bool(forKey: "verticalHalvesMigrated") {
            for action in [Action.top, .bottom] {
                if bindings[action] == nil, let shortcut = Self.defaults[action], !bindings.values.contains(shortcut) {
                    bindings[action] = shortcut
                }
            }
            let values = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
            if let data = try? JSONEncoder().encode(values) {
                UserDefaults.standard.set(data, forKey: "shortcuts")
                UserDefaults.standard.set(true, forKey: "verticalHalvesMigrated")
            }
        }
    }
    func activate() -> [String] {
        var failures: [String] = []
        for (action, shortcut) in bindings { do { try register(shortcut, for: action) } catch { failures.append(action.title) } }
        return failures
    }
    private func register(_ shortcut: Shortcut, for action: Action) throws {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: UInt32(Action.allCases.firstIndex(of: action)! + 1))
        guard RegisterEventHotKey(shortcut.key, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref else {
            throw LoomError(message: "快捷键无法注册，可能已被系统或其他应用占用。原绑定已保留。")
        }
        if let old = refs[action] { UnregisterEventHotKey(old) }
        refs[action] = ref
    }
    func update(_ shortcut: Shortcut?, for action: Action) throws {
        if bindings[action] == shortcut { return }
        if let shortcut {
            guard shortcut.modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else { throw LoomError(message: "请至少包含 Control、Option 或 Command 中的一个修饰键。") }
            if let conflict = bindings.first(where: { $0.key != action && $0.value == shortcut }) {
                throw LoomError(message: "快捷键冲突：\(shortcut.label) 已用于“\(conflict.key.title)”。请使用其他组合键，或先清除该操作的快捷键。原绑定已保留。")
            }
            try register(shortcut, for: action)
            bindings[action] = shortcut
        } else {
            if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
            bindings.removeValue(forKey: action)
        }
        let values = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(try JSONEncoder().encode(values), forKey: "shortcuts")
    }
    deinit { for ref in refs.values { UnregisterEventHotKey(ref) }; if let handler { RemoveEventHandler(handler) } }
}
