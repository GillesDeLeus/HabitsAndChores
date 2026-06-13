import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("appLanguage") private var appLanguage = "en"
    @AppStorage("appAppearance") private var appearance = "system"
    #if DEBUG
    @State private var devAlert: String?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                AccountSection()

                Section(header: Text("Language")) {
                    Picker("Language", selection: $appLanguage) {
                        Text("English").tag("en")
                        // Additional languages can be added here as the catalog grows.
                    }
                    Text("More languages are coming soon.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Notifications")) {
                    Button("Open notification settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section(header: Text("Sharing")) {
                    NavigationLink {
                        HouseholdsView()
                    } label: {
                        Label("Household chores", systemImage: "house.and.flag.fill")
                    }
                }

                Section(header: Text("Data")) {
                    Link(destination: URL(string: "https://www.apple.com/icloud/")!) {
                        Label("iCloud sync is automatic", systemImage: "icloud.fill")
                    }
                    NavigationLink {
                        DataExportView()
                    } label: {
                        Label("Export my data", systemImage: "square.and.arrow.up")
                    }
                }

                Section(header: Text("Legal")) {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                    NavigationLink {
                        TermsView()
                    } label: {
                        Label("Terms & Community Guidelines", systemImage: "doc.text.fill")
                    }
                    LabeledContent("License", value: "MIT")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } footer: {
                    Text("Habits & Chores keeps your data private on your device and your iCloud account. © 2026 Gilles De Leus.")
                }

                #if DEBUG
                Section(header: Text("Developer")) {
                    Button("Load sample data") {
                        if case let .message(text) = SampleData.populate(context) { devAlert = text }
                    }
                    Button("Delete all data", role: .destructive) {
                        if case let .message(text) = SampleData.wipe(context) { devAlert = text }
                    }
                    Text("Test data only — not included in release builds. “Load sample data” does nothing if tasks already exist.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                #endif
            }
            .navigationTitle("Settings")
            .preferredColorScheme(colorScheme)
            #if DEBUG
            .alert("Sample data", isPresented: .constant(devAlert != nil), presenting: devAlert) { _ in
                Button("OK") { devAlert = nil }
            } message: { Text($0) }
            #endif
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

#Preview {
    SettingsView()
        .environment(SocialAccount())
}
