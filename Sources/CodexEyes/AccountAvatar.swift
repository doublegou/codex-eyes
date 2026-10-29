import SwiftUI

struct AccountAvatar: View {
    let name: String
    var size: CGFloat = 36
    private var initials: String { Self.initials(for: name) }
    private static func initials(for name: String) -> String {
        let letters = name.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary, in: Circle())
            .accessibilityHidden(true)
    }
}
