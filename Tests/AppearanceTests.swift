import AppKit
import Foundation
import Testing
@testable import Memos

@MainActor
@Suite struct AppearanceTests {
    private func open(_ defaults: UserDefaults) -> AppModel {
        AppModel(store: ChangeableStore([]), images: FakeImageStore(), defaults: defaults, editor: FakeEditor())
    }

    private func model(_ values: [String: Any] = [:]) -> (AppModel, UserDefaults) {
        let suite = "appearance-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        for (key, value) in values { defaults.set(value, forKey: key) }
        return (open(defaults), defaults)
    }

    @Test func freshDefaultsLookLikeThePlainWindow() {
        let (model, _) = model()
        #expect(!model.advancedAppearance)
        #expect(model.windowBlur)
        #expect(model.backdropTint == nil)
        #expect(model.backdropBlur)
        #expect(model.appearanceIsDefault)
    }

    @Test func aTintStoredBeforeTheSwitchTurnsAdvancedOn() {
        let (model, _) = model(["windowTint": "#FCB827"])
        #expect(model.advancedAppearance)
        #expect(model.backdropTint?.hexString == "#FCB827")
    }

    @Test func anExplicitSwitchBeatsAStoredTint() {
        let (model, _) = model(["windowTint": "#FCB827", "advancedAppearance": false])
        #expect(!model.advancedAppearance)
        #expect(model.backdropTint == nil)
    }

    @Test func storedAdvancedValuesDoNothingWhileAdvancedIsOff() {
        let (model, _) = model(["advancedAppearance": false, "windowTint": "#112233", "windowBlur": false])
        #expect(model.backdropTint == nil)
        #expect(model.backdropBlur)
        model.advancedAppearance = true
        #expect(model.backdropTint?.hexString == "#112233")
        #expect(!model.backdropBlur)
    }

    @Test func changesAreStoredAndRestored() {
        let (model, defaults) = model()
        model.advancedAppearance = true
        model.windowBlur = false
        #expect(defaults.bool(forKey: "advancedAppearance"))
        #expect(defaults.object(forKey: "windowBlur") as? Bool == false)
        let again = open(defaults)
        #expect(again.advancedAppearance)
        #expect(!again.windowBlur)
    }

    @Test func resetReturnsEverythingToTheDefaults() {
        let (model, defaults) = model()
        model.windowOpacity = 0.2
        model.advancedAppearance = true
        model.windowTint = .red
        model.windowBlur = false
        #expect(!model.appearanceIsDefault)
        model.resetAppearance()
        #expect(model.appearanceIsDefault)
        #expect(model.windowOpacity == AppModel.defaultWindowOpacity)
        #expect(defaults.string(forKey: "windowTint") == nil)
        #expect(defaults.bool(forKey: "windowBlur"))
        #expect(!defaults.bool(forKey: "advancedAppearance"))
    }

    @Test func eachAdvancedValueAloneIsNotTheDefault() {
        let (model, _) = model()
        model.windowBlur = false
        #expect(!model.appearanceIsDefault)
        model.windowBlur = true
        model.windowTint = .red
        #expect(!model.appearanceIsDefault)
    }
}
