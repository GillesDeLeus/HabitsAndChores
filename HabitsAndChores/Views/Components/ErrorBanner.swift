import SwiftUI

/// A transient, non-blocking error banner driven by `AppErrorCenter`. Auto-dismisses.
private struct ErrorBannerModifier: ViewModifier {
    @State private var center = AppErrorCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = center.message {
                    Text(message)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .shadow(radius: 6, y: 2)
                        .onTapGesture { center.message = nil }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: message) {
                            try? await Task.sleep(for: .seconds(4))
                            center.message = nil
                        }
                }
            }
            .animation(.snappy, value: center.message)
    }
}

extension View {
    func errorBanner() -> some View { modifier(ErrorBannerModifier()) }
}
