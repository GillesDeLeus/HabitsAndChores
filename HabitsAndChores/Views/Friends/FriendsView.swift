import SwiftUI

struct FriendsView: View {
    @Environment(SocialAccount.self) private var account

    @State private var model: FriendsModel?
    @State private var searchHandle = ""
    @State private var searchResult: SharedProfile?
    @State private var searching = false
    @State private var searchMessage: String?

    var body: some View {
        Group {
            if case let .active(userID, _) = account.state {
                let model = model ?? makeModel(me: userID)
                content(model)
                    .task { if self.model == nil { self.model = model; await model.reload() } }
            } else {
                ContentUnavailableView {
                    Label("No account", systemImage: "person.crop.circle.badge.xmark")
                } description: {
                    Text("Create an account in Settings to add friends.")
                }
            }
        }
        .navigationTitle("Friends")
    }

    private func makeModel(me: String) -> FriendsModel {
        FriendsModel(service: CloudKitSocialService(), me: me)
    }

    private func content(_ model: FriendsModel) -> some View {
        List {
            // MARK: Add by handle
            Section("Add a friend") {
                HStack {
                    TextField("handle", text: $searchHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Find") { search(model) }
                        .disabled(searching || normalizedHandle(searchHandle) == nil)
                }
                if let result = searchResult {
                    HStack {
                        ProfileRowLabel(profile: result)
                        Spacer()
                        searchActionButton(model, for: result)
                    }
                } else if let message = searchMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            // MARK: Requests received
            if !model.incoming.isEmpty {
                Section("Requests received (\(model.incoming.count))") {
                    ForEach(model.incoming) { profile in
                        HStack {
                            NavigationLink { ProfileDetailView(profile: profile) } label: {
                                ProfileRowLabel(profile: profile)
                            }
                            Spacer(minLength: 8)
                            Button { Task { await model.accept(profile) } } label: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            .accessibilityLabel("Accept \(profile.displayName)")
                            Button { Task { await model.decline(profile) } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                            .accessibilityLabel("Decline \(profile.displayName)")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // MARK: Requests sent
            if !model.outgoing.isEmpty {
                Section("Requests sent (\(model.outgoing.count))") {
                    ForEach(model.outgoing) { profile in
                        HStack {
                            ProfileRowLabel(profile: profile)
                            Spacer()
                            Text("Pending").font(.caption).foregroundStyle(.secondary)
                            Button("Cancel") { Task { await model.remove(profile) } }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            // MARK: Suggestions
            if !model.suggestions.isEmpty {
                Section("Suggested for you") {
                    ForEach(model.suggestions) { suggestion in
                        HStack {
                            NavigationLink { ProfileDetailView(profile: suggestion.profile) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    ProfileRowLabel(profile: suggestion.profile)
                                    Text(mutualText(suggestion.mutualCount))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Button("Add") { Task { await model.sendRequest(to: suggestion.profile) } }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // MARK: Friends
            Section("Friends (\(model.friends.count))") {
                if model.friends.isEmpty {
                    Text("No friends yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(model.friends) { profile in
                        NavigationLink { ProfileDetailView(profile: profile) } label: {
                            ProfileRowLabel(profile: profile)
                        }
                    }
                    .onDelete { indexSet in
                        let targets = indexSet.map { model.friends[$0] }
                        Task { for t in targets { await model.remove(t) } }
                    }
                }
            }

            if let error = model.error {
                Section { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .overlay { if model.loading && model.friends.isEmpty { ProgressView() } }
        .refreshable { await model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .friendGraphChanged)) { _ in
            Task { await model.reload() }
        }
    }

    /// Status-aware action for the search result.
    @ViewBuilder
    private func searchActionButton(_ model: FriendsModel, for profile: SharedProfile) -> some View {
        switch model.relationship(to: profile.userID) {
        case .isMe:
            Text("That's you").font(.caption).foregroundStyle(.secondary)
        case .friend:
            Label("Friends", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
        case .outgoing:
            Text("Requested").font(.caption).foregroundStyle(.secondary)
        case .incoming:
            Button("Accept") {
                Task { await model.accept(profile); clearSearch() }
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        case .none:
            Button("Request") {
                Task { await model.sendRequest(to: profile); clearSearch() }
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
    }

    private func mutualText(_ count: Int) -> String {
        count == 1 ? "1 mutual friend" : "\(count) mutual friends"
    }

    private func search(_ model: FriendsModel) {
        searching = true
        searchResult = nil
        searchMessage = nil
        Task {
            if let found = await model.findProfile(handle: searchHandle) {
                searchResult = found
            } else {
                searchMessage = "No user found with that handle."
            }
            searching = false
        }
    }

    private func clearSearch() {
        searchResult = nil
        searchHandle = ""
        searchMessage = nil
    }
}

/// Compact identity row: avatar initial, display name, @handle, level.
struct ProfileRowLabel: View {
    let profile: SharedProfile

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(profile: profile, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName).font(.body)
                Text("@\(profile.handle) · Lvl \(profile.level)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
