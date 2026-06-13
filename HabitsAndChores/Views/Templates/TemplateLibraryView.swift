import SwiftUI
import SwiftData

/// Browse the built-in habits & chores and add them to the user's schedule.
struct TemplateLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [TaskItem]

    @State private var search = ""

    private var addedTemplateIDs: Set<String> {
        Set(existing.compactMap { $0.createdFromTemplateID })
    }

    private var groups: [(category: TaskCategory, templates: [TaskTemplate])] {
        TemplateLibrary.byCategory().compactMap { group in
            let filtered = search.isEmpty ? group.templates : group.templates.filter {
                $0.title.localizedCaseInsensitiveContains(search)
            }
            return filtered.isEmpty ? nil : (group.category, filtered)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.category) { group in
                    Section(header: Label(group.category.localizedName, systemImage: group.category.symbolName)) {
                        ForEach(group.templates) { template in
                            row(template)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search habits & chores")
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ template: TaskTemplate) -> some View {
        let alreadyAdded = addedTemplateIDs.contains(template.id)
        return HStack(spacing: 12) {
            Image(systemName: template.symbolName)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color(hue: template.colorHue, saturation: 0.65, brightness: 0.9),
                            in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                Text(template.defaultFrequency.localizedDescription)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { add(template) } label: {
                Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(alreadyAdded ? .green : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(alreadyAdded)
        }
    }

    private func add(_ template: TaskTemplate) {
        let task = template.makeTaskItem()
        context.insert(task)
        try? context.save()
        Task { await NotificationManager.shared.reschedule(for: task) }
    }
}

#Preview {
    TemplateLibraryView()
        .modelContainer(PreviewData.container)
}
