import AppKit

extension NSColor {
    var hexString: String? {
        guard let color = usingColorSpace(.sRGB) else { return nil }
        // Wide-gamut picks land outside 0...1 in sRGB.
        let channel = { (value: CGFloat) in Int(round(min(max(value, 0), 1) * 255)) }
        return String(format: "#%02X%02X%02X", channel(color.redComponent), channel(color.greenComponent), channel(color.blueComponent))
    }

    convenience init?(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
