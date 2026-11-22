import SwiftUI
import UIKit

extension Locale {
    static let ptBR = Locale(identifier: "pt_BR")
}

/// Brand constants. The tagline lives here only.
enum Brand {
    static let name = "livo"
    static let headline = "Vida inteligente."
    static let tagline = "Sua vida mais simples."
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Palette from the brand reference: azul profundo, verde menta, branco gelo, azul grafite,
/// plus the logo's own blue and mint. Meaning, not decoration:
///   blue  = what you can act on (tint, links, selection)
///   mint  = growth (progress, income, done)
///   ink   = text and headings
extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static func brand(_ light: UInt32, dark: UInt32) -> Color {
        Color(light: UIColor(hex: light), dark: UIColor(hex: dark))
    }

    /// Headings. Light: azul profundo. Dark: gelo.
    static let lifeInk = brand(0x14283B, dark: 0xF3F6FA)
    /// Screen background. Light: branco gelo. Dark: azul profundo, one step darker.
    static let lifeCanvas = brand(0xF6F8FA, dark: 0x0E1C2B)
    /// Cards. Dark mode steps toward azul grafite.
    static let lifeSurface = brand(0xFFFFFF, dark: 0x172B40)
    static let lifeHairline = brand(0xE2E8EF, dark: 0x26364A)
    /// Interactive blue (the logo's bar).
    static let lifeAccent = brand(0x0462D0, dark: 0x6BA9FF)
    /// Growth: progress fills, completed items.
    static let lifeProgress = brand(0x2BD08F, dark: 0x5BE8B0)
    /// Soft mint for chips and quiet highlights (the palette's verde menta).
    static let lifeMintSoft = brand(0xA4E8DB, dark: 0x1D4D4A)
    /// Income as text: darker than the logo mint so it stays readable on white.
    static let lifeIncome = brand(0x087F55, dark: 0x5BE8B0)
    static let lifeExpense = brand(0xD92D3A, dark: 0xFF7A80)

    // Logo colors (used by LivoMark and the hero card)
    static let markBlueTop = brand(0x0462D0, dark: 0x58A6FF)
    static let markBlueBottom = brand(0x02357F, dark: 0x2F79E8)
    static let markMintA = brand(0x55E8A9, dark: 0x79F0C0)
    static let markMintB = brand(0x3FD99C, dark: 0x58E3AB)
    static let markWordmark = brand(0x082650, dark: 0xF3F6FA)
    static let heroTop = brand(0x0A64DA, dark: 0x0C52B8)
    static let heroBottom = brand(0x03378A, dark: 0x0A2C66)
}

enum Spacing {
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
}

/// Standard card: ice-white surface with a hairline and a soft blue-tinted shadow (graphite in dark mode).
struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.lifeSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.lifeHairline, lineWidth: 1))
            .shadow(color: Color.lifeInk.opacity(scheme == .dark ? 0 : 0.07), radius: 16, y: 6)
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }

    /// Brand canvas behind lists, forms and scroll views (replaces the system grouped background).
    func brandScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.lifeCanvas.ignoresSafeArea())
    }
}

extension String {
    /// "domingo, 22 de novembro" → "Domingo, 22 de novembro" (`.capitalized` would also turn "de" into "De").
    var firstUppercased: String { prefix(1).uppercased() + dropFirst() }
}

extension Color {
    /// Fixed (non-adaptive) color from a 0xRRGGBB value, for surfaces whose colors don't change with the appearance.
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}
