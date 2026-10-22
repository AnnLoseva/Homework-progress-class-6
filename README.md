# Woodland Study Tracker 🍄

A cozy, native **iPhone and iPad** app for a university class. The instructor publishes
lessons and PDFs. Each student signs in with Apple, follows the lessons they need, and tracks
their own progress privately, across all their devices.

<p align="center">
  <img src="docs/screenshots/ipad-home.png" width="32%" alt="iPad home dashboard with workload, study next and deadlines">
  <img src="docs/screenshots/ipad-lesson.png" width="32%" alt="iPad lesson screen with progress controls and PDF materials">
  <img src="docs/screenshots/iphone-home-hebrew-dark.png" width="22%" alt="iPhone home in Hebrew, right-to-left, dark mode">
</p>

* **Students:** a dashboard (what to study, what's required, what's done, what's left),
  a catalog with **Required (חובה)** and **Optional (רשות)** lessons, "My Lessons" for
  subscriptions, exercise counters, private notes, PDFs that work offline, and a share sheet
  to send them to Notability and other apps.
* **Administrator:** create, edit, publish, unpublish and archive lessons; upload, preview
  and replace PDFs; manage courses; set the class join code. All from inside the app.
* **Backend:** Supabase (Postgres + Row Level Security, Auth with Sign in with Apple, private
  Storage, one Edge Function). Every security rule is enforced in the database and covered by
  SQL tests.
* **Privacy:** no email or name stored, no analytics or trackers. Students can export or
  delete their data at any time.

Architecture, data model and security model: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

---

## Contents

1. [Required tools](#1-required-tools)
2. [Clone and try the demo](#2-clone-and-try-the-demo-no-accounts-needed)
3. [Create a Supabase project (or run it locally)](#3-create-a-supabase-project-or-run-it-locally)
4. [Configure Sign in with Apple](#4-configure-sign-in-with-apple)
5. [Configure Supabase Auth](#5-configure-supabase-auth)
6. [Apply the database migrations](#6-apply-the-database-migrations)
7. [Configure the app](#7-configure-the-app)
8. [Run the app](#8-run-the-app)
9. [Run the tests](#9-run-the-tests)
10. [Create the first administrator](#10-create-the-first-administrator-securely)
11. [Upload and publish lessons](#11-upload-and-publish-lessons)
12. [Prepare a release build](#12-prepare-a-release-build)
13. [Project layout](#project-layout) · [Behavior notes](#behavior-notes) · [Limitations](#known-limitations) · [License](#license)

---

## 1. Required tools

| Tool | Version | Needed for |
|---|---|---|
| macOS + **Xcode** | Xcode 26 or newer (tested with Xcode 27, Swift 6.4) | Building the app |
| iOS / iPadOS | 17.0 or newer | Running the app |
| **Node.js** | 20+ (tested with 22) | Database tests (`tools/db-tests`), Supabase CLI via `npx` |
| Python 3 | 3.9+ (preinstalled on macOS) | Secret scan, string catalog script |
| Supabase account | free tier is enough | The real backend |
| **Apple Developer Program** | paid membership | Sign in with Apple on real devices, TestFlight |
| Docker Desktop | optional | A full local Supabase stack (`npx supabase start`) |

Without a Supabase project or an Apple Developer membership you can still run the
**demo mode** and every automated test.

## 2. Clone and try the demo (no accounts needed)

```bash
git clone https://github.com/<your-account>/woodland-study-tracker.git
```

```bash
cd woodland-study-tracker && open WoodlandStudy.xcodeproj
```

Choose an iPhone or iPad simulator and press **Run**. Without a Supabase configuration the app
starts in **demo mode**: tap **Explore the demo** to use synthetic lessons that live only in
memory. To try the administrator screens, edit the scheme (**Product → Scheme → Edit Scheme →
Run → Arguments**) and enable `-demoAdmin`.

## 3. Create a Supabase project (or run it locally)

**Hosted (recommended for the class):**

1. Sign in at [supabase.com](https://supabase.com) and create a **new project** just for this
   app. Pick a region close to your class, and store the database password in a password
   manager. Don't reuse a project that holds other data.
2. Note the **Project URL** and the **Publishable key** (Project Settings → API Keys).
   The *secret* / *service_role* key stays in the dashboard. It never goes in the app, in
   this repository, or in chat.

**Local (Docker):** `npx supabase start` runs Postgres, Auth and Storage on your Mac, applies
`supabase/migrations`, and loads `supabase/seed.sql`. `npx supabase status` prints the
local URL and keys. Reset it any time with `npx supabase db reset`.

## 4. Configure Sign in with Apple

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list),
   create an **App ID** with your own bundle identifier (e.g. `com.yourname.woodland-study`)
   and enable **Sign in with Apple**. Xcode's automatic signing can do this when you add your team.
2. *(Recommended, for account deletion)* Under **Keys**, create a key with **Sign in with Apple**
   enabled and download the `.p8` file. Keep it out of the repository (`*.p8` is
   git-ignored). The `delete-account` Edge Function uses it to revoke the user's Apple
   authorization when they delete their account.

The app asks Apple for **no** name and **no** email: the stable Supabase user id is the only
identity.

## 5. Configure Supabase Auth

In the Supabase dashboard:

1. **Authentication → Sign In / Providers → Apple:** enable it. In **Client IDs**, enter your
   bundle identifier (e.g. `com.yourname.woodland-study`). The native iOS flow doesn't need
   the "Secret Key (for OAuth)" field.
2. **Email** provider: turn it **off** (or at least turn off sign-ups). Students only use Apple.
3. Keep **Anonymous sign-ins** off and **Allow new users to sign up** on (Apple creates the
   user on first sign-in).

For the local stack, set the same values in `.env` (copy `.env.example`); `supabase/config.toml`
reads them.

## 6. Apply the database migrations

The schema, RLS policies, storage buckets and functions are in `supabase/migrations`.

```bash
npx supabase login
```

```bash
npx supabase link --project-ref <your-project-ref>
```

```bash
npx supabase db push
```

`db push` applies only migrations the project doesn't have yet. Don't load `seed.sql` into a
production project. It's synthetic sample data for development (`npx supabase db reset`
loads it locally).

Then deploy the account-deletion function and (optionally) its Apple secrets:

```bash
npx supabase functions deploy delete-account --no-verify-jwt
```

```bash
npx supabase secrets set --env-file supabase/functions/.env
```

Put only the four `APPLE_*` values from `.env.example` in `supabase/functions/.env` (git-ignored).
`--no-verify-jwt` is intentional: the function verifies the caller's token itself with
`supabase.auth.getUser`.

## 7. Configure the app

```bash
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

Edit `Config/Local.xcconfig` (it's git-ignored):

```
APP_BUNDLE_ID = com.yourname.woodland-study
DEVELOPMENT_TEAM = ABCDE12345
SUPABASE_URL = https:/$()/your-project-ref.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_…
```

The `$()` keeps xcconfig from reading `//` as a comment. If you paste a secret key by
mistake, the app refuses to start against Supabase and tells you to rotate the key.

## 8. Run the app

Open `WoodlandStudy.xcodeproj`, select the **WoodlandStudy** scheme and a device or simulator,
and press **Run**. Sign in with Apple works in the simulator if it's signed in to an Apple ID.
On a real device you need your team set in `Local.xcconfig`.

## 9. Run the tests

| What | Command | Proves |
|---|---|---|
| **Database security (RLS)** | `cd tools/db-tests && npm ci && npm test` | 172 assertions in 9 suites: student isolation, role escalation, drafts, storage access, enrollment, progress rules, account deletion. Runs migrations on **PGlite** (real Postgres 17 in WebAssembly) with a small `auth`/`storage` shim. No Docker needed. |
| …against a real local Supabase | `npm test -- --database-url postgresql://postgres:postgres@127.0.0.1:54322/postgres` | The same suites on the real Supabase stack (`npx supabase start` first). Refuses hosted URLs. |
| Edge Function helpers | `cd tools/db-tests && npm run test:edge` | Apple client-secret signing and revocation flow |
| Domain + sync logic | `cd Packages/StudyKit && swift test` | 101 tests: workload, progress rules, dashboard math, offline outbox, retries, two-device sync, auth state, attachments, Supabase row mapping |
| Everything on a simulator | `xcodebuild test -project WoodlandStudy.xcodeproj -scheme WoodlandStudy -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` | Package tests, app tests and UI tests (iPhone; use an iPad destination for the split view) |
| Secret scan | `python3 scripts/secret-scan.py` | No keys, tokens, `.env` files or dumps in files or history |

The UI tests run in demo mode and show that the screens work. They are **not** evidence
of backend security; the SQL suites are.

## 10. Create the first administrator (securely)

Nobody can make themselves an administrator from the app. The `administrator_roles` table
has no write policy, and `private.grant_admin` can't be called by app users.

1. Run the app with your Supabase configuration and **sign in with Apple once**.
2. In the Supabase dashboard, open **Authentication → Users** and copy your **User UID**
   (it's a UUID; the email column may show an Apple private-relay address).
3. Open **SQL Editor** and run:

   ```sql
   select private.grant_admin('00000000-0000-0000-0000-000000000000', 'Course instructor');
   ```

4. Pull to refresh (or relaunch) the app. A **Manage** tab (iPhone) or **Manage lessons**
   sidebar item (iPad) appears.

To remove a role: `select private.revoke_admin('<uuid>');`.

## 11. Upload and publish lessons

1. **Manage → Class code:** set a code (at least 8 characters, or tap **Suggest a code**) and
   share it with the class. Students enter it in **Settings → Join your class** to unlock
   materials marked *Class members*. Only a salted hash is stored, so write the code down.
2. **Manage → Courses:** add your courses (title, Hebrew subtitle, illustration, color).
3. **Manage → +:** create a lesson (title, course, **Required/Optional**, week, dates,
   exercise count, prerequisites) and **Save**. It starts as a **draft**, invisible to students.
4. **Add PDF:** choose a file, check the preview, set *Class members* or *Anyone*, and
   **Upload**. **Replace PDF** later keeps the same attachment and never touches progress.
5. **Publish.** Later you can **Unpublish** (back to draft) or **Archive**. Lessons that
   students have worked on can't be deleted, only archived.

More detail: [docs/ADMIN_GUIDE.md](docs/ADMIN_GUIDE.md).

## 12. Prepare a release build

1. Set `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` (target build settings).
2. Run `python3 scripts/secret-scan.py` and all tests.
3. **Product → Archive** in Xcode, then **Distribute App → App Store Connect** to upload to
   TestFlight.
4. Before an App Store submission, fill in the App Privacy questionnaire (see
   [PRIVACY.md](PRIVACY.md); the bundled `PrivacyInfo.xcprivacy` declares *User ID* and
   *Other User Content*, not used for tracking) and publish a privacy policy URL.

Open source vs. development build vs. TestFlight vs. App Store, and what MIT means for you:
**[docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)**.

---

## Project layout

```
WoodlandStudy/                 iOS/iPadOS app (SwiftUI)
  App/                         entry point, dependency wiring, Sign in with Apple helpers
  DesignSystem/                woodland palette (light + dark), Lora type, shared components
  Features/Auth|Root|Home|Catalog|Lesson|MyLessons|Settings   student screens
  Features/Admin/              content management (separate from student screens)
  Resources/                   assets, fonts (OFL), Localizable.xcstrings (en + he), privacy manifest
Packages/StudyKit/             Swift package below the UI
  StudyDomain/                 pure models & rules (workload, progress, dashboard, filters)
  StudyData/                   protocols, offline cache, outbox & sync, PDF cache, demo backend
  StudySupabase/               Supabase implementation (supabase-swift)
supabase/
  migrations/                  schema, RLS, storage policies, API functions
  functions/delete-account/    the only code that uses the service-role key
  tests/                       SQL security suites
  seed.sql                     synthetic development data
tools/db-tests/                runs the SQL suites on PGlite or a local database
scripts/                       secret scan, string catalog generator, git hooks
Config/                        Base.xcconfig, Local.example.xcconfig, Info.plist, entitlements
docs/                          architecture, admin guide, distribution, assets, screenshots
```

## Behavior notes

* **Required lessons** are always in every student's workload and can't be toggled off.
  **Optional lessons** count only after the student subscribes.
* **Unsubscribing never deletes progress**; subscribing again restores it.
* **Category changes:** optional → required adds the lesson to everyone's workload.
  required → optional keeps it for students who already started (they're auto-subscribed).
  Progress is never touched.
* **Archived lessons** leave the workload but stay in **My Lessons → History** with the
  student's progress.
* **Progress sync:** changes apply at once on the device, queue offline, and sync with
  last-writer-wins by device time. An old offline edit never overwrites a newer one from
  another device.
* **Dashboard:** lesson completion (completed ÷ workload) and exercise completion
  (Σ done ÷ Σ total, weighted) are separate numbers.
* **No iCloud sync:** Supabase is the single source of truth, so there's no second copy that
  could conflict.

## Known limitations

* **Notability** has no public import API, so PDFs go through the standard share sheet
  ("Open in Notability"). The app can't choose a notebook.
* The SQL suites ran here on **PGlite** with a minimal Supabase shim. Run them against
  `npx supabase start` (Docker) before relying on a new deployment; storage-API behaviors
  such as signed-URL issuance are exercised there, not in PGlite.
* The **Edge Function**'s Apple-revocation helper is unit-tested with Node. The function
  itself runs on Deno and still needs an end-to-end test on a deployed or local Supabase.
* Sign in with Apple on real devices and TestFlight need a **paid Apple Developer** account.
* The `student-private` bucket and its policies exist and are tested, but no screen uploads
  student files yet.

## License

Code: **MIT** (see [LICENSE](LICENSE) and [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md#the-mit-license-in-plain-words)).
Lora font: SIL Open Font License 1.1. Illustrations: see [docs/ASSETS.md](docs/ASSETS.md).

Contributing: [CONTRIBUTING.md](CONTRIBUTING.md) · Security: [SECURITY.md](SECURITY.md) ·
Privacy: [PRIVACY.md](PRIVACY.md)
