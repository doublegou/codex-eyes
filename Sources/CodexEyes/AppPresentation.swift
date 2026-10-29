import SwiftUI
import CodexEyesCore

/// Shared by every hosting root, including native sheets and the menu bar panel.
struct AppPresentation<Content: View>: View {
    @ObservedObject var model: AppModel
    var content: Content
    var body: some View {
        content.environment(\.locale, Locale(identifier: model.preferences.language.identifier()))
            .preferredColorScheme(model.preferences.appearance == .system ? nil :
                                 model.preferences.appearance == .dark ? .dark : .light)
    }
}
