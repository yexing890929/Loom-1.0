import AppKit
import ApplicationServices

// The OS's green-button popup is not exposed by one stable AX role on every
// macOS/app combination. Prefer AX shown-menu state and fall back to onscreen
// window metadata near the green button; never inspect window contents.
enum PaletteSystemPopup {
    static func isVisible(button: AXUIElement, window: AXUIElement, buttonFrame: CGRect, primaryTop: CGFloat? = nil) -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app = AXUIElementCreateApplication(pid)
        let system = AXUIElementCreateSystemWide()
        for root in [button, app, system] {
            AXUIElementSetMessagingTimeout(root, 0.03)
            var shown: CFTypeRef?
            if AXUIElementCopyAttributeValue(root, kAXShownMenuUIElementAttribute as CFString, &shown) == .success,
               let shown, CFGetTypeID(shown) == AXUIElementGetTypeID() {
                var menuPID: pid_t = 0
                if AXUIElementGetPid(shown as! AXUIElement, &menuPID) == .success, menuPID != ownPID { return true }
            }
        }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let primaryTop = primaryTop ?? NSScreen.screens.first?.frame.maxY ?? 0
        for info in windows {
            guard let owner = info[kCGWindowOwnerPID as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            let frame = PaletteGeometry.cocoaFrame(rect, primaryTop: primaryTop)
            if PaletteGeometry.isCompetingPopup(frame: frame, button: buttonFrame, layer: layer, ownerPID: owner, ownPID: Int(ownPID)) { return true }
        }
        return false
    }
}
