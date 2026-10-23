# TestFlight upload guide (Homework Progress)

Project: `Homework progress.xcodeproj` · scheme **Homework progress** · Release ·
bundle ID `AnnaLoseva.Homework-progress` · team `K36SNFAJDS` · version 1.0.

## Already done on this Mac (2026-10-23)

- A signed Release archive builds: `build/HomeworkProgress-1.0-11.xcarchive`.
- It exports for App Store Connect: `build/export-11/Homework progress.ipa`, signed by
  *Apple Distribution: Anna Loseva* with an App Store profile, `aps-environment=production`,
  CloudKit **Production**, no `get-task-allow`. **Nothing has been uploaded.**
- Archives fail on purpose if `Config/Local.xcconfig` has no backend, a local/HTTP one, a
  placeholder or a secret key (`scripts/check-release-config.sh`).

## 1. One-time setup (you, in the browser)

1. **CloudKit production schema — done on 2026-10-23.** TestFlight builds use
   CloudKit's *Production* environment, which starts empty. Without the schema, iPhone ↔ iPad
   sync silently stays local.
   1. Run the app from Xcode on your device once with a week, an assignment and a PDF, so
      the development schema has every record type.
   2. [CloudKit Console](https://icloud.developer.apple.com) → container
      `iCloud.AnnaLoseva.Homework-progress` → **Schema → Deploy Schema Changes…** → Deploy to
      Production.
   3. Do this again whenever a SwiftData model changes.
2. **App record.** [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+** →
   New App: platform iOS, name (see [RELEASE_METADATA.md](RELEASE_METADATA.md)), primary
   language English, bundle ID `AnnaLoseva.Homework-progress`, SKU e.g. `homework-progress`,
   User Access: Full. (If the bundle ID isn't in the list, open the project in Xcode once
   with automatic signing, or add it under Certificates, Identifiers & Profiles → Identifiers.)
3. **Class backend.** In the Supabase project the build uses
   (the one in `Config/Local.xcconfig`): set a class code (app → Class → Manage lessons → Class code) and
   check that the lessons you want testers to see are *published*. This project is your
   class's live backend from now on — treat it as production (see
   [SECURITY_REVIEW.md](SECURITY_REVIEW.md)).
4. **Privacy policy URL.** Fill in [PRIVACY.md](../../PRIVACY.md) and publish it somewhere
   public. External testing needs the URL.

## 2. Archive and upload

### Option A — Xcode (simplest)

1. Open `Homework progress.xcodeproj`. In the toolbar choose scheme **Homework progress** and
   destination **Any iOS Device (arm64)**.
2. **Product → Archive.** The Organizer opens when it finishes.
3. Select the archive → **Distribute App** → **TestFlight & App Store** → Distribute.
   Keep *Upload your app's symbols* and *Manage Version and Build Number* ticked (Xcode
   then raises the build number if it was already used).
4. Wait for "Upload Successful".

### Option B — Terminal

```bash
scripts/testflight.sh check
```

```bash
scripts/testflight.sh upload
```

`upload` archives with build number = commit count on `HEAD` (or `--build N`), exports with
your Xcode account's signing and uploads. Use `export` instead of `upload` to only make the
`.ipa`. Don't mix options A and B for the same version unless the build number keeps
increasing.

### Option C — Xcode Cloud

Xcode Cloud builds from the GitHub repository, where `Config/Local.xcconfig` doesn't exist.
`ci_scripts/ci_post_clone.sh` writes it from the workflow's environment variables; without
them the archive stops with an error instead of shipping a Class tab that can't connect.

1. Commit and push `ci_scripts/`, the shared scheme
   (`Homework progress.xcodeproj/xcshareddata/xcschemes/`) and
   `xcshareddata/xcodecloud/manifest.json`.
2. App Store Connect → your app → **Xcode Cloud → Manage Workflows** → your workflow →
   **Environment**. In Xcode: Report navigator → Cloud → right-click the product → *Manage
   Workflows…*. Under **Environment Variables** add:

   | Name | Value | Secret |
   |---|---|---|
   | `SUPABASE_URL` | `https://<project-ref>.supabase.co` — the same URL as in your `Config/Local.xcconfig` | optional |
   | `SUPABASE_PUBLISHABLE_KEY` | the `sb_publishable_…` key from your `Config/Local.xcconfig` (Supabase → Project Settings → API Keys). **Never** the secret / service-role key. | tick it, so it's hidden in logs |

   For a homework-only build, set `ALLOW_ARCHIVE_WITHOUT_CLASS_BACKEND` = `YES` instead.
3. In the same workflow: **Actions → Archive** (platform iOS, *TestFlight (Internal and
   External Testing)*), and under **Post-Actions → TestFlight External Testing** pick your
   group if you want builds to go to classmates automatically.
4. **Build numbers:** Xcode Cloud sets its own increasing build number. If you already
   uploaded a higher one from the Mac (e.g. 11), raise Xcode Cloud's next build number in
   the product's Settings → Build Number, or App Store Connect will reject the upload.
5. Start a build (Xcode → Product → Xcode Cloud → Start Build). The log of the
   `ci_post_clone.sh` step should say "Wrote Config/Local.xcconfig for <ref>.supabase.co".

## 3. After the upload

1. App Store Connect → your app → **TestFlight**. The build shows *Processing* for
   5–30 minutes; you get an email when it's ready.
2. **Export compliance** is already answered by `ITSAppUsesNonExemptEncryption = NO`, so no
   question should appear. If it does, answer that the app uses only exempt (standard HTTPS)
   encryption.
3. **Test Information** (TestFlight → Test Information): beta description, feedback email,
   privacy policy URL, and for Beta App Review the sign-in notes — all drafted in
   [RELEASE_METADATA.md](RELEASE_METADATA.md).

## 4. Testers

| | Internal testers | External testers |
|---|---|---|
| Who | People added as users of **your** App Store Connect team (up to 100) | Anyone with an email invite or the public link (up to 10,000) |
| Review | None — available as soon as processing finishes | The **first build of each version** goes through *Beta App Review* (usually under a day, can be longer); later builds of that version often don't |
| For classmates? | Only if you add them to your team, which also gives them access to App Store Connect | **Yes — use this** |

**Classmates via a public link:**

1. TestFlight → **External Testing → +** → create a group, e.g. "HIT class".
2. Add the build to the group → **Submit for Review** (fill in the review notes).
3. When approved: group → **Public Link → Enable**, optionally set a tester limit, copy the
   link.
4. Share the link and the class code. Classmates install **TestFlight** from the App Store,
   open the link and tap *Install*. Builds expire after 90 days.

Test it yourself first as an internal tester (add your own Apple ID under Internal Testing).

## 5. Next builds

1. Commit your changes (the default build number comes from the commit count).
2. Bump `MARKETING_VERSION` (target → General → Version) only for a new version, e.g. 1.1;
   new builds of 1.0 just need a higher build number.
3. Archive and upload as in step 2, then add the build to the external group. Write
   "What to Test" for each build.
4. If the SwiftData models changed: redeploy the CloudKit schema (step 1.1) **before**
   testers update. If the database changed: run `npx supabase db push` and the SQL tests first.

## Not part of this

Publishing on the public App Store (needs screenshots, full App Review, support URL and the
privacy label) — see [RELEASE_METADATA.md](RELEASE_METADATA.md).
