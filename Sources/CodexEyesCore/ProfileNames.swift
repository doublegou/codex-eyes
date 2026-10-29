import Foundation

/// Reads display-only identity claims from existing local login snapshots.
/// JWT contents never participate in authorization and are never written to the app cache.
public enum LocalProfileNames {
    public static func load(home: URL) -> [String: String] {
        let directory = home.appendingPathComponent("accounts")
        var files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".auth.json") }
        files.append(home.appendingPathComponent("auth.json"))
        var result: [String: String] = [:]
        for file in files {
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
                  let data = try? Data(contentsOf: file), let identity = parse(data) else { continue }
            result[identity.id] = identity.name
        }
        return result
    }
    public static func parse(_ data: Data) -> (id: String, name: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any], let token = tokens["id_token"] as? String else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let decoded = Data(base64Encoded: encoded),
              let claims = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let name = claims["name"] as? String,
              let auth = claims["https://api.openai.com/auth"] as? [String: Any],
              let userID = (auth["chatgpt_user_id"] ?? auth["user_id"]) as? String,
              let accountID = (tokens["account_id"] ?? auth["chatgpt_account_id"]) as? String,
              !userID.isEmpty, !accountID.isEmpty else { return nil }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 200, !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return (userID + "::" + accountID, clean)
    }
}

public enum CompactTime {
    public static func localizedRemaining(until date: Date, now: Date = Date()) -> String {
        if L10n.language.identifier() == "en" { return date > now ? remaining(until: date, now: now) : L("即将") }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return L("即将") }
        // Unix timestamp round-trips can add fractions of a millisecond at an exact minute.
        let minutes = max(1, Int(ceil((seconds - 0.001) / 60)))
        if minutes >= 1440 {
            return L("\(minutes / 1440)天") + ((minutes % 1440) / 60 > 0 ? L("\((minutes % 1440) / 60)小时") : "")
        }
        if minutes >= 60 { return L("\(minutes / 60)小时") + (minutes % 60 > 0 ? L("\(minutes % 60)分") : "") }
        return L("\(minutes)分钟")
    }
    public static func remaining(until date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "0m" }
        let minutes = max(1, Int(ceil((seconds - 0.001) / 60)))
        if minutes >= 1440 { return "\(minutes / 1440)d" + ((minutes % 1440) / 60 > 0 ? "\((minutes % 1440) / 60)h" : "") }
        if minutes >= 60 { return "\(minutes / 60)h" + (minutes % 60 > 0 ? "\(minutes % 60)m" : "") }
        return "\(minutes)m"
    }
}
