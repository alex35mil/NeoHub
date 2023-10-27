import SwiftUI

struct SettingsGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
    }
}

extension View {
    func settingsGroup() -> some View {
        self.modifier(SettingsGroupModifier())
    }
}
