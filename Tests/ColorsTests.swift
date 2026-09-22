import AppKit
import Testing
@testable import Memos

@Suite struct ColorsTests {
    @Test func hexRoundTrips() {
        let color = NSColor(hexString: "#FCB827")
        #expect(color?.hexString == "#FCB827")
        #expect(NSColor(hexString: "1a2B3c")?.hexString == "#1A2B3C")
    }

    @Test func outOfGamutComponentsClamp() {
        let color = NSColor(displayP3Red: 1.2, green: -0.1, blue: 0.5, alpha: 1)
        #expect(color.hexString?.hasPrefix("#FF00") == true)
    }

    @Test func standardAccentIsOneColorInBothAppearances() {
        var light: String?
        var dark: String?
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { light = Accent.standardColor.hexString }
        NSAppearance(named: .vibrantDark)!.performAsCurrentDrawingAppearance { dark = Accent.standardColor.hexString }
        #expect(light == "#FCB827")
        #expect(dark == "#FCB827")
    }

    @Test func malformedHexIsRejected() {
        #expect(NSColor(hexString: "#FFD60") == nil)
        #expect(NSColor(hexString: "#GGGGGG") == nil)
    }
}
