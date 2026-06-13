# Habits & Chores

A native iOS app for tracking habits and chores with flexible recurrence, a
calendar view, a built-in template library, reminders, streaks, stats, iCloud
sync, and a home-screen widget.

- **Platform:** iOS 17+
- **UI:** SwiftUI
- **Persistence:** SwiftData (with automatic CloudKit/iCloud sync)
- **Architecture:** Lightweight MVVM — models + a stateless `SchedulingEngine`,
  views query SwiftData directly.

## Getting started

This repo contains source only. The `.xcodeproj` is generated with
[XcodeGen](https://github.com/yonyz/XcodeGen) so the project file never has to be
hand-merged.

```bash
brew install xcodegen      # one-time
cd HabitsAndChores
xcodegen generate          # creates HabitsAndChores.xcodeproj
open HabitsAndChores.xcodeproj
```

Then in Xcode:

1. Set your **Development Team** on both targets (Signing & Capabilities), or set
   it once in `project.yml` under `settings.base.DEVELOPMENT_TEAM`.
2. To enable iCloud sync, add the **iCloud → CloudKit** capability and a
   background mode of *Remote notifications* on the app target. Without it the
   app automatically falls back to a local-only store (see
   `HabitsAndChoresApp.swift`).
3. Build & run on the iOS 17+ simulator or a device.

> The repo intentionally omits the generated `.xcodeproj` (see `.gitignore`).
> Run `xcodegen generate` after pulling.

## Project layout

```
HabitsAndChores/
├── App/                  App entry, ModelContainer setup (+ iCloud)
├── Models/               TaskItem, Completion, FrequencyRule, enums (SwiftData)
├── Services/
│   ├── SchedulingEngine  Turns FrequencyRule → concrete occurrence dates; streaks
│   ├── NotificationManager  Local reminder scheduling
│   ├── TemplateLibrary   Loads bundled Templates.json
│   └── PreviewData       In-memory seed for SwiftUI previews
├── Views/
│   ├── RootTabView       5-tab shell
│   ├── Today/            Due-today list + progress ring
│   ├── Calendar/         Month grid with per-day indicators + day detail
│   ├── Tasks/            List, add/edit, frequency & reminder pickers
│   ├── Templates/        Built-in library browser ("+ add to schedule")
│   ├── Stats/            7-day chart + per-task completion & streaks
│   ├── Settings/         Language (English), appearance, notifications
│   └── Components/        Reusable TaskRow
└── Resources/
    ├── Templates.json    ~30 built-in habits & chores
    └── Localizable.xcstrings  String Catalog (English; ready for more languages)

HabitsAndChoresWidget/    WidgetKit "Today" widget (reads the shared store)
```

## Key design decisions

- **Occurrences are computed, not stored.** `SchedulingEngine` derives scheduled
  dates from a task's `FrequencyRule` for any date range, so changing a
  frequency instantly re-projects the whole calendar with no migration.
- **Completions are the only event records.** A `Completion(scheduledDate,
  status)` is written when the user checks something off; everything else
  (streaks, stats, today's progress) is derived.
- **Templates are clones.** Adding a template copies it into a user-owned
  `TaskItem` (`createdFromTemplateID` tracks origin) so edits never mutate the
  library.
- **Localization-first.** All user-facing strings go through `String(localized:)`
  / the String Catalog. Only English ships now; adding a language is a
  translation task with no code changes.

## Localization

To add a language later: open `Localizable.xcstrings` in Xcode, add the language,
translate the entries (and the `titleKey`/`detailsKey` values referenced by
`Templates.json`), then add it to the picker in `SettingsView`.

## Roadmap ideas (not yet built)

- Household/multi-user shared chores with rotation
- Apple Watch companion
- EventKit export to the system Calendar
- Gamification (points / badges)
- Smart template suggestions
```
