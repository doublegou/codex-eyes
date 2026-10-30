import Foundation
import SystemConfiguration

/// VPNs can change routes or proxies while the Wi-Fi interface remains connected.
final class NetworkWatch {
    private var store: SCDynamicStore?
    private let changed: () -> Void

    init(changed: @escaping () -> Void) {
        self.changed = changed
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        store = SCDynamicStoreCreate(nil, "CodexEyesNetwork" as CFString, { _, _, info in
            guard let info else { return }
            Unmanaged<NetworkWatch>.fromOpaque(info).takeUnretainedValue().changed()
        }, &context)
        if let store {
            let keys = ["State:/Network/Global/Proxies", "State:/Network/Global/IPv4", "State:/Network/Global/IPv6"]
            let patterns = ["State:/Network/Service/.*/IPv4", "State:/Network/Service/.*/IPv6", "State:/Network/Service/.*/Proxies"]
            SCDynamicStoreSetNotificationKeys(store, keys as CFArray, patterns as CFArray)
            SCDynamicStoreSetDispatchQueue(store, .main)
        }
    }

    deinit {
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
    }
}
