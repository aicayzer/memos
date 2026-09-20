import AppKit
import Testing
@testable import Memos

@Suite struct ColorsTests {
    @Test func hexRoundTrips() {
        let color = NSColor(hexString: "#FFD60A")
        #expect(color?.hexString == "#FFD60A")
        #expect(NSColor(hexString: "1a2B3c")?.hexString == "#1A2B3C")
    }

    @Test func outOfGamutComponentsClamp() {
        let color = NSColor(displayP3Red: 1.2, green: -0.1, blue: 0.5, alpha: 1)
        #expect(color.hexString?.hasPrefix("#FF00") == true)
    }

    @Test func malformedHexIsRejected() {
        #expect(NSColor(hexString: "#FFD60") == nil)
        #expect(NSColor(hexString: "#GGGGGG") == nil)
    }
}
