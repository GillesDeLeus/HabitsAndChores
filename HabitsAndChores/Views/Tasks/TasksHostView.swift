import SwiftUI

/// Hosts the recurring-tasks list and the one-off to-do list under a single tab,
/// switched by a segmented control in the navigation bar.
struct TasksHostView: View {
    enum Section: String, CaseIterable, Identifiable {
        case recurring, todo
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recurring: return String(localized: "Recurring")
            case .todo:      return String(localized: "To-Do")
            }
        }
    }

    @State private var section: Section = .recurring

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // The section switcher lives in the body (not a `.principal` toolbar
                // item) so it's always visible — a toolbar-centered control gets
                // squeezed out when the list's own bar buttons plus the Settings gear
                // crowd the navigation bar on narrower devices.
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 6)

                Group {
                    switch section {
                    case .recurring: TaskListView()
                    case .todo:      TodoListView()
                    }
                }
            }
            .settingsToolbar()
        }
    }
}
