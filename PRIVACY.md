# Privacy Policy (template)

> **This is a template.** Whoever operates a deployment of Woodland Study Tracker (the
> "operator", e.g. the course instructor) must fill in the bracketed parts, check them against
> their actual setup, and publish the result before inviting users. It is not legal advice,
> and the project makes no claim of compliance with any specific law (GDPR, Israeli Privacy
> Protection Law, etc.). Ask your institution if you're unsure.

**Last updated:** [date]
**Operator:** [name, course, institution] · **Contact:** [email for privacy requests]

## What we store and why

| Data | Why | Where |
|---|---|---|
| A stable account identifier created when you sign in with Apple | To keep your data separate from everyone else's and sync it across your devices | Supabase (hosted in [region]) |
| Information Apple provides when you sign in. The app requests **no** name and **no** email; Apple's token may still include an email or a private-relay address, which Supabase Auth keeps on your account record | Required by the sign-in service | Supabase Auth |
| Which optional lessons you follow | To build your workload | Supabase |
| Your progress: lesson status, exercise counts, timestamps | To track your progress | Supabase |
| Your private notes | So you can keep notes per lesson | Supabase |
| Whether you joined the class with its code | To unlock class-only materials | Supabase |
| An optional display name (not used yet) | Reserved for future features | Supabase |
| A cache of lessons, your progress and downloaded PDFs; recently opened lessons | So the app opens fast and works offline | Your device only |

We **don't** collect advertising identifiers, location, contacts, device analytics or crash
analytics, and we **don't** use tracking SDKs. We **never sell** your data.

## Who can see your data

* **You.** Database rules (Row Level Security) let each account read and change only its own
  subscriptions, progress and notes.
* **Not other students. Not the instructor.** The administrator role has no access to
  students' progress or notes through the app or the API.
* **Service providers:** Supabase (database, authentication, file storage) and Apple (Sign in
  with Apple) process data on the operator's behalf. People with administrative access to the
  operator's Supabase project could technically access the database. [Describe who has that
  access, e.g. "only the instructor".]

## How long we keep it

Your data is kept while your account exists. [Optional: "Accounts inactive for more than
N months after the course ends are deleted."] Supabase may keep backups for a limited period
under its own retention policy ([link]).

## Your choices and rights

* **Export:** Settings → Export my data gives you a JSON file with everything stored about you.
* **Delete:** Settings → Delete account and data permanently deletes your account,
  subscriptions, progress and notes from the server, and removes cached data from your device.
  The app also asks Apple to revoke its sign-in authorization.
* **Sign out:** removes cached data from the device; your data stays in your account.
* For other requests (correction, questions), contact [email].

## Children

The app is intended for university students and is not directed to children under [13/16].

## Changes

We'll update this page and the "Last updated" date when the policy changes.
