import Foundation

enum WindowFrameAdjustment {
    // Some applications clamp a resize to the space remaining at the old origin.
    // Move first using the accepted size, then retry the requested size at its new origin.
    static func apply(_ requested: CGRect, in destination: CGRect, resize: Bool,
                      read: () -> CGRect?, setSize: (CGSize) throws -> Void,
                      setPosition: (CGPoint) throws -> Void) rethrows {
        if resize { try setSize(requested.size) }
        var accepted = requested
        if let actual = read() { accepted.size = actual.size }
        try setPosition(Layout.fit(accepted, in: destination).origin)
        if resize, let actual = read(),
           abs(actual.width - requested.width) > 1 || abs(actual.height - requested.height) > 1 {
            try setSize(requested.size)
            if let actual = read() { accepted.size = actual.size }
            try setPosition(Layout.fit(accepted, in: destination).origin)
        }
    }
}
