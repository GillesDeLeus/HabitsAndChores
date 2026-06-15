# Habits & Chores

A native iOS app for tracking habits, chores, and to-dos with flexible
recurrence, a calendar view, a built-in template library, reminders, streaks,
stats, gamification, searchable & filterable lists, optional friends, shareable
households, iCloud sync, and a home-screen widget.

- **Platform:** iOS 17+
- **UI:** SwiftUI
- **Persistence:** SwiftData (automatic CloudKit/iCloud sync) for personal data,
  plus CloudKit `CKShare` for shared households.
- **Architecture:** Lightweight MVVM — models + stateless engines
  (`SchedulingEngine`, `GamificationEngine`); views query SwiftData directly, and
  a shared `HouseholdsModel` (in the environment) provides the CloudKit-shared
  household data to every tab.

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
├── Models/               TaskItem, TodoItem, Completion, FrequencyRule (SwiftData)
├── Services/
│   ├── SchedulingEngine  Turns FrequencyRule → concrete occurrence dates; streaks
│   ├── GamificationEngine  Points, levels, badges, weekly goal (derived)
│   ├── NotificationManager  Local reminder scheduling (personal + shared tasks)
│   ├── TemplateLibrary   Loads bundled Templates.json
│   ├── Household/        HouseholdService — CloudKit CKShare households & shared tasks
│   ├── Social/           Account, profiles, friends graph (CloudKit public DB)
│   └── PreviewData       In-memory seed for SwiftUI previews
├── Views/
│   ├── RootTabView       5-tab shell (Today, Tasks, Stats, Awards, Settings)
│   ├── Today/            Due-today list (personal + shared) + progress ring
│   ├── Calendar/         Month grid with per-day indicators + day detail
│   ├── Tasks/            Recurring list + add/edit; Household & Assignee pickers
│   ├── Todo/             One-off to-do list + editor (also shareable)
│   ├── Templates/        Built-in library browser ("+ add to schedule")
│   ├── Stats/            7-day chart + per-task completion & streaks
│   ├── Awards/           Badges & gamification progress
│   ├── Friends/          Optional social: profiles, friend requests
│   ├── Household/        Create/join households, members, invites
│   ├── Onboarding/       First-run guided intro
│   ├── Settings/         Language, appearance, notifications, account
│   └── Components/       Reusable rows (TaskRow, SharedTaskRow, …)
└── Resources/
    ├── Templates.json    ~30 built-in habits & chores
    └── Localizable.xcstrings  String Catalog (English; ready for more languages)

HabitsAndChoresWidget/    WidgetKit "Today" widget (reads the shared local store)
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
- **Private vs. shared is a field, not a separate screen.** Every task/to-do
  editor has a `Household` picker: *Private* stores a local SwiftData object
  (mirrored only to your own devices); choosing a household writes a `SharedChore`
  into a CloudKit `CKShare` zone visible to its members. Both surface together in
  the normal Today / Tasks / To-Do lists.

## Localization

Ships in **English, French, Dutch, Italian, Polish, Spanish and German** (String
Catalog). Settings → Language offers System + each language (in-app override via
`AppleLanguages`, applied on next launch). Notes:

- The catalog's established UI strings are translated; strings added since the
  catalog was last extracted in Xcode need an Xcode build (to extract them) then
  translation. Run `/tmp`-style extraction or open the project in Xcode to refresh.
- Translations are a first machine-assisted pass and should get **native review**
  before store submission. `Templates.json` content (`titleKey`/`detailsKey`) is
  not yet translated.

## Roadmap ideas (not yet built)

- Apple Watch companion
- EventKit export to the system Calendar
- Per-language native translation review; translate the built-in templates
```
