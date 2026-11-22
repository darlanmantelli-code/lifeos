import SwiftUI

/// The bar of the logo: a capsule between two points (geometry fitted to the brand reference).
private struct BarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let a = CGPoint(x: rect.minX + LivoMarkGeometry.capsuleStart.x * w, y: rect.minY + LivoMarkGeometry.capsuleStart.y * w)
        let b = CGPoint(x: rect.minX + LivoMarkGeometry.capsuleEnd.x * w, y: rect.minY + LivoMarkGeometry.capsuleEnd.y * w)
        let r = Double(LivoMarkGeometry.capsuleRadius * w)
        let theta = Double(atan2(b.y - a.y, b.x - a.x))
        let steps = 48
        var points: [CGPoint] = []
        // Half circle around the start facing away from the end, then the same around the end.
        for i in 0...steps {
            let t = Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            points.append(CGPoint(x: Double(a.x) + r * cos(theta + t), y: Double(a.y) + r * sin(theta + t)))
        }
        for i in 0...steps {
            let t = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            points.append(CGPoint(x: Double(b.x) + r * cos(theta + t), y: Double(b.y) + r * sin(theta + t)))
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// The leaf of the logo, drawn from a smooth outline.
private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let points = LivoMarkGeometry.leaf.map { CGPoint(x: rect.minX + $0.x * w, y: rect.minY + $0.y * w) }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// The livo mark: a blue bar and a mint leaf. Vector, so it stays sharp at any size and in both appearances.
struct LivoMark: View {
    enum Style {
        case brand
        case mono(Color)
    }

    var style: Style = .brand

    private var barFill: AnyShapeStyle {
        switch style {
        case .brand:
            let h = LivoMarkGeometry.aspectHeight
            return AnyShapeStyle(LinearGradient(
                colors: [Color.markBlueTop, Color.markBlueBottom],
                startPoint: UnitPoint(x: LivoMarkGeometry.capsuleStart.x, y: LivoMarkGeometry.capsuleStart.y / h),
                endPoint: UnitPoint(x: LivoMarkGeometry.capsuleEnd.x, y: LivoMarkGeometry.capsuleEnd.y / h)))
        case .mono(let color):
            return AnyShapeStyle(color)
        }
    }

    private var leafFill: AnyShapeStyle {
        switch style {
        case .brand:
            return AnyShapeStyle(LinearGradient(colors: [Color.markMintA, Color.markMintB], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .mono(let color):
            return AnyShapeStyle(color)
        }
    }

    var body: some View {
        ZStack {
            LeafShape().fill(leafFill)
            BarShape().fill(barFill)
        }
        .aspectRatio(1 / LivoMarkGeometry.aspectHeight, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Brand.name)
    }
}

/// "livo" set in heavy SF Rounded, close to the logo's own letterforms.
struct Wordmark: View {
    var size: CGFloat = 30

    var body: some View {
        Text(Brand.name)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.markWordmark)
            .kerning(-size * 0.015)
            .accessibilityHidden(true)
    }
}

/// Mark + wordmark side by side.
struct BrandLockup: View {
    var height: CGFloat = 26

    var body: some View {
        HStack(spacing: height * 0.3) {
            LivoMark().frame(height: height)
            Wordmark(size: height * 1.15)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.name)
    }
}

/// The one loud surface: the blue of the logo, with the mark faintly watermarked in the corner.
struct HeroCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.m + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background {
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(colors: [Color.heroTop, Color.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    LivoMark(style: .mono(Color.white.opacity(0.09)))
                        .frame(width: 180)
                        .offset(x: 52, y: 44)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .shadow(color: Color.heroBottom.opacity(0.30), radius: 18, y: 10)
    }
}

extension View {
    func heroCard() -> some View { modifier(HeroCardStyle()) }
}
