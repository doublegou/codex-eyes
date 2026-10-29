import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, simplifiedChinese, english
    public func identifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .simplifiedChinese: return "zh-Hans"
        case .english: return "en"
        case .system: return preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
        }
    }
}

public enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

/// Carbon-compatible modifier bits, stored independently of AppKit for migration and validation.
public struct PanelShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var key: String
    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.key = key
    }
    public static let standard = PanelShortcut(keyCode: 14, modifiers: 256 | 512, key: "E")
    public var display: String {
        (modifiers & 4096 != 0 ? "⌃" : "") + (modifiers & 2048 != 0 ? "⌥" : "") +
        (modifiers & 512 != 0 ? "⇧" : "") + (modifiers & 256 != 0 ? "⌘" : "") + key
    }
    public var isValid: Bool {
        let allowed: UInt32 = 256 | 512 | 2048 | 4096
        guard keyCode < 128, !key.isEmpty, modifiers & ~allowed == 0,
              modifiers & (256 | 4096) != 0 else { return false }
        // Escape, Return, Tab, Delete and navigation keys remain available to native controls.
        guard ![UInt32(36), 48, 51, 53, 76, 117, 123, 124, 125, 126].contains(keyCode) else { return false }
        // Do not steal basic application commands, even when Carbon would allow registration.
        if modifiers == 256 && [UInt32(0), 6, 7, 8, 9, 12, 13, 4, 46].contains(keyCode) { return false }
        return true
    }
}

/// A normal strings-table key with positional placeholders; interpolated values are never translated.
public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public let key: String
    public let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key; arguments = stringInterpolation.arguments
    }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ literal: String) { key += literal.replacingOccurrences(of: "%", with: "%%") }
        public mutating func appendInterpolation<T>(_ value: T) {
            arguments.append(String(describing: value)); key += "%\(arguments.count)$@"
        }
    }
}

public enum L10n {
    private static let lock = NSLock()
    private static var selected = AppLanguage.simplifiedChinese
    public static var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return selected }
        set { lock.lock(); defer { lock.unlock() }; selected = newValue }
    }
    public static var locale: Locale { Locale(identifier: language.identifier()) }
    private static let resources: Bundle = {
        let name = "CodexEyes_CodexEyesCore.bundle"
        let packaged = Bundle.main.resourceURL?.appendingPathComponent(name)
        let helper = Bundle.main.executableURL?.deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/" + name)
        for url in [packaged, helper].compactMap({ $0 }) {
            if let bundle = Bundle(url: url) { return bundle }
        }
        return Bundle.module
    }()
    public static func text(_ message: LocalizedMessage, language: AppLanguage? = nil) -> String {
        let identifier = (language ?? self.language).identifier()
        let bundle = resources.path(forResource: identifier, ofType: "lproj").flatMap(Bundle.init(path:)) ?? resources
        let format = bundle.localizedString(forKey: message.key, value: message.key, table: nil)
        guard !message.arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: identifier), arguments: message.arguments)
    }
}

public func L(_ message: LocalizedMessage) -> String { L10n.text(message) }
