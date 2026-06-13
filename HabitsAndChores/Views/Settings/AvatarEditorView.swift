import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Lets the signed-in user either pick a photo or build a cartoon character, then
/// republishes their public profile with the new avatar.
struct AvatarEditorView: View {
    let service: SocialService

    @Environment(SocialAccount.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskItem> { !$0.isArchived }) private var tasks: [TaskItem]

    private enum Mode { case none, photo, character }

    @State private var mode: Mode = .character
    @State private var config = AvatarConfig()
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var saving = false
    @State private var error: String?

    init(service: SocialService) { self.service = service }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        AvatarView(photoData: mode == .photo ? photoData : nil,
                                   config: mode == .character ? config : nil,
                                   fallbackText: account.displayName.isEmpty ? "?" : account.displayName,
                                   size: 110)
                        Spacer()
                    }
                }

                Section("Photo") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose a photo", systemImage: "photo.on.rectangle")
                    }
                }

                Section {
                    SwatchRow(title: "Background", colors: CharacterAvatarView.backgrounds,
                              index: $config.background) { useCharacter() }
                    SwatchRow(title: "Skin", colors: CharacterAvatarView.skins,
                              index: $config.skin) { useCharacter() }
                    SwatchRow(title: "Hair color", colors: CharacterAvatarView.hairs,
                              index: $config.hairColor) { useCharacter() }

                    PartStepper(title: "Hair", index: $config.hair,
                                count: AvatarConfig.hairCount) { useCharacter() }
                    PartStepper(title: "Eyebrows", index: $config.eyebrows,
                                count: AvatarConfig.eyebrowsCount) { useCharacter() }
                    PartStepper(title: "Eyes", index: $config.eyes,
                                count: AvatarConfig.eyesCount) { useCharacter() }
                    PartStepper(title: "Mouth", index: $config.mouth,
                                count: AvatarConfig.mouthCount) { useCharacter() }
                    PartStepper(title: "Facial hair", index: $config.facialHair,
                                count: AvatarConfig.facialHairCount) { useCharacter() }
                    PartStepper(title: "Accessory", index: $config.accessory,
                                count: AvatarConfig.accessoryCount) { useCharacter() }

                    Button {
                        config = .random(); useCharacter()
                    } label: {
                        Label("Surprise me", systemImage: "dice.fill")
                    }
                } header: {
                    Text("Build a character")
                }

                Section {
                    Button("Remove avatar", role: .destructive) {
                        mode = .none; photoData = nil; photoItem = nil
                    }
                }
            }
            .navigationTitle("Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(saving)
                }
            }
            .onAppear(perform: prefill)
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            .alert("Couldn’t save avatar", isPresented: .constant(error != nil), presenting: error) { _ in
                Button("OK") { error = nil }
            } message: { Text($0) }
        }
    }

    private func useCharacter() { mode = .character }

    private func prefill() {
        if let photo = account.photoData {
            photoData = photo
            mode = .photo
        } else if let cfg = account.avatarConfig {
            config = cfg
            mode = .character
        } else {
            mode = .character
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let thumb = Self.thumbnail(from: data) {
                photoData = thumb
                mode = .photo
            }
        }
    }

    private func save() {
        saving = true
        switch mode {
        case .photo:
            if let photoData { account.setPhotoAvatar(photoData) } else { account.clearAvatar() }
        case .character:
            account.setCharacterAvatar(config)
        case .none:
            account.clearAvatar()
        }
        Task {
            if let me = account.userID, let handle = account.handle {
                let summary = GamificationEngine.summary(for: tasks)
                let profile = SharedProfile(
                    userID: me, handle: handle,
                    displayName: account.displayName.isEmpty ? handle : account.displayName,
                    summary: summary,
                    avatarConfig: account.avatarConfig,
                    photoData: account.photoData
                )
                do { try await service.publish(profile) }
                catch {
                    self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    saving = false
                    return
                }
            }
            saving = false
            dismiss()
        }
    }

    static func thumbnail(from data: Data, maxDimension: CGFloat = 256) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return scaled.jpegData(compressionQuality: 0.7)
    }
}

private struct SwatchRow: View {
    let title: String
    let colors: [Color]
    @Binding var index: Int
    var onChange: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(colors.indices, id: \.self) { i in
                        Circle()
                            .fill(colors[i])
                            .frame(width: 30, height: 30)
                            .overlay {
                                if i == index { Circle().strokeBorder(.primary, lineWidth: 2) }
                            }
                            .onTapGesture { index = i; onChange() }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct PartStepper: View {
    let title: String
    @Binding var index: Int
    let count: Int
    var onChange: () -> Void = {}

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button { index = (index - 1 + count) % count; onChange() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Text("\(index + 1)/\(count)").monospacedDigit().frame(minWidth: 40)
            Button { index = (index + 1) % count; onChange() } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
    }
}
