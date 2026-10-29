import Foundation

public struct Preferences: Codable {
    public var demo = false
    public var privacy = false
    public var reducedMotion = false
    public var allowSwitching = false
    public var skipSwitchConfirmation = false
    public var notifyQuota = false
    public var notifyTasks = false
    public var notifyBackup = false
    public var notes: [String: String] = [:]
    public var order: [String] = []
    public var pinnedSession: String?
    public var language = AppLanguage.system
    public var appearance = AppAppearance.system
    public var shortcut = PanelShortcut.standard
    public init() {}
    enum CodingKeys: String, CodingKey { case demo, privacy, reducedMotion, allowSwitching, skipSwitchConfirmation, notifyQuota, notifyTasks, notifyBackup, notes, order, pinnedSession, language, appearance, shortcut }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        demo = try c.decodeIfPresent(Bool.self, forKey: .demo) ?? demo
        privacy = try c.decodeIfPresent(Bool.self, forKey: .privacy) ?? privacy
        reducedMotion = try c.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? reducedMotion
        allowSwitching = try c.decodeIfPresent(Bool.self, forKey: .allowSwitching) ?? allowSwitching
        skipSwitchConfirmation = try c.decodeIfPresent(Bool.self, forKey: .skipSwitchConfirmation) ?? false
        notifyQuota = try c.decodeIfPresent(Bool.self, forKey: .notifyQuota) ?? notifyQuota
        notifyTasks = try c.decodeIfPresent(Bool.self, forKey: .notifyTasks) ?? notifyTasks
        notifyBackup = try c.decodeIfPresent(Bool.self, forKey: .notifyBackup) ?? notifyBackup
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes) ?? notes
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? order
        pinnedSession = try c.decodeIfPresent(String.self, forKey: .pinnedSession)
        language = (try? c.decodeIfPresent(AppLanguage.self, forKey: .language)) ?? language
        // Older releases were Chinese-only. Preserve their language on upgrade.
        if !c.contains(.language) { language = .simplifiedChinese }
        appearance = (try? c.decodeIfPresent(AppAppearance.self, forKey: .appearance)) ?? appearance
        shortcut = (try? c.decodeIfPresent(PanelShortcut.self, forKey: .shortcut)) ?? shortcut
        if !shortcut.isValid { shortcut = .standard }
    }
}
