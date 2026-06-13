import SwiftUI

/// Renders a cartoon character from an `AvatarConfig` by layering recolorable
/// vector parts. Scales to any `size`; no external art assets.
struct CharacterAvatarView: View {
    let config: AvatarConfig
    var size: CGFloat = 44

    private func f(_ x: CGFloat) -> CGFloat { size * x }
    private var ink: Color { .black.opacity(0.8) }

    var body: some View {
        ZStack {
            Circle().fill(Self.bgColor(config.background).gradient)
            hairBack
            face
            ears
            eyebrowsView
            eyes
            facialHairView
            mouthView
            hairFront
            accessoryView
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    // MARK: - Head

    private var face: some View {
        Ellipse()
            .fill(Self.skinColor(config.skin))
            .frame(width: f(0.58), height: f(0.68))
            .offset(y: f(0.07))
    }

    private var ears: some View {
        let c = Self.skinColor(config.skin)
        return HStack(spacing: f(0.56)) {
            Circle().fill(c).frame(width: f(0.1), height: f(0.1))
            Circle().fill(c).frame(width: f(0.1), height: f(0.1))
        }
        .offset(y: f(0.06))
    }

    // MARK: - Hair

    @ViewBuilder private var hairBack: some View {
        if config.hair != 0 {
            let c = Self.hairColor(config.hairColor)
            switch config.hair {
            case 1: Ellipse().fill(c).frame(width: f(0.68), height: f(0.66)).offset(y: f(-0.01))
            case 2: Ellipse().fill(c).frame(width: f(0.66), height: f(0.56)).offset(y: f(-0.05))
            case 3: Ellipse().fill(c).frame(width: f(0.74), height: f(0.96)).offset(y: f(0.10))
            case 4:
                Ellipse().fill(c).frame(width: f(0.62), height: f(0.56)).offset(y: f(-0.03))
                Circle().fill(c).frame(width: f(0.20), height: f(0.20)).offset(y: f(-0.34))
            case 5: Ellipse().fill(c).frame(width: f(0.60), height: f(0.50)).offset(y: f(-0.06))
            case 6: Circle().fill(c).frame(width: f(0.82), height: f(0.82)).offset(y: f(-0.06)) // afro
            case 7: // spiky — a hair mass topped with spikes
                Ellipse().fill(c).frame(width: f(0.62), height: f(0.50)).offset(y: f(-0.05))
                SpikeShape().fill(c).frame(width: f(0.66), height: f(0.30)).offset(y: f(-0.30))
            default: Ellipse().fill(c).frame(width: f(0.64), height: f(0.62))
            }
        }
    }

    /// A small forehead fringe for some styles, drawn over the face.
    @ViewBuilder private var hairFront: some View {
        let c = Self.hairColor(config.hairColor)
        switch config.hair {
        case 2: // side part — soft sweep across the forehead
            Ellipse().fill(c).frame(width: f(0.46), height: f(0.20))
                .offset(x: f(-0.07), y: f(-0.17))
        case 3: // long — straight bangs
            Capsule().fill(c).frame(width: f(0.46), height: f(0.13)).offset(y: f(-0.19))
        default: EmptyView()
        }
    }

    // MARK: - Brows & eyes

    @ViewBuilder private var eyebrowsView: some View {
        if config.eyebrows != 0 {
            let yBase: CGFloat = config.eyebrows == 2 ? -0.14 : -0.11
            let angle: Double = config.eyebrows == 3 ? 12 : 0
            ZStack {
                brow.rotationEffect(.degrees(-angle)).offset(x: f(-0.13), y: f(yBase))
                brow.rotationEffect(.degrees(angle)).offset(x: f(0.13), y: f(yBase))
            }
        }
    }

    private var brow: some View {
        Capsule().fill(ink).frame(width: f(0.10), height: f(0.022))
    }

    private var eyes: some View {
        ZStack {
            eyeView().offset(x: f(-0.13), y: f(-0.02))
            eyeView().offset(x: f(0.13), y: f(-0.02))
        }
    }

    @ViewBuilder private func eyeView() -> some View {
        switch config.eyes {
        case 0: Circle().fill(ink).frame(width: f(0.07), height: f(0.07))
        case 1: Circle().fill(ink).frame(width: f(0.045), height: f(0.045))
        case 2: EyeArc().stroke(ink, style: StrokeStyle(lineWidth: max(1, f(0.022)), lineCap: .round))
                    .frame(width: f(0.09), height: f(0.05))
        case 3: ZStack {
                    Circle().fill(.white).frame(width: f(0.10), height: f(0.10))
                    Circle().strokeBorder(ink.opacity(0.4), lineWidth: max(0.5, f(0.006)))
                        .frame(width: f(0.10), height: f(0.10))
                    Circle().fill(ink).frame(width: f(0.05), height: f(0.05))
                }
        case 4: Capsule().fill(ink).frame(width: f(0.085), height: f(0.02)) // sleepy
        default: Circle().fill(ink).frame(width: f(0.07), height: f(0.07))
        }
    }

    // MARK: - Mouth

    @ViewBuilder private var mouthView: some View {
        Group {
            switch config.mouth {
            case 0: SmileShape().stroke(ink, style: StrokeStyle(lineWidth: max(1, f(0.028)), lineCap: .round))
                        .frame(width: f(0.20), height: f(0.10))
            case 1: Capsule().fill(ink).frame(width: f(0.14), height: f(0.025))
            case 2: SmileShape().fill(ink).frame(width: f(0.18), height: f(0.09))
            case 3: Ellipse().fill(ink).frame(width: f(0.10), height: f(0.08))
            case 4: SmileShape().stroke(ink, style: StrokeStyle(lineWidth: max(1, f(0.028)), lineCap: .round))
                        .frame(width: f(0.18), height: f(0.09)).scaleEffect(y: -1) // frown
            default: Capsule().fill(ink).frame(width: f(0.14), height: f(0.025))
            }
        }
        .offset(y: f(0.19))
    }

    // MARK: - Facial hair

    @ViewBuilder private var facialHairView: some View {
        if config.facialHair != 0 {
            let c = Self.hairColor(config.hairColor)
            switch config.facialHair {
            case 1: Capsule().fill(c).frame(width: f(0.16), height: f(0.035)).offset(y: f(0.13)) // mustache
            case 2: BeardShape().fill(c).frame(width: f(0.52), height: f(0.40)).offset(y: f(0.22)) // full
            case 3: BeardShape().fill(c).frame(width: f(0.52), height: f(0.40)).offset(y: f(0.22)).opacity(0.32) // stubble
            case 4: Capsule().fill(c).frame(width: f(0.09), height: f(0.10)).offset(y: f(0.27)) // goatee
            default: EmptyView()
            }
        }
    }

    // MARK: - Accessory

    @ViewBuilder private var accessoryView: some View {
        switch config.accessory {
        case 1: Image(systemName: "eyeglasses").font(.system(size: f(0.34)))
                    .foregroundStyle(.black.opacity(0.85)).offset(y: f(-0.02))
        case 2: Image(systemName: "sunglasses.fill").font(.system(size: f(0.32)))
                    .foregroundStyle(.black.opacity(0.9)).offset(y: f(-0.02))
        case 3: // baseball cap: dome + forward brim
            let hat = Color(red: 0.85, green: 0.30, blue: 0.32)
            ZStack {
                Ellipse().fill(hat).frame(width: f(0.64), height: f(0.50)).offset(y: f(-0.18))
                Capsule().fill(hat).frame(width: f(0.60), height: f(0.10)).offset(y: f(-0.05))
                Circle().fill(hat).frame(width: f(0.06), height: f(0.06)).offset(y: f(-0.40))
            }
        case 4: // headphones: band over the crown + two ear cups
            let gear = Color.black.opacity(0.78)
            ZStack {
                HeadbandShape().stroke(gear, style: StrokeStyle(lineWidth: f(0.05), lineCap: .round))
                    .frame(width: f(0.66), height: f(0.33)).offset(y: f(-0.10))
                RoundedRectangle(cornerRadius: f(0.04)).fill(gear)
                    .frame(width: f(0.11), height: f(0.17)).offset(x: f(-0.30), y: f(0.03))
                RoundedRectangle(cornerRadius: f(0.04)).fill(gear)
                    .frame(width: f(0.11), height: f(0.17)).offset(x: f(0.30), y: f(0.03))
            }
        default: EmptyView()
        }
    }

    // MARK: - Palettes

    static let backgrounds: [Color] = [
        Color(red: 0.36, green: 0.55, blue: 0.86), Color(red: 0.36, green: 0.75, blue: 0.55),
        Color(red: 0.95, green: 0.66, blue: 0.30), Color(red: 0.90, green: 0.45, blue: 0.55),
        Color(red: 0.62, green: 0.50, blue: 0.85), Color(red: 0.40, green: 0.78, blue: 0.80),
        Color(red: 0.55, green: 0.58, blue: 0.65), Color(red: 0.93, green: 0.80, blue: 0.35),
        Color(red: 0.45, green: 0.82, blue: 0.70), Color(red: 0.96, green: 0.55, blue: 0.45),
        Color(red: 0.40, green: 0.42, blue: 0.70), Color(red: 0.88, green: 0.60, blue: 0.78),
    ]
    static let skins: [Color] = [
        Color(red: 0.99, green: 0.87, blue: 0.78), Color(red: 0.96, green: 0.80, blue: 0.68),
        Color(red: 0.92, green: 0.74, blue: 0.58), Color(red: 0.83, green: 0.63, blue: 0.46),
        Color(red: 0.70, green: 0.50, blue: 0.35), Color(red: 0.55, green: 0.38, blue: 0.25),
        Color(red: 0.40, green: 0.27, blue: 0.18),
    ]
    static let hairs: [Color] = [
        Color(red: 0.15, green: 0.13, blue: 0.12), Color(red: 0.35, green: 0.24, blue: 0.16),
        Color(red: 0.55, green: 0.38, blue: 0.22), Color(red: 0.85, green: 0.70, blue: 0.40),
        Color(red: 0.78, green: 0.36, blue: 0.20), Color(red: 0.72, green: 0.72, blue: 0.74),
        Color(red: 0.93, green: 0.92, blue: 0.90), Color(red: 0.55, green: 0.55, blue: 0.88),
    ]

    static func bgColor(_ i: Int) -> Color { backgrounds[clamp(i, backgrounds.count)] }
    static func skinColor(_ i: Int) -> Color { skins[clamp(i, skins.count)] }
    static func hairColor(_ i: Int) -> Color { hairs[clamp(i, hairs.count)] }
    private static func clamp(_ i: Int, _ n: Int) -> Int { min(max(i, 0), n - 1) }
}

private struct SmileShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 2))
        return p
    }
}

private struct EyeArc: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY - r.height))
        return p
    }
}

/// A rounded chin-hugging beard shape (flat top, round bottom).
private struct BeardShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY),
                       control: CGPoint(x: r.midX, y: r.maxY * 1.6))
        p.closeSubpath()
        return p
    }
}

/// A top-arc band for headphones.
private struct HeadbandShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: r.midX, y: r.maxY),
                 radius: r.width / 2,
                 startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        return p
    }
}

/// Zigzag spikes for spiky hair.
private struct SpikeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let spikes = 5
        let step = r.width / CGFloat(spikes)
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        for i in 0..<spikes {
            let x = r.minX + step * CGFloat(i)
            p.addLine(to: CGPoint(x: x + step / 2, y: r.minY))
            p.addLine(to: CGPoint(x: x + step, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
            ForEach(0..<25, id: \.self) { _ in
                CharacterAvatarView(config: .random(), size: 60)
            }
        }
        .padding()
    }
}
