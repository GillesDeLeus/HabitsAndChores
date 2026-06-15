# Privacy Policy

**Habits & Chores**
Last updated: 14 June 2026

Habits & Chores ("the app") is operated by Gilles De Leus ("we", "us"). This
policy explains what data the app handles and how. The app is designed to be
private by default: you can use it fully without creating an account, and in
that case your data stays in your own devices and iCloud account unless you
explicitly share a task with a household (see §3).

## 1. Data you create

- **Tasks, habits, chores, to-dos, and completions** you enter are stored
  locally on your device using Apple's SwiftData framework.
- If you are signed in to iCloud on your device, this data is automatically
  synced to **your own private iCloud account** via Apple CloudKit. It is stored
  in Apple's iCloud infrastructure and is **not accessible to us** — only to you,
  on your devices.
- Tasks you keep **Private** (the default) are never shared with anyone. If you
  choose to share a task with a **household**, that specific task becomes visible
  to the household's members — see §3.

## 2. Optional account and social features

These features are **opt-in**. If you never create an account, nothing in this
section applies and no data is shared.

If you choose **"Create an account"**:

- **Sign in with Apple** is used to authenticate you. We receive a stable,
  app-specific user identifier from Apple. If Apple provides a name, it is used
  only to suggest a display name. We do **not** receive your real Apple ID email
  unless Apple's relay forwards messages.
- A **public profile** is created in a shared (public) CloudKit database. It
  contains: your chosen **handle**, **display name**, **avatar** (either a photo
  you select or a character you build), and a **summary of your progress**
  (level, points, current/longest streak, and badge tiers). This profile is
  **readable by other signed-in users of the app** so that friends can find and
  view you.
- **Friend relationships** you create (requests, acceptances) are stored as
  records in the same public database.
- Your underlying habit/chore history is **never** published — only the derived
  summary above is shared.

## 3. Shared households

The app lets you create or join a **household** to share tasks with specific
people you choose (for example a partner or housemates). This uses Apple's
CloudKit **sharing** (CKShare) and is separate from the social features in §2.

- A household you create lives in **your private iCloud account**. When you
  invite someone — by share link, or (if you both use the social features)
  directly from your friends — Apple grants that person access to the shared
  household area.
- Inviting a friend in-app creates a small **invitation record** in the shared
  (public) database addressed to that friend, containing the household name, your
  display name, and the invitation link so they can accept inside the app. It is
  removed once they accept or decline.
- **A task you assign to a household is visible to every member of that
  household.** This includes its title, notes, icon, recurrence or due date, the
  member it is assigned to, and who marked it done. Tasks you keep Private are
  never shared.
- This data is shared **between members' iCloud accounts only**. It is still
  **not accessible to us**, and we do not operate any server in the middle.
- Member names shown inside a household come from each member's own iCloud or
  app display name.
- Leaving or deleting a household, or deleting a shared task, removes your
  access. Data already synced to other members remains available to them until
  they remove it.

## 4. Photos

If you choose a photo for your avatar, it is selected through Apple's system
photo picker. Only the single image you pick is used; it is resized to a small
thumbnail and stored with your public profile. The app does not access your
photo library beyond the image you explicitly select.

## 5. Notifications

- The app schedules **local reminder notifications** on your device for tasks
  with reminders, including reminders for shared household tasks you can see.
- If you use the social or household features, the app registers for **push
  notifications** via CloudKit so you can be notified of friend requests and of
  changes to a shared household. The push token is managed by Apple.

## 6. What we do NOT do

- We do **not** use analytics, advertising, or third-party tracking SDKs.
- We do **not** sell or share your data with advertisers or data brokers.
- We do **not** operate our own servers; all syncing and sharing uses Apple
  iCloud/CloudKit.

## 7. Data retention and deletion

- **Local data:** deleting the app removes the on-device data. Within the app,
  you can also remove your data.
- **Account / public profile:** choosing **"Leave & delete profile"** in
  Settings deletes your public profile and releases your handle. Friend records
  that other users created may persist on their side until they remove them.
- **Households:** deleting a household you own removes it for everyone; leaving a
  household you were invited to removes your copy. Shared tasks already synced to
  other members remain with them.
- **iCloud data:** your private iCloud data is controlled by you and can be
  managed or removed through your Apple iCloud settings.

## 8. Children

The app is not directed to children under 13 and does not knowingly collect
personal information from children.

## 9. Your rights

Depending on your jurisdiction (e.g., the EU/EEA under GDPR), you may have the
right to access, correct, export, or delete your personal data. Because social
and household data is stored in Apple CloudKit under your control and your public
profile can be deleted in-app, most of these actions are available directly to
you. For any other request, contact us using the details below.

## 10. Changes to this policy

We may update this policy as the app evolves. Material changes will be reflected
by updating the "Last updated" date above.

## 11. Contact

For privacy questions or requests, contact:
**gilles.de.leus@outlook.com**
