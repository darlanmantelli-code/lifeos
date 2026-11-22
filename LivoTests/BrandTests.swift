import XCTest
import SwiftUI
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

    func testPaletteMatchesReferenceInLightMode() {
        func hex(_ c: Color, _ style: UIUserInterfaceStyle) -> UInt32 {
            let ui = UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
        }
        XCTAssertEqual(hex(.lifeInk, .light), 0x14283B)       // azul profundo
        XCTAssertEqual(hex(.lifeCanvas, .light), 0xF6F8FA)    // branco gelo
        XCTAssertEqual(hex(.lifeMintSoft, .light), 0xA4E8DB)  // verde menta
        XCTAssertEqual(hex(.lifeHairline, .dark), 0x26364A)   // azul grafite
        XCTAssertNotEqual(hex(.lifeAccent, .light), hex(.lifeAccent, .dark)) // adapts to dark mode
    }

    func testTaglineIsTheReferenceCopy() {
        XCTAssertEqual(Brand.headline, "Vida inteligente.")
        XCTAssertEqual(Brand.tagline, "Sua vida mais simples.")
    }
}
