# Security

## Reporting a vulnerability

Please **don't open a public issue** for security problems. Use GitHub's
**Security → Report a vulnerability** (private vulnerability reporting) on this repository,
or contact the maintainer privately. Include steps to reproduce and what an attacker could
access. You'll get an acknowledgement within a week.

This is a student project. It has **not** been independently audited, and no compliance
certification is claimed.

## Security model in short

* **Postgres is the security boundary.** RLS is enabled on every table; privileges are granted
  explicitly per role; validation lives in `BEFORE` triggers. The app's own checks are only
  for convenience. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#security-model).
* **Identity comes from the JWT.** No API accepts a user id from the client. `created_by`,
  `uploaded_by` and progress ownership are set server-side.
* **Students are isolated.** Each student can read and write only their own subscriptions,
  progress and notes. Administrators have **no** policy on students' personal tables.
* **Roles can't be self-assigned.** `administrator_roles` has no client write policy;
  `private.grant_admin` is executable only by the SQL editor or service role.
* **Files:** both buckets are private. Lesson files are readable only if the matching
  attachment row says so (published lesson; public, or restricted + enrolled). Old versions
  and draft files are unreadable even with the exact path.
* **Secrets:** the app ships only the publishable key and refuses to run with a secret key.
  The service-role key exists only inside the `delete-account` Edge Function.
* **Class code:** stored as a salted SHA-256 hash; at most 10 failed attempts per hour per user.

These guarantees are tested in `supabase/tests/*.sql`, which run in CI.

## Rules for contributors

* Never commit `.env`, `Config/Local.xcconfig`, `.p8`/`.p12` files, provisioning profiles,
  database dumps, data exports, or real student data. They're git-ignored. Install the
  pre-commit hook with `scripts/install-git-hooks.sh`.
* Never disable RLS, add `using (true)` to a personal table, or grant `anon` write access.
  New tables need RLS, explicit grants and SQL tests in the same pull request.
* Never use the service-role key in the app, in tests that touch a hosted project, or in CI.
* `SECURITY DEFINER` functions must `set search_path = ''`, check the caller, and be
  revoked from `public`/`anon`. `01_schema_security.sql` checks this.

## If a secret leaks

1. **Rotate it first** (Supabase → Project Settings → API Keys / JWT keys; Apple → revoke the
   key; GitHub → revoke the token). Deleting the commit isn't enough: assume it was copied.
2. Remove it from history (`git filter-repo` or GitHub's guide on removing sensitive data),
   force-push, and ask collaborators to re-clone.
3. Check Supabase logs for misuse.

## Repository settings to enable (on GitHub)

* **Settings → Code security:** Secret scanning **and push protection**, Dependabot alerts,
  private vulnerability reporting.
* **Settings → Branches → Branch protection for `main`:** require a pull request, require
  the CI checks (`secret-scan`, `database`, `swift`) to pass, block force pushes and deletions.
* **Settings → Collaborators:** classmates who contribute get *Write* (or fork); only the
  maintainer keeps *Admin*.
* Keep production configuration (project ref, keys, Apple key, team id) out of the
  repository, in Supabase/Apple dashboards and your local git-ignored files.
