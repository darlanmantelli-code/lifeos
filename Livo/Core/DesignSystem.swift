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
/// The palette as (light, dark) hex pairs: one source for the colors below and for the contrast tests.
enum BrandHex {
    typealias Pair = (light: UInt32, dark: UInt32)

    /// Headings. Light: azul profundo. Dark: gelo.
    static let ink: Pair = (0x14283B, 0xF3F6FA)
    /// Screen background. Light: branco gelo. Dark: azul profundo, one step darker.
    static let canvas: Pair = (0xF6F8FA, 0x0E1C2B)
    /// Cards. Dark mode steps toward azul grafite.
    static let surface: Pair = (0xFFFFFF, 0x172B40)
    static let hairline: Pair = (0xE2E8EF, 0x26364A)
    /// Interactive blue (the logo's bar).
    static let accent: Pair = (0x0462D0, 0x6BA9FF)
    /// Growth: progress fills, completed items.
    static let progress: Pair = (0x2BD08F, 0x5BE8B0)
    /// Soft mint for chips and quiet highlights (the palette's verde menta).
    static let mintSoft: Pair = (0xA4E8DB, 0x1D4D4A)
    /// Income as text: darker than the logo mint so it stays readable on white.
    static let income: Pair = (0x087F55, 0x5BE8B0)
    static let expense: Pair = (0xD92D3A, 0xFF7A80)

    // Logo colors (used by LivoMark, the wordmark and the hero card)
    static let markBlueTop: Pair = (0x0462D0, 0x58A6FF)
    static let markBlueBottom: Pair = (0x02357F, 0x2F79E8)
    static let markMintA: Pair = (0x55E8A9, 0x79F0C0)
    static let markMintB: Pair = (0x3FD99C, 0x58E3AB)
    static let wordmark: Pair = (0x082650, 0xF3F6FA)
    static let heroTop: Pair = (0x0A64DA, 0x0C52B8)
    static let heroBottom: Pair = (0x03378A, 0x0A2C66)
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static func brand(_ pair: BrandHex.Pair) -> Color {
        Color(light: UIColor(hex: pair.light), dark: UIColor(hex: pair.dark))
    }

    static let lifeInk = brand(BrandHex.ink)
    static let lifeCanvas = brand(BrandHex.canvas)
    static let lifeSurface = brand(BrandHex.surface)
    static let lifeHairline = brand(BrandHex.hairline)
    static let lifeAccent = brand(BrandHex.accent)
    static let lifeProgress = brand(BrandHex.progress)
    static let lifeMintSoft = brand(BrandHex.mintSoft)
    static let lifeIncome = brand(BrandHex.income)
    static let lifeExpense = brand(BrandHex.expense)

    static let markBlueTop = brand(BrandHex.markBlueTop)
    static let markBlueBottom = brand(BrandHex.markBlueBottom)
    static let markMintA = brand(BrandHex.markMintA)
    static let markMintB = brand(BrandHex.markMintB)
    static let markWordmark = brand(BrandHex.wordmark)
    static let heroTop = brand(BrandHex.heroTop)
    static let heroBottom = brand(BrandHex.heroBottom)
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
