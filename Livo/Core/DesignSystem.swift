import SwiftUI
import UIKit

extension Locale {
    static let ptBR = Locale(identifier: "pt_BR")
}

extension Color {
    /// Brand accent: deep teal in light mode, brighter in dark mode.
    static let lifeAccent = Color(light: UIColor(red: 0.05, green: 0.45, blue: 0.47, alpha: 1),
                                  dark: UIColor(red: 0.30, green: 0.78, blue: 0.76, alpha: 1))
    static let lifeIncome = Color(.systemGreen)
    static let lifeExpense = Color(.systemRed)

    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

enum Spacing {
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
}

/// Standard card: grouped surface, continuous corners. Used by every dashboard widget and summary.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

extension String {
    /// "domingo, 22 de novembro" → "Domingo, 22 de novembro" (`.capitalized` would also turn "de" into "De").
    var firstUppercased: String { prefix(1).uppercased() + dropFirst() }
}
