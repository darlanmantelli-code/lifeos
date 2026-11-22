import XCTest
@testable import Livo

final class BrandTests: XCTestCase {
    func testAssetsAreInTheBundle() {
        // The launch screen resolves these by name; a typo or missing catalog would show a blank launch.
        XCTAssertNotNil(UIImage(named: "LaunchMark"))
        XCTAssertNotNil(UIColor(named: "LaunchBackground"))
    }

    func testLogoGeometryIsWellFormed() {
        XCTAssertEqual(LivoMarkGeometry.leaf.count, 160)
        let all = LivoMarkGeometry.leaf + [LivoMarkGeometry.capsuleStart, LivoMarkGeometry.capsuleEnd]
        XCTAssertTrue(all.allSatisfy { (-0.01...1.01).contains($0.x) && (-0.01...1.01).contains($0.y) })
        XCTAssertEqual(LivoMarkGeometry.aspectHeight, 0.9218, accuracy: 0.001)
    }

    func testReferenceSwatchesArePresent() {
        XCTAssertEqual(BrandHex.ink.light, 0x14283B)      // azul profundo
        XCTAssertEqual(BrandHex.mintSoft.light, 0xA4E8DB) // verde menta
        XCTAssertEqual(BrandHex.canvas.light, 0xF6F8FA)   // branco gelo
        XCTAssertEqual(BrandHex.hairline.dark, 0x26364A)  // azul grafite
    }

    func testTaglineIsTheReferenceCopy() {
        XCTAssertEqual(Brand.headline, "Vida inteligente.")
        XCTAssertEqual(Brand.tagline, "Sua vida mais simples.")
    }

    // MARK: Accessibility guardrail: WCAG contrast of text colors on the surfaces they sit on.

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func testTextContrastMeetsAA() {
        let pairs: [(String, BrandHex.Pair, BrandHex.Pair)] = [
            ("tinta sobre fundo", BrandHex.ink, BrandHex.canvas),
            ("tinta sobre cartão", BrandHex.ink, BrandHex.surface),
            ("ação sobre fundo", BrandHex.accent, BrandHex.canvas),
            ("ação sobre cartão", BrandHex.accent, BrandHex.surface),
            ("receita sobre cartão", BrandHex.income, BrandHex.surface),
            ("despesa sobre cartão", BrandHex.expense, BrandHex.surface),
        ]
        for (name, fg, bg) in pairs {
            XCTAssertGreaterThanOrEqual(contrast(fg.light, bg.light), 4.5, "\(name) (claro)")
            XCTAssertGreaterThanOrEqual(contrast(fg.dark, bg.dark), 4.5, "\(name) (escuro)")
        }
        // White text on the hero gradient's lighter stop, both appearances.
        XCTAssertGreaterThanOrEqual(contrast(0xFFFFFF, BrandHex.heroTop.light), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(0xFFFFFF, BrandHex.heroTop.dark), 4.5)
    }
}
