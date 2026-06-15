<style>
  @page { size: A4; margin: 18mm 16mm; }
  body { font-family: -apple-system, "Helvetica Neue", Arial, sans-serif; color: #1d1d1f; font-size: 11pt; line-height: 1.5; max-width: 100%; }
  h1 { font-size: 26pt; margin: 0 0 2px; color: #0a2540; }
  .sub { color: #6b7280; font-size: 11pt; margin: 0 0 4px; font-weight: 600; }
  .meta { color: #9ca3af; font-size: 9.5pt; margin-bottom: 16px; }
  h2 { font-size: 15pt; color: #0a66c2; border-bottom: 2px solid #e5e7eb; padding-bottom: 4px; margin: 26px 0 10px; }
  h3 { font-size: 12pt; color: #0a2540; margin: 16px 0 4px; }
  ul { margin: 6px 0 10px; padding-left: 20px; }
  li { margin: 4px 0; }
  p { margin: 6px 0; }
  code { background: #f3f4f6; padding: 1px 4px; border-radius: 3px; font-size: 9.5pt; font-family: "SF Mono", Menlo, monospace; }
  .tag { display: inline-block; font-size: 8pt; font-weight: 700; padding: 1px 6px; border-radius: 10px; color: #fff; vertical-align: middle; }
  .high { background: #dc2626; } .med { background: #d97706; } .low { background: #2563eb; } .ok { background: #16a34a; } .done { background: #059669; }
  table { width: 100%; border-collapse: collapse; margin: 8px 0 14px; font-size: 10pt; }
  th, td { border: 1px solid #e5e7eb; padding: 6px 8px; text-align: left; vertical-align: top; }
  th { background: #f3f4f6; }
  .box { background: #f8fafc; border: 1px solid #e5e7eb; border-radius: 8px; padding: 10px 14px; margin: 10px 0; }
  .green { background: #ecfdf5; border-color: #a7f3d0; }
  .lead { color: #374151; }
  .fig { margin: 12px 0 16px; page-break-inside: avoid; }
  .fig svg { width: 100%; height: auto; border: 1px solid #e5e7eb; border-radius: 8px; background: #fff; }
  figcaption { font-size: 9.5pt; color: #6b7280; margin-top: 5px; line-height: 1.4; }
  footer { margin-top: 24px; color: #9ca3af; font-size: 9pt; border-top: 1px solid #e5e7eb; padding-top: 6px; }
</style>

# Habits & Chores

<p class="sub">Complete Application Review — Revision 9</p>
<p class="meta">Updated 15 June 2026 · iOS 17+ · SwiftUI + SwiftData + CloudKit · ~9,000 lines Swift across 73 files (incl. 58 unit tests) · public repo <code>github.com/GillesDeLeus/HabitsAndChores</code> (MIT)</p>

<div class="box green">
<strong>What changed.</strong> Earlier revisions resolved code-quality, App Store compliance, and functional-feature gaps, then added household sharing via CloudKit <code>CKShare</code> (Rev. 5), completed its two P1 items — per-occurrence completion and live-update push (Rev. 6) — and added first-run onboarding while expanding the suite to 50 tests (Rev. 7). <strong>Rev. 8 reworks household sharing into the normal task flow:</strong> chores are no longer created <em>inside</em> a household. Instead every task / habit / to-do / chore editor gains a <strong>Household</strong> field (Private by default, or any household you belong to) plus an <strong>Assignee</strong> picker, and shared items now appear in <em>each member's</em> normal Today / Tasks / To-Do lists. One-off to-dos are shareable too, and each device schedules local reminders for the shared tasks it sees. <strong>Rev. 9 is a hardening pass:</strong> a durable offline outbox for household writes, incremental sync (skip the full re-fetch when nothing changed), Sign in with Apple revocation handling, a lightweight local crash logger, live in-app language switching, and a per-member fairness/activity view. The cross-user surface (friends, invites, assignment) has now been tested on two devices with two iCloud accounts. Remaining work is mostly operational App Store readiness (production CloudKit deploy, submission assets, localization review).
</div>

## 1. What works well

- **Derived-data architecture.** A stateless `SchedulingEngine` projects occurrences on demand; streaks, stats and "today" are computed, never denormalized.
- **Clean layering & isolation.** Models / Services / Views are well separated; the social layer sits behind a `SocialService` protocol with a CloudKit implementation.
- **Unified task surface (new).** Personal and shared household tasks are created in the *same* editors and listed together in Today / Tasks / To-Do; picking a household routes the item into the shared CloudKit zone and assigns a member. The old "create chores inside a household" screen is gone, removing the parallel task world (see §7).
- **Privacy-respecting opt-in social.** `SocialAccount` gates every network write — anonymous users' data never leaves the device.
- **Robust error handling.** `ModelContext.saveOrReport()` logs failures via `os.Logger` and surfaces a transient banner; scattered silent `try? save()` calls are gone from production paths.
- **Fresh public profiles.** `ProfileSync` re-publishes the derived summary on app active/background (throttled), so friends don't see stale stats.
- **Compliance scaffolding.** Privacy manifest, in-app Privacy Policy & Terms, content moderation, and block/report/delete-account flows are in place.
- **Correct CloudKit social-graph modelling.** Mutual friendship via two owner-owned `FriendEdge` records respects CloudKit's creator-only-write rule.
- **Zero third-party dependencies;** reproducible project (XcodeGen + an explicit shared scheme); localization-first via the String Catalog, now shipping **7 languages** (en/fr/nl/it/pl/es/de) with an in-app language picker (see §2 for the translation-completeness caveat).
- **Household fairness (new).** A per-member completion-history view shows who's pulling their weight over the last 30 days, plus a recent-activity feed.
- **Operational hardening (Rev. 9).** Durable offline outbox (household writes survive a kill/offline and replay idempotently); incremental sync via per-database `CKServerChangeToken` (skips the full re-fetch when nothing changed); Sign in with Apple revocation → local sign-out on launch; a dependency-free local crash logger; and live in-app language switching (no relaunch).
- **Mature feature depth.** To-dos (private *and* shared household ones) support a due date *and* a separate **scheduled "do" day** (which surfaces them in Today), recurring/relative reminders, priority, notes, category and manual ordering; both lists have search, sort, **filtering** (habits/chores by type & category; to-dos by category & priority) and drag-reordering; tasks use a colour-swatch picker; users can edit their display name and export all their data as JSON.
- **Tested core.** A 58-case unit-test target covers the pure engines (scheduling, streaks, gamification, friend graph, household occurrence/recurrence, shared-draft / to-do mapping, chore **rotation**, and the offline-outbox serialization), the models, helpers, and the `FriendsModel` view-model, plus a regression test that keeps the data model CloudKit-valid.
- **Guided first run.** A one-time onboarding flow introduces habits vs. chores, the template library, and the optional account; the notification permission is requested after it rather than over it.
- **Household sharing.** Native `CKShare`-based shared households with assignable recurring chores *and* one-off to-dos, created from the normal editors; invite by link or directly from friends; optimistic local updates with background sync. No server required (see §7).
- **Open-sourced.** Public GitHub repo under the MIT license, with the privacy policy hosted there.

## 2. What could be improved

### Resolved

<span class="tag done">DONE</span> Error handling · <span class="tag done">DONE</span> Profile freshness · <span class="tag done">DONE</span> Summary recomputation (cached) · <span class="tag done">DONE</span> Batched suggestion queries · <span class="tag done">DONE</span> Observability (`os.Logger`) · <span class="tag done">DONE</span> CloudKit fallback diagnostic · <span class="tag done">DONE</span> Automated tests · <span class="tag done">DONE</span> CloudKit model validity · <span class="tag done">DONE</span> Household chores isolated from the app's own lists (Rev. 8 — now surfaced in Today / Tasks / To-Do).

### Still open / new

| Area | Issue | Suggested fix |
|---|---|---|
| <span class="tag med">MED</span> Test breadth | The engines and draft mapping are covered; views, the social service, CloudKit I/O, and UI flows are not. | Add view-model / integration tests (and optionally UI tests) over time. |
| <span class="tag med">MED</span> Moderation depth | The handle/name profanity filter is a small, illustrative substring blocklist. | Expand the list / use a maintained dataset; consider normalization (leetspeak, spacing). |
| <span class="tag med">MED</span> Accessibility (partial) | Labels and 44 pt hit targets were added, but a full VoiceOver + Dynamic Type pass hasn't been done. | Audit large text sizes and full VoiceOver navigation across screens. |
| <span class="tag low">LOW</span> Summary key edge case | The cache key counts completions; a status-only change (done↔skipped) at equal count wouldn't trigger recompute (doesn't occur in current flows). | Include a status hash if skip-toggling is ever added to Today. |
| <span class="tag med">MED</span> Localization (in progress) | Ships en/fr/nl/it/pl/es/de; the established catalog strings are translated (machine-assisted), but ~50 recently-added strings need an Xcode extraction pass, and all translations need native review. `Templates.json` content untranslated. | Open in Xcode to extract remaining strings; commission native review; translate the template library. |

## 3. Missing features

*Most prior gaps are now implemented:* block, report, account deletion, terms acceptance, content moderation, display-name editing, data export, to-do depth, task search/sort/group/reorder/**filter**, first-run onboarding, and — new in Rev. 8 — shared household tasks surfaced inside the normal lists, shareable one-off to-dos, list filtering (type/category/priority), and a colour-swatch picker.

### Remaining functional gaps

- **Household completion has no history UI** — per-occurrence completion data exists, but there's no per-member fairness/streak view built on it yet (see §7).
- **Household tasks don't gamify** — by design, shared tasks contribute to the day's "X/Y" count but not to streaks, points, Stats, or the widget (which stay personal/local-only).

*(To-do reminders — fixed-date only, previously listed here — now support recurring and relative ("before due") options.)*

### Roadmap-level (per README)

- Apple Watch companion; Lock-Screen / accessory widgets (and a to-do widget); EventKit export; "streak about to break" nudges; additional languages. *(Household / multi-user shared chores — and, new in Rev. 8, unifying them with personal tasks — are implemented; see §7.)*

## 4. Codebase quality

**Overall: good, and improved since Rev. 1.** ~7,100 lines of app code across 58 well-named files (plus 12 test files), consistent SwiftUI idioms, no dependencies.

| Dimension | Assessment |
|---|---|
| Structure & naming | <span class="tag ok">Strong</span> — clear folders, small focused types, intent-revealing comments. |
| Error handling | <span class="tag ok">Now solid</span> — centralized `saveOrReport()` + banner; only preview/sample helpers use `try?`. |
| Observability | <span class="tag ok">Present</span> — structured `os.Logger` categories; no stray `print()`. |
| Tests | <span class="tag ok">Now present</span> — 58 unit tests across the pure engines, models, helpers, the `FriendsModel` view-model, household occurrence logic, shared-draft / to-do mapping, chore rotation, and outbox serialization, plus a CloudKit-schema regression test. SwiftUI views and CloudKit I/O remain untested. |
| Data model / CloudKit | <span class="tag ok">Fixed</span> — models are CloudKit-valid (defaulted attributes, optional relationship); the app no longer silently degrades to local-only. |
| View complexity | <span class="tag low">Minor</span> — a few long view bodies (the task/to-do editors grew with the Sharing section) could be decomposed. |

## 5. Open items

- **Deploy the CloudKit schema Development → Production** — record types `Profile`, `Handle`, `FriendEdge` (with queryable `owner`/`other` indexes), `Report`, `HouseholdInvite` (with a queryable `invitee` index for in-app invitations), and the household types `Household`, `SharedChore`, `SharedCompletion`. **New in Rev. 8:** `SharedChore` gained fields `isTodo`, `dueDate`, `scheduledDate`, `priority`, `reminderMode`, `reminderDate`, `reminderOffset`, `reminderHour`, `reminderMinute`, `rotates`, and `Household` gained a `memberNames` field — these auto-create in Development on first write but must be deployed to Production before release. The app still runs against Development.
- **Verify SwiftData↔CloudKit personal sync** across a user's *own* devices (the household/social cross-user flows are now two-device tested; the `.automatic` personal mirror still warrants a same-account multi-device check, and existing local-only installs start fresh once CloudKit engages).
- **Expand the moderation blocklist** before exposing accounts widely.
- *Resolved:* automated tests added/expanded (now 58); CloudKit model validity; profile staleness; silent save failures; household chores unified with the lists; **offline durability (outbox)**; **incremental sync (change tokens)**; **Sign in with Apple revocation**; **local crash logging**; the two-device test pass of friends/invites/assignment.

## 6. What is missing to publish to the App Store

*The compliance blockers from Rev. 1 are largely closed. What remains is mostly operational + submission assets.*

### Now done

<span class="tag done">DONE</span> Privacy manifest · <span class="tag done">DONE</span> Hosted privacy policy URL · <span class="tag done">DONE</span> In-app account deletion · <span class="tag done">DONE</span> Block, Report, content moderation, and Terms/EULA acceptance (Guideline 1.2) · <span class="tag done">DONE</span> App icon (present) · <span class="tag done">DONE</span> Sign in with Apple revocation handling (Rev. 9) · <span class="tag done">DONE</span> Two-device test of friends / invites / assignment.

### Still required

- **CloudKit Production deploy** — the **#1 remaining blocker.** All record types/fields used by social + households (incl. `Report`, `HouseholdInvite`, `Household.memberNames`, and the `SharedChore` to-do/reminder/`rotates`/`scheduledDate` fields, with queryable indexes) must be deployed; a released build cannot use the Development environment.
- **Distribution signing & build** — App Store provisioning + distribution certificate; verify push with the production `aps-environment`; unique, incrementing build numbers.
- **App Store Connect metadata** — name, subtitle, description, keywords, support URL, category; screenshots for required device sizes; age rating; export-compliance answer.
- **App Privacy answers** in ASC must match the privacy manifest.
- **Localization decision** — ship English-only for v1, or finish + natively review the 7-language translations (see §2) before submitting.

### Recommended before submitting

- A **TestFlight beta** and a real **two-device** pass of friends + push *and* the shared-household flow (assign a task on device A, confirm it appears in member B's normal lists and B can complete it).
- Confirm the **widget** works with no account / no data; basic **accessibility** pass.

## 7. Household feature — in-depth analysis

### Architecture

Households are implemented as a **direct CloudKit layer** (not SwiftData, which lacks real `CKShare` support): each household is a root `CKRecord` in its own **custom zone** in the owner's private database, wrapped in a `CKShare`; shared tasks are child records of that root, so they share together. Members are `CKShare` participants. Records are read with `CKFetchRecordZoneChangesOperation` across the private + shared databases, behind one app-wide `HouseholdsModel` injected via the environment. The UI uses **optimistic mutations** (update locally, persist in the background, then quietly reconcile).

**New in Rev. 8 — sharing is a field on the normal flow, not a separate screen.** The in-household "add chore" editor is removed. Instead the standard task and to-do editors carry a **Household** picker (Private = a local SwiftData object, as before; or a household = a shared `CKRecord`) and an **Assignee** picker over that household's members. Saving routes the item to the chosen store; changing the picker on an existing item *moves* it between the SwiftData store and the shared zone (delete-here / create-there, which resets that item's completion history). To carry one-off to-dos, the single `SharedChore` record gained an `isTodo` discriminator plus due-date / priority / reminder fields — one record type, one fetch path, and the existing `SharedCompletion` mechanism (keyed by a fixed sentinel occurrence for to-dos) serve both. Shared items are merged into Today / Tasks / To-Do **at display time** (no SwiftData mirroring, so no two-way-sync risk), and after each sync every member's device schedules local reminders for the shared tasks it can see.

### What works well

- **No server** — data lives in members' iCloud; Apple manages sharing, permissions, and transport.
- **Correct sharing primitives** — custom zone + root `CKShare` + child records is the canonical pattern; reading via zone-changes avoids the queryable-index pitfall that first broke persistence.
- **One task vocabulary** — shared items reuse the app's type, category, recurrence, icon, colour, reminder and (now) to-do fields, created in the same editors as personal tasks.
- **Unified, single-surface UX (new)** — shared tasks merge into the normal lists, badged with the household. **Today** shows only what's assigned to *you* (your actionable items); the **Tasks / To-Do** lists and the household's own screen show *all* of the household's tasks whoever they're assigned to. No separate "household tasks" world to context-switch into.
- **Snappy UX** — optimistic local updates remove the per-action sync delay.
- **In-app invitations (new)** — an existing friend can be invited from the household; they receive a push and an in-app invitation (a `HouseholdInvite` record in the public database carrying the share URL) and **accept inside the app** — no manual link to send. A system share link remains available for inviting non-friends.

### Resolved

- <span class="tag done">DONE</span> **Per-occurrence completion** & <span class="tag done">DONE</span> **live-update push** (Rev. 6) — a `SharedCompletion` record (chore + occurrence date + who) replaces the flat flag, and a `CKDatabaseSubscription` pushes a member's change to the others.
- <span class="tag done">DONE</span> **Isolation from the app (Rev. 8)** — shared chores and to-dos now appear in Today / Tasks / To-Do alongside personal tasks; the previously "parallel world" is unified, and the prior P3 idea of "surface assigned-to-me household chores in Today" is implemented (for all members, not only the assignee).
- <span class="tag done">DONE</span> **Shareable to-dos (Rev. 8)** — one-off to-dos can be assigned to a household via `SharedChore.isTodo`, with due date / priority / reminder carried on the shared record.
- <span class="tag done">DONE</span> **Reminders for shared tasks (Rev. 8)** — each member's device (re)schedules local notifications for the shared tasks it sees after every sync, keyed by a stable id prefix so it stays idempotent.
- <span class="tag done">DONE</span> **In-app invitations (Rev. 8)** — inviting a friend no longer requires sending them a share link: a `HouseholdInvite` record (public DB, addressed to the invitee) plus a push subscription lets the friend accept from inside the app, which fetches the share metadata and runs `CKAcceptSharesOperation` programmatically. Mirrors the friend-request flow. (Accepted/declined invites are suppressed client-side, since the invitee can't delete the inviter-owned public record.)
- <span class="tag done">DONE</span> **Remove / leave (Rev. 8)** — the owner can remove a member (revokes their share participation) and any member can leave the household, via the household detail screen. Left households are suppressed locally (CKShare self-removal isn't always immediate, so this stops a left household popping back in). Leaving or being removed **clears that member's chore assignments** so no ghost-assigned tasks remain; the owner deleting removes the zone (and all its tasks) for everyone.
- <span class="tag done">DONE</span> **Optional assignment rotation (Rev. 8)** — a chore can carry `rotates`; on completion the assignee advances to the next household member (round-robin, retreats on un-completion), or stays put when off. Rotation math is pure and unit-tested.
- <span class="tag done">DONE</span> **Member names + assignee-scoped lists (Rev. 8)** — members self-publish their display name onto the household root record (`memberNames` map, keyed by CloudKit user record name), so everyone sees real names instead of "Owner/Member"; and **Today** shows the chores assigned to you plus unassigned/up-for-grabs ones (chores assigned to *others* stay out of your Today but remain visible in the Tasks list).

### Remaining gaps & risks

| Area | Issue |
|---|---|
| <span class="tag low">LOW</span> Per-zone deltas | Rev. 9 added per-database `CKServerChangeToken`s so a reload is **skipped entirely when nothing changed**; a *changed* reload still re-fetches all zones (per-zone record-level delta merge is the remaining optimization). |
| <span class="tag low">LOW</span> Member identity | Mostly resolved (Rev. 8): members self-publish their display name to the household so others see real names. Residual: a member invited by **link** who hasn't opened the app, or a non-social user, still falls back to "Owner/Member" until they publish; avatars aren't shown yet. |
| <span class="tag med">MED</span> Conflict handling | Edits use fetch-modify-save; concurrent edits are last-writer-wins with no retry on `serverRecordChanged`. |
| <span class="tag low">LOW</span> Move resets history | Moving a task between Private and a household physically changes stores, dropping that item's completion/streak history (an accepted trade-off, surfaced in the editor footer). |
| <span class="tag low">LOW</span> Member roles | Members can now be removed (by the owner) and can leave (Rev. 8); there's still no role management (e.g. promoting another owner). |
| <span class="tag low">LOW</span> Partly tested | The pure parts — occurrence/recurrence math, shared-draft and to-do mapping — are unit-tested; the CloudKit I/O (zones, shares, subscriptions, completion records, the merge-into-lists display path, and shared notification scheduling) still isn't and is hard to without a CloudKit harness. |

### Proposed improvements (remaining, prioritized)

- **P2 — Incremental sync.** Persist per-zone `CKServerChangeToken`s and use `CKFetchDatabaseChangesOperation` to fetch only what changed — faster reloads, real scalability.
- **P2 — Resolve members to app profiles.** Map each participant's CloudKit record id to their `SharedProfile` for consistent display names + avatars (also disambiguates the assignee picker).
- **P3 — Conflict-safe writes** (`CKModifyRecordsOperation` with retry on `serverRecordChanged`) and member **role** management (remove/leave now exist; promoting a co-owner does not), plus owner-side cleanup of stale `HouseholdInvite` records.
<span class="tag done">DONE</span> **Fairness / completion-history UI (Rev. 8)** — `HouseholdHistoryView` shows each member's completion share over the last 30 days (bars) plus a recent-activity feed, built from `SharedCompletion` records. Feeding shared completions into Stats/gamification remains out of scope (personal-only by design).
- <span class="tag done">DONE</span> **Durable offline writes (Rev. 9)** — a persisted, idempotent outbox (`HouseholdOutbox`) queues chore/completion/assign mutations to disk, so a write made offline (or interrupted by a kill) replays on next launch/foreground instead of being lost. Covered by serialization unit tests; online-only actions (create/invite/accept) still require connectivity.
- <span class="tag done">DONE</span> **Incremental sync (Rev. 9)** — per-database change tokens skip the full re-fetch when nothing changed, with a safe fall back to full fetch on token expiry/error.

**Status:** the P1 items (Rev. 6) made the household a genuine shared-chores system, and **Rev. 8 unifies it with the app's own task surface** — shared recurring chores and to-dos are created in the normal editors and listed in Today / Tasks / To-Do for every member. Remaining work is P2/P3 polish. Note the household record types/fields (incl. the new `SharedChore` to-do/reminder fields and `SharedCompletion`) still need a **Production CloudKit schema deploy**, and the multi-member flow still warrants a **two-device test** — it cannot be exercised in the Simulator, which has no iCloud account.

## 8. Architecture at a glance

Three schemes summarise how the app is put together: the layered structure, how a created task is routed between the two storage backends (the core of Rev. 8), and the CloudKit topology that makes a household shared.

### 8.1 Layered structure

<figure class="fig">
<svg viewBox="0 0 720 322" xmlns="http://www.w3.org/2000/svg" font-family="Helvetica Neue, Arial, sans-serif">
  <defs><marker id="aA" markerWidth="9" markerHeight="9" refX="6" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 Z" fill="#475569"/></marker></defs>
  <rect x="10" y="12" width="660" height="58" rx="6" fill="#eef2ff" stroke="#c7d2fe"/>
  <text x="24" y="36" font-size="11" font-weight="700" fill="#3730a3">VIEWS</text>
  <text x="24" y="54" font-size="11" font-weight="700" fill="#3730a3">SwiftUI</text>
  <text x="130" y="34" font-size="9.5" fill="#334155">RootTabView · TodayView · TaskListView · TodoListView · StatsView · AwardsView · SettingsView</text>
  <text x="130" y="52" font-size="9.5" fill="#334155">AddEditTaskView · TodoEditView · HouseholdsView · HouseholdDetailView · SharedTaskRow / SharedTodoRow</text>
  <rect x="10" y="78" width="660" height="40" rx="6" fill="#f5f3ff" stroke="#ddd6fe"/>
  <text x="24" y="102" font-size="11" font-weight="700" fill="#6d28d9">STATE</text>
  <text x="130" y="102" font-size="9.5" fill="#334155">HouseholdsModel (@Observable, in environment) · SocialAccount (@Observable) · @Query · @Environment(\.modelContext)</text>
  <rect x="10" y="126" width="660" height="58" rx="6" fill="#ecfeff" stroke="#a5f3fc"/>
  <text x="24" y="150" font-size="11" font-weight="700" fill="#0e7490">SERVICES</text>
  <text x="130" y="148" font-size="9.5" fill="#334155">SchedulingEngine · GamificationEngine · NotificationManager</text>
  <text x="130" y="166" font-size="9.5" fill="#334155">HouseholdService · SocialService → CloudKitSocialService · ProfileSync</text>
  <rect x="10" y="192" width="660" height="40" rx="6" fill="#f0fdf4" stroke="#bbf7d0"/>
  <text x="24" y="216" font-size="11" font-weight="700" fill="#15803d">MODELS</text>
  <text x="130" y="216" font-size="9.5" fill="#334155">SwiftData: TaskItem · TodoItem · Completion · FrequencyRule    |    CloudKit structs: SharedChore · SharedCompletion · SharedProfile</text>
  <rect x="10" y="240" width="660" height="58" rx="6" fill="#fff7ed" stroke="#fed7aa"/>
  <text x="24" y="264" font-size="11" font-weight="700" fill="#c2410c">CLOUD</text>
  <text x="24" y="282" font-size="11" font-weight="700" fill="#c2410c">&amp; STORE</text>
  <text x="130" y="262" font-size="9.5" fill="#334155">SwiftData store ⇄ CloudKit private DB mirror — same Apple ID, your devices only</text>
  <text x="130" y="280" font-size="9.5" fill="#334155">HouseholdService ⇄ CloudKit private custom zones + Shared DB, wrapped in CKShare — across users</text>
  <line x1="690" y1="20" x2="690" y2="292" stroke="#475569" stroke-width="1.4" marker-end="url(#aA)"/>
  <text x="700" y="160" font-size="8.5" fill="#475569" transform="rotate(90 700 160)" text-anchor="middle">depends downward</text>
</svg>
<figcaption>Models / Services / Views are cleanly separated; one <code>HouseholdsModel</code> in the environment is the single source of shared-household data for every tab. Two persistence paths sit at the bottom (see 8.2).</figcaption>
</figure>

### 8.2 Two storage backends — how a task is routed (Rev. 8)

<figure class="fig">
<svg viewBox="0 0 720 400" xmlns="http://www.w3.org/2000/svg" font-family="Helvetica Neue, Arial, sans-serif">
  <defs><marker id="aB" markerWidth="9" markerHeight="9" refX="6" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 Z" fill="#475569"/></marker></defs>
  <rect x="235" y="14" width="250" height="46" rx="6" fill="#eef2f7" stroke="#64748b"/>
  <text x="360" y="34" font-size="10" font-weight="700" fill="#0a2540" text-anchor="middle">Editor — AddEditTaskView · TodoEditView</text>
  <text x="360" y="50" font-size="9" fill="#475569" text-anchor="middle">Household: Private ▾    ·    Assignee ▾</text>
  <line x1="345" y1="60" x2="190" y2="100" stroke="#475569" stroke-width="1.4" marker-end="url(#aB)"/>
  <line x1="375" y1="60" x2="530" y2="100" stroke="#475569" stroke-width="1.4" marker-end="url(#aB)"/>
  <text x="225" y="82" font-size="9" font-weight="700" fill="#15803d">Private (default)</text>
  <text x="470" y="82" font-size="9" font-weight="700" fill="#0a66c2">Household selected</text>
  <rect x="60" y="100" width="250" height="38" rx="6" fill="#f8fafc" stroke="#cbd5e1"/>
  <text x="185" y="123" font-size="9.5" fill="#334155" text-anchor="middle">modelContext.insert / update</text>
  <line x1="185" y1="138" x2="185" y2="156" stroke="#475569" stroke-width="1.4" marker-end="url(#aB)"/>
  <rect x="60" y="156" width="250" height="44" rx="6" fill="#f0fdf4" stroke="#86efac"/>
  <text x="185" y="174" font-size="9.5" font-weight="700" fill="#15803d" text-anchor="middle">SwiftData store</text>
  <text x="185" y="190" font-size="9" fill="#334155" text-anchor="middle">TaskItem · TodoItem · Completion</text>
  <line x1="185" y1="200" x2="185" y2="218" stroke="#475569" stroke-width="1.4" marker-end="url(#aB)"/>
  <rect x="60" y="218" width="250" height="44" rx="6" fill="#eff6ff" stroke="#93c5fd"/>
  <text x="185" y="236" font-size="9.5" font-weight="700" fill="#0a66c2" text-anchor="middle">CloudKit private mirror</text>
  <text x="185" y="252" font-size="9" fill="#334155" text-anchor="middle">your devices only — not other people</text>
  <rect x="410" y="100" width="250" height="38" rx="6" fill="#f8fafc" stroke="#cbd5e1"/>
  <text x="535" y="123" font-size="9.5" fill="#334155" text-anchor="middle">HouseholdsModel.addChore (optimistic)</text>
  <line x1="535" y1="138" x2="535" y2="156" stroke="#475569" stroke-width="1.4" marker-end="url(#aB)"/>
  <rect x="410" y="156" width="250" height="44" rx="6" fill="#f8fafc" stroke="#cbd5e1"/>
  <text x="535" y="174" font-size="9.5" font-weight="700" fill="#334155" text-anchor="middle">HouseholdService</text>
  <text x="535" y="190" font-size="9" fill="#334155" text-anchor="middle">writes a CKRecord</text>
  <line x1="535" y1="200" x2="535" y2="218" stroke="#475569" stroke-width="1.4" marker-end="url(#aB)"/>
  <rect x="410" y="218" width="250" height="44" rx="6" fill="#eff6ff" stroke="#93c5fd"/>
  <text x="535" y="236" font-size="9.5" font-weight="700" fill="#0a66c2" text-anchor="middle">Household zone (CKShare)</text>
  <text x="535" y="252" font-size="9" fill="#334155" text-anchor="middle">SharedChore · SharedCompletion → every member</text>
  <path d="M150,262 C150,300 250,300 330,326" fill="none" stroke="#475569" stroke-width="1.4" marker-end="url(#aB)"/>
  <path d="M570,262 C570,300 470,300 390,326" fill="none" stroke="#475569" stroke-width="1.4" marker-end="url(#aB)"/>
  <text x="150" y="300" font-size="8.5" fill="#475569" text-anchor="middle">@Query</text>
  <text x="592" y="300" font-size="8.5" fill="#475569" text-anchor="middle">sharedTasks()</text>
  <rect x="170" y="330" width="380" height="52" rx="6" fill="#fffbeb" stroke="#f59e0b"/>
  <text x="360" y="351" font-size="10.5" font-weight="700" fill="#92400e" text-anchor="middle">Today · Tasks · To-Do lists</text>
  <text x="360" y="369" font-size="9" fill="#92400e" text-anchor="middle">private + shared rows merged at display time (no mirroring, no two-way sync)</text>
</svg>
<figcaption>The Household picker is a router. <strong>Private</strong> stores a local SwiftData object (mirrored only to your own devices). <strong>A household</strong> writes a <code>SharedChore</code> into the shared CloudKit zone. Both surface together in the normal lists; switching the picker on an existing item moves it across (and resets its completion history).</figcaption>
</figure>

### 8.3 Household sharing topology (CloudKit)

<figure class="fig">
<svg viewBox="0 0 720 286" xmlns="http://www.w3.org/2000/svg" font-family="Helvetica Neue, Arial, sans-serif">
  <defs><marker id="aC" markerWidth="9" markerHeight="9" refX="6" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 Z" fill="#475569"/></marker></defs>
  <rect x="18" y="16" width="300" height="210" rx="8" fill="#f8fafc" stroke="#94a3b8"/>
  <text x="168" y="36" font-size="10.5" font-weight="700" fill="#0a2540" text-anchor="middle">Owner — Private database</text>
  <rect x="38" y="48" width="260" height="162" rx="6" fill="#eff6ff" stroke="#93c5fd" stroke-dasharray="4 3"/>
  <text x="168" y="66" font-size="9" font-style="italic" fill="#0a66c2" text-anchor="middle">custom zone “household-&lt;uuid&gt;”</text>
  <rect x="54" y="76" width="228" height="38" rx="5" fill="#fff" stroke="#cbd5e1"/>
  <text x="168" y="92" font-size="9.5" font-weight="700" fill="#334155" text-anchor="middle">Household (root record)</text>
  <text x="168" y="106" font-size="8.5" fill="#059669" text-anchor="middle">+ CKShare (public permission: none)</text>
  <rect x="54" y="120" width="228" height="34" rx="5" fill="#fff" stroke="#cbd5e1"/>
  <text x="168" y="141" font-size="9.5" fill="#334155" text-anchor="middle">SharedChore × N (child records)</text>
  <rect x="54" y="160" width="228" height="34" rx="5" fill="#fff" stroke="#cbd5e1"/>
  <text x="168" y="181" font-size="9.5" fill="#334155" text-anchor="middle">SharedCompletion × N (child records)</text>
  <line x1="320" y1="120" x2="400" y2="120" stroke="#475569" stroke-width="1.6" marker-end="url(#aC)"/>
  <text x="360" y="108" font-size="8.5" fill="#475569" text-anchor="middle">CKShare</text>
  <text x="360" y="135" font-size="8.5" fill="#475569" text-anchor="middle">invite link /</text>
  <text x="360" y="146" font-size="8.5" fill="#475569" text-anchor="middle">from friends</text>
  <rect x="402" y="16" width="300" height="210" rx="8" fill="#f8fafc" stroke="#94a3b8"/>
  <text x="552" y="36" font-size="10.5" font-weight="700" fill="#0a2540" text-anchor="middle">Member — Shared database</text>
  <rect x="422" y="48" width="260" height="162" rx="6" fill="#f0fdf4" stroke="#86efac" stroke-dasharray="4 3"/>
  <text x="552" y="66" font-size="9" font-style="italic" fill="#15803d" text-anchor="middle">same zone, read-write</text>
  <rect x="438" y="84" width="228" height="46" rx="5" fill="#fff" stroke="#cbd5e1"/>
  <text x="552" y="104" font-size="9.5" font-weight="700" fill="#334155" text-anchor="middle">Household + its SharedChores</text>
  <text x="552" y="120" font-size="8.5" fill="#334155" text-anchor="middle">appear in this member's normal lists</text>
  <rect x="438" y="140" width="228" height="46" rx="5" fill="#fff" stroke="#cbd5e1"/>
  <text x="552" y="160" font-size="9.5" fill="#334155" text-anchor="middle">completing writes a SharedCompletion</text>
  <text x="552" y="176" font-size="8.5" fill="#334155" text-anchor="middle">(records who · which occurrence)</text>
  <rect x="18" y="240" width="684" height="34" rx="6" fill="#eef2ff" stroke="#c7d2fe"/>
  <text x="360" y="261" font-size="9.5" fill="#3730a3" text-anchor="middle">CKDatabaseSubscription on both databases → silent push on any change → HouseholdsModel.reload() refreshes every member</text>
</svg>
<figcaption>A household is a custom zone with a root <code>CKShare</code> in the owner's private database; chores and completions are child records, so they share as a unit. Invited members access the same zone through their <em>shared</em> database. The app reads zones with <code>CKFetchRecordZoneChangesOperation</code> and is woken by database subscriptions.</figcaption>
</figure>

<footer>
Habits & Chores — internal application review, Revision 9 · updated 15 June 2026. Severity tags (<span class="tag high">HIGH</span> <span class="tag med">MED</span> <span class="tag low">LOW</span> <span class="tag done">DONE</span>) reflect reviewer judgement, not formal risk scoring. App Store items reflect current Apple guidelines as understood at the time of writing; verify against the latest App Review Guidelines before submission.
</footer>
