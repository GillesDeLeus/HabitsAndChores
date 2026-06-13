import SwiftUI

/// Lets the household owner add people directly from their friends list, instead
/// of sending a system invite link. Calls `onAdd` per chosen friend.
struct AddFriendsToHouseholdView: View {
    @Environment(SocialAccount.self) private var account
    @Environment(\.dismiss) private var dismiss

    /// Returns an error message, or nil on success.
    let onAdd: (SharedProfile) async -> String?

    @State private var model: FriendsModel?
    @State private var addingID: String?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if case let .active(userID, _) = account.state {
                    let model = self.model ?? FriendsModel(service: CloudKitSocialService(), me: userID)
                    List {
                        if model.friends.isEmpty {
                            ContentUnavailableView("No friends yet", systemImage: "person.2",
                                                   description: Text("Add friends in the Friends screen first."))
                        }
                        ForEach(model.friends) { friend in
                            Button { add(friend) } label: {
                                HStack {
                                    ProfileRowLabel(profile: friend)
                                    Spacer()
                                    if addingID == friend.userID {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(addingID != nil)
                        }
                    }
                    .task { if self.model == nil { self.model = model; await model.reload() } }
                } else {
                    ContentUnavailableView("No account", systemImage: "person.crop.circle.badge.xmark",
                                           description: Text("Create an account to add friends."))
                }
            }
            .navigationTitle("Add from friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Couldn’t add", isPresented: .constant(message != nil), presenting: message) { _ in
                Button("OK") { message = nil }
            } message: { Text($0) }
        }
    }

    private func add(_ friend: SharedProfile) {
        addingID = friend.userID
        Task {
            let error = await onAdd(friend)
            addingID = nil
            if let error { message = error } else { dismiss() }
        }
    }
}
