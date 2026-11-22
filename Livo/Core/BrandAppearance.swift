import UIKit

/// UIKit-backed chrome (navigation bar titles, tab bar) can't read SwiftUI's font design, so set it here.
enum BrandAppearance {
    @MainActor
    static func apply() {
        let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xF3F6FA) : UIColor(hex: 0x14283B) }

        func rounded(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            let size = UIFont.preferredFont(forTextStyle: style).pointSize
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
            return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
        }

        let large: [NSAttributedString.Key: Any] = [.font: rounded(.largeTitle, .heavy), .foregroundColor: ink]
        let title: [NSAttributedString.Key: Any] = [.font: rounded(.headline, .bold), .foregroundColor: ink]

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.largeTitleTextAttributes = large
        standard.titleTextAttributes = title

        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.largeTitleTextAttributes = large
        edge.titleTextAttributes = title

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = edge
    }
}
