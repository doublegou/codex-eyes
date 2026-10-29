import XCTest
@testable import CodexEyesCore

final class AppSettingsTests: XCTestCase {
    func testExistingPreferencesKeepNotesAndOrder() throws {
        let old = Data(#"{"privacy":true,"allowSwitching":true,"notes":{"one":"Personal"},"order":["two","one"],"pinnedSession":"session"}"#.utf8)
        let settings = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertTrue(settings.privacy)
        XCTAssertTrue(settings.allowSwitching)
        XCTAssertFalse(settings.skipSwitchConfirmation)
        XCTAssertEqual(settings.notes["one"], "Personal")
        XCTAssertEqual(settings.order, ["two", "one"])
        XCTAssertEqual(settings.pinnedSession, "session")
        XCTAssertEqual(settings.language, .simplifiedChinese)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.shortcut, .standard)
    }

    func testNewPreferencesRoundTripAndUnknownValuesDoNotDiscardNotes() throws {
        var settings = Preferences()
        settings.skipSwitchConfirmation = true
        settings.language = .english; settings.appearance = .dark
        settings.shortcut = .init(keyCode: 15, modifiers: 4096 | 2048, key: "R")
        let saved = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(Preferences.self, from: saved)
        XCTAssertTrue(restored.skipSwitchConfirmation)
        XCTAssertEqual(restored.shortcut, settings.shortcut)
        XCTAssertEqual(restored.language, .english)
        XCTAssertEqual(restored.appearance, .dark)
        let unknown = Data(#"{"notes":{"one":"Keep me"},"language":"unknown","appearance":"future","shortcut":{"keyCode":14,"modifiers":0,"key":"E"}}"#.utf8)
        let safe = try JSONDecoder().decode(Preferences.self, from: unknown)
        XCTAssertEqual(safe.notes["one"], "Keep me")
        XCTAssertEqual(safe.language, .system)
        XCTAssertEqual(safe.shortcut, .standard)
    }

    func testShortcutRequiresModifiersAndDoesNotStealBasicCommands() {
        XCTAssertTrue(PanelShortcut.standard.isValid)
        XCTAssertEqual(PanelShortcut.standard.display, "⇧⌘E")
        XCTAssertFalse(PanelShortcut(keyCode: 14, modifiers: 0, key: "E").isValid)
        XCTAssertFalse(PanelShortcut(keyCode: 12, modifiers: 256, key: "Q").isValid)
        XCTAssertFalse(PanelShortcut(keyCode: 53, modifiers: 256, key: "Esc").isValid)
        XCTAssertFalse(PanelShortcut(keyCode: 14, modifiers: UInt32.max, key: "E").isValid)
        XCTAssertTrue(PanelShortcut(keyCode: 15, modifiers: 4096 | 2048, key: "R").isValid)
    }

    func testLanguageSelectionUsesPrimarySystemLanguageWithEnglishFallback() {
        XCTAssertEqual(AppLanguage.system.identifier(preferredLanguages: ["zh-Hant-TW", "en"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.identifier(preferredLanguages: ["en-US", "zh-Hans"]), "en")
        XCTAssertEqual(AppLanguage.system.identifier(preferredLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(AppLanguage.english.identifier(preferredLanguages: ["zh-Hans"]), "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.identifier(preferredLanguages: ["en-US"]), "zh-Hans")
    }

    func testEnglishTranslationsPreserveUserValuesAndLiteralPercent() {
        let name = "李明 %@ 👋"
        XCTAssertEqual(L10n.text("管理账号", language: .english), "Manage accounts")
        XCTAssertEqual(L10n.text("可用", language: .english), "Available")
        XCTAssertEqual(L10n.text("账号 \(name)", language: .english), "Account " + name)
        XCTAssertEqual(L10n.text("剩余 \(72)%", language: .english), "72% remaining")
        XCTAssertEqual(L10n.text("\("2h")后重置", language: .english), "Resets in 2h")
        XCTAssertEqual(L10n.text("账号 \(name)", language: .simplifiedChinese), "账号 " + name)
    }
}
