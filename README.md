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
[XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project file never has to be
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
    └── Localizable.xcstrings  String Catalog (ships in 7 languages — see below)

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
  / the String Catalog (ships in seven languages — see below); adding another is
  a translation task with no code changes.
- **Recurrence covers fixed *and* floating schedules.** Beyond daily / specific
  weekdays / day-of-month / every-N, the **"Anytime"** mode is due *once within a
  period* (e.g. once a week or month) with no fixed day: it stays outstanding in
  Today all period until done once, while the calendar and stats show a single
  occurrence per period. Streaks count periods, so an in-progress period never
  breaks a run.
- **Private vs. shared is a field, not a separate screen.** Every task/to-do
  editor has a `Household` picker: *Private* stores a local SwiftData object
  (mirrored only to your own devices); choosing a household writes a `SharedChore`
  into a CloudKit `CKShare` zone visible to its members. Both surface together in
  the normal Today / Tasks / To-Do lists.

## Localization

Ships in **English, French, Dutch, Italian, Polish, Spanish and German** (String
Catalog). Settings → Language offers System + each language; the choice applies
**live, with no relaunch** — `LanguageManager` swizzles `Bundle.main` to resolve
strings from the chosen `.lproj` immediately (it does *not* use `AppleLanguages`).
Notes:

- **Coverage is complete:** every non-stale catalog key is translated in all seven
  languages, including the built-in template titles/details (`Templates.json`'s
  `titleKey`/`detailsKey`, which are added to the catalog manually because their
  runtime-variable lookup is invisible to Xcode's extractor).
- Translations are a **machine-generated first pass** and should get **native
  review** before store submission — coverage is guaranteed, idiomatic quality is
  not (plurals, especially Polish, are simplified).
- Re-running a machine pass / adding strings: edit the translation map and apply it
  with `scripts/merge_translations.py`. `Tests/LocalizationCoverageTests.swift`
  fails CI if any advertised language is left untranslated.
- **The legal screens are intentionally English-only.** The Privacy Policy and
  Terms & Community Guidelines bodies (`PrivacyPolicyView` / `TermsView`, mirroring
  `PRIVACY.md` / `TERMS.md`) render verbatim and are *not* in the catalog — machine-
  translated legal text is a liability, and Apple does not require a localized
  policy. Only the chrome (navigation titles, section headers, "Last updated") is
  localized. Translate the bodies only with native legal review.

## Roadmap ideas (not yet built)

- Apple Watch companion
- EventKit export to the system Calendar
- Native (human) review of the machine-generated translations before submission
```
