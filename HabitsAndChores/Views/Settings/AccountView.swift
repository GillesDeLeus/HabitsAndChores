import SwiftUI
import SwiftData
import AuthenticationServices

/// The "Account" section shown in Settings. Reflects the opt-in state and hosts
/// the create / leave flows. Everything here is inert until the user opts in.
struct AccountSection: View {
    @Environment(SocialAccount.self) private var account
    @State private var showingCreate = false
    @State private var showingAvatar = false
    @State private var leaving = false
    @State private var errorMessage: String?

    private let service: SocialService = CloudKitSocialService()

    var body: some View {
        Section {
            switch account.state {
            case .anonymous:
                Button {
                    showingCreate = true
                } label: {
                    Label("Create an account", systemImage: "person.crop.circle.badge.plus")
                }
            case let .active(userID, handle):
                HStack(spacing: 12) {
                    AvatarView(account: account, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName.isEmpty ? "@\(handle)" : account.displayName)
                            .font(.headline)
                        Text("@\(handle)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button {
                    showingAvatar = true
                } label: {
                    Label("Edit avatar", systemImage: "person.crop.circle.badge.photo")
                }
                Button(role: .destructive) {
                    leave(userID: userID, handle: handle)
                } label: {
                    if leaving { ProgressView() } else { Text("Leave & delete profile") }
                }
                .disabled(leaving)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Optional. Without an account the app stays fully private on your device and iCloud. Creating an account publishes a public profile (handle, level, streaks, badges) so friends can find you.")
        }
        .sheet(isPresented: $showingCreate) {
            CreateAccountSheet(service: service)
        }
        .sheet(isPresented: $showingAvatar) {
            AvatarEditorView(service: service)
        }
        .alert("Account", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { Text($0) }
    }

    private func leave(userID: String, handle: String) {
        leaving = true
        Task {
            await SocialPushManager.removeSubscription(for: userID)
            try? await service.deleteAccount(userID: userID, handle: handle)
            account.markLeft()
            leaving = false
        }
    }
}

/// Two-step flow: Sign in with Apple, then choose a handle. On success the profile
/// is published and the account is marked active.
private struct CreateAccountSheet: View {
    let service: SocialService

    @Environment(\.dismiss) private var dismiss
    @Environment(SocialAccount.self) private var account
    @Query(filter: #Predicate<TaskItem> { !$0.isArchived }) private var tasks: [TaskItem]

    private enum Step { case signIn, handle }
    @State private var step: Step = .signIn
    @State private var pendingUserID = ""
    @State private var suggestedName = ""
    @State private var handleInput = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .signIn:
                    Section {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName]
                        } onCompletion: { result in
                            handleSignIn(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 48)
                    } footer: {
                        Text("Sign in with Apple gives you a private, durable identity. Your real name and email are never shared with other users.")
                    }
                case .handle:
                    Section {
                        TextField("handle", text: $handleInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            createAccount()
                        } label: {
                            if busy { ProgressView() } else { Text("Create profile") }
                        }
                        .disabled(busy || normalizedHandle(handleInput) == nil)
                    } header: {
                        Text("Choose a handle")
                    } footer: {
                        Text("3–20 characters: letters, numbers, or underscore. This is how friends find you.")
                    }
                }
            }
            .navigationTitle("Create account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn’t create account", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { Text($0) }
        }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            pendingUserID = credential.user
            if let given = credential.fullName?.givenName, !given.isEmpty {
                suggestedName = given
                handleInput = given.lowercased()
            }
            step = .handle
        case let .failure(error):
            // User cancellation is not an error worth surfacing.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createAccount() {
        guard let handle = normalizedHandle(handleInput) else {
            errorMessage = SocialError.invalidHandle.errorDescription
            return
        }
        busy = true
        Task {
            do {
                guard await service.isAvailable() else { throw SocialError.iCloudUnavailable }
                try await service.claimHandle(handle, for: pendingUserID)
                let summary = GamificationEngine.summary(for: tasks)
                let profile = SharedProfile(
                    userID: pendingUserID,
                    handle: handle,
                    displayName: suggestedName.isEmpty ? handle : suggestedName,
                    summary: summary
                )
                try await service.publish(profile)
                account.markJoined(userID: pendingUserID, handle: handle,
                                   displayName: suggestedName.isEmpty ? handle : suggestedName)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            busy = false
        }
    }
}
