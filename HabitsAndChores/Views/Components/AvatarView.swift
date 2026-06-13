import SwiftUI
import UIKit

/// Renders a user's avatar with a clear precedence: photo → built character → initials.
struct AvatarView: View {
    var photoData: Data?
    var config: AvatarConfig?
    var fallbackText: String
    var size: CGFloat = 44

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
    }

    @ViewBuilder
    private var content: some View {
        if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let config {
            CharacterAvatarView(config: config, size: size)
        } else {
            ZStack {
                Circle().fill(Color.accentColor.gradient)
                Text(fallbackText.prefix(1).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

extension AvatarView {
    /// Convenience for a friend's public profile.
    init(profile: SharedProfile, size: CGFloat = 44) {
        self.init(photoData: profile.photoData,
                  config: profile.avatarConfig,
                  fallbackText: profile.displayName,
                  size: size)
    }

    /// Convenience for the signed-in user's own account.
    init(account: SocialAccount, size: CGFloat = 44) {
        self.init(photoData: account.photoData,
                  config: account.avatarConfig,
                  fallbackText: account.displayName.isEmpty ? (account.handle ?? "?") : account.displayName,
                  size: size)
    }
}
