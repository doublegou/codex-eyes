import Foundation
import CFNetwork

/// CLI curl does not automatically inherit macOS' proxy configuration like URLSession does.
/// Translate explicit system proxies, while respecting caller-provided proxy environment variables.
public enum NetworkEnvironment {
    public static func systemProxy() -> [String: String] {
        let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
        return proxy(settings: settings, inherited: ProcessInfo.processInfo.environment)
    }
    public static func proxy(settings: [String: Any], inherited: [String: String]) -> [String: String] {
        let explicit = ["http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"]
        if explicit.contains(where: { !(inherited[$0] ?? "").isEmpty }) { return [:] }
        func address(_ name: String, scheme: String) -> String? {
            guard (settings[name + "Enable"] as? NSNumber)?.boolValue == true,
                  let host = settings[name + "Proxy"] as? String, !host.isEmpty,
                  let port = settings[name + "Port"] as? Int, (1...65535).contains(port) else { return nil }
            var components = URLComponents(); components.scheme = scheme; components.host = host; components.port = port
            return components.string
        }
        var result: [String: String] = [:]
        if let http = address("HTTP", scheme: "http") { result["http_proxy"] = http }
        if let https = address("HTTPS", scheme: "http") { result["https_proxy"] = https }
        if let socks = address("SOCKS", scheme: "socks5h") { result["all_proxy"] = socks }
        if !result.isEmpty, inherited["no_proxy"] == nil, inherited["NO_PROXY"] == nil {
            let exclusions = settings["ExceptionsList"] as? [String] ?? []
            result["no_proxy"] = (["localhost", "127.0.0.1", "::1"] + exclusions.filter { !$0.contains("<") })
                .map { $0.hasPrefix("*.") ? String($0.dropFirst()) : $0 }.joined(separator: ",")
        }
        return result
    }
}
