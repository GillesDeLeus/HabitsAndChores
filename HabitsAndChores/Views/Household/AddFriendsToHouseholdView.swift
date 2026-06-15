import SwiftUI

/// Lets the household owner invite people directly from their friends list. Each
/// friend gets an in-app invitation (and a push) they can accept from the app —
/// no manual link needed. Calls `onInvite` per chosen friend.
struct AddFriendsToHouseholdView: View {
    @Environment(SocialAccount.self) private var account
    @Environment(\.dismiss) private var dismiss

    /// Returns an error message, or nil on success.
    let onInvite: (SharedProfile) async -> String?

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
                            Button { invite(friend) } label: {
                                HStack {
                                    ProfileRowLabel(profile: friend)
                                    Spacer()
                                    if addingID == friend.userID {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(Color.accentColor)
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
            .navigationTitle("Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Couldn’t invite", isPresented: .constant(message != nil), presenting: message) { _ in
                Button("OK") { message = nil }
            } message: { Text($0) }
        }
    }

    private func invite(_ friend: SharedProfile) {
        addingID = friend.userID
        Task {
            let error = await onInvite(friend)
            addingID = nil
            if let error { message = error } else { dismiss() }
        }
    }
}
