import SwiftUI

/// A lightweight, dependency-free confetti burst. Increment `trigger` to replay it.
/// Sits as a non-interactive overlay; pieces fall once and fade out.
struct ConfettiView: View {
    /// Changing this value re-emits the burst.
    var trigger: Int

    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
    private let count = 70

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    ConfettiPiece(
                        trigger: trigger,
                        color: colors[index % colors.count],
                        startX: .random(in: 0...geo.size.width),
                        fallHeight: geo.size.height + 60,
                        drift: .random(in: -40...40),
                        spins: .random(in: 1...3),
                        duration: .random(in: 1.4...2.4),
                        delay: .random(in: 0...0.35)
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct ConfettiPiece: View {
    var trigger: Int
    let color: Color
    let startX: CGFloat
    let fallHeight: CGFloat
    let drift: CGFloat
    let spins: Double
    let duration: Double
    let delay: Double

    private struct Frame {
        var y: CGFloat = -40
        var x: CGFloat = 0
        var angle: Double = 0
        var opacity: Double = 0
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 7, height: 11)
            .keyframeAnimator(initialValue: Frame(), trigger: trigger) { content, frame in
                content
                    .opacity(frame.opacity)
                    .rotationEffect(.degrees(frame.angle))
                    .offset(x: frame.x, y: frame.y)
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    LinearKeyframe(-40, duration: delay)
                    LinearKeyframe(fallHeight, duration: duration)
                }
                KeyframeTrack(\.x) {
                    LinearKeyframe(0, duration: delay)
                    LinearKeyframe(drift, duration: duration)
                }
                KeyframeTrack(\.angle) {
                    LinearKeyframe(0, duration: delay)
                    LinearKeyframe(360 * spins, duration: duration)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: delay)
                    LinearKeyframe(1, duration: 0.01)
                    LinearKeyframe(1, duration: duration * 0.7)
                    LinearKeyframe(0, duration: duration * 0.3)
                }
            }
            .position(x: startX, y: 0)
    }
}
