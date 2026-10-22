# Contributing

Thanks for helping! This project is shared within our class, so please keep changes small,
tested and kind.

## Getting started

1. Fork and clone, then follow [README](README.md#2-clone-and-try-the-demo-no-accounts-needed).
   Demo mode needs no accounts.
2. Install the pre-commit secret check:

   ```bash
   scripts/install-git-hooks.sh
   ```

3. Create a branch: `git switch -c feature/short-description`.

## Before opening a pull request

```bash
python3 scripts/secret-scan.py
```

```bash
cd tools/db-tests && npm ci && npm test && npm run test:edge
```

```bash
cd Packages/StudyKit && swift test
```

```bash
xcodebuild test -project WoodlandStudy.xcodeproj -scheme WoodlandStudy -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

CI runs the same checks.

## Where things go

* **Rules** (what counts as workload, how progress changes): `Packages/StudyKit/Sources/StudyDomain`,
  with tests. If the database enforces the same rule, change **both** and test both.
* **Database changes:** add a new file in `supabase/migrations/` (never edit one that's already
  merged), enable RLS, grant privileges explicitly, and add assertions in `supabase/tests/`.
* **Screens:** `WoodlandStudy/Features/…`. Student and admin screens stay in separate folders.
  Use `Palette`, `Font.lora` and the shared components so Dark Mode and Dynamic Type keep working.
* **Text:** every user-facing string must be localizable. After adding strings, build once,
  then run `python3 scripts/update-string-catalog.py <derived-data-path>` and add the Hebrew
  translation to `scripts/localization/he.json`. Use leading/trailing (not left/right) so
  right-to-left layout works.

## Accessibility checklist

* Works with the largest Dynamic Type size and with VoiceOver (meaningful labels, no
  information conveyed by color alone).
* Readable in light and dark mode.
* Tap targets at least 44×44 pt.

## Content and data

* Use **synthetic** data only (`example.test` addresses, made-up lessons).
* Don't commit course PDFs or other copyrighted material without written permission.
* Never commit real student data, database dumps or exports.

## Code style

Follow the surrounding code: Swift 6 strict concurrency, `@Observable` stores, small views,
comments that explain *why*. SQL: lowercase keywords, `set search_path = ''` on every function.

By contributing you agree your contribution is licensed under the MIT License.
