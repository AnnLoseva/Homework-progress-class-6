# Distribution: open source, builds, TestFlight and the App Store

Publishing this repository on GitHub makes the **code** public. It does **not** put the app on
anyone's phone, and it does **not** put it on the App Store. These are four different things:

| | What it is | Who can install | What you need |
|---|---|---|---|
| **Open-source repository** | The source code, docs and migrations on GitHub | Nobody "installs" it; people read, fork and build it | A GitHub account |
| **Development build** | Built and run from Xcode onto a connected device | Only devices you plug in (or register) | Xcode. A free Apple ID can run the homework tracker for 7 days; **Sign in with Apple (the Class tab) and iCloud sync need a paid membership** |
| **TestFlight** | A beta uploaded to App Store Connect | Up to 100 internal testers, or up to 10,000 external testers by email or public link, after a short beta review. Builds expire after 90 days | Paid Apple Developer Program, an App Store Connect record, an archive upload |
| **App Store** | The public listing | Anyone in the chosen regions | Full App Review, privacy "nutrition label", privacy policy URL, support URL, screenshots, account deletion in the app (already implemented) |

**For a class, TestFlight is usually the right choice:** the instructor (with a paid
account) uploads a build and shares a public TestFlight link. Classmates install the
TestFlight app and join; no one needs Xcode. The build points at the instructor's Supabase
project through the publishable key, which is safe because RLS protects the data.

How to actually upload the beta: [release/TESTFLIGHT_UPLOAD_GUIDE.md](release/TESTFLIGHT_UPLOAD_GUIDE.md).

A classmate who builds from source with their own Apple team and bundle id gets **their own
app**. To use the class's backend, the instructor must add that bundle id to the Apple
provider's *Client IDs* in Supabase. Otherwise they can use the homework tracker alone, or
connect their own Supabase project. They also need their own iCloud container identifier
(see the README).

## The MIT License in plain words

* Anyone may use, copy, modify, publish, distribute, sublicense and even **sell** copies or
  derivatives of the code, including in closed-source products.
* The one condition: keep the copyright notice and license text in copies.
* There's **no warranty** and no liability: if it breaks, the authors aren't responsible.
* It covers **only the code** in this repository. It does not grant rights to:
  * the **Lora font** (SIL OFL 1.1: free to bundle, can't be sold on its own);
  * the **illustrations and app icon** (see [ASSETS.md](ASSETS.md); confirm you may
    publish them before making the repository public);
  * your **Supabase project**, its data, or your Apple developer identity;
  * **course materials** you upload through the app (they stay in your private storage,
    under your institution's or authors' terms, and never belong in this repository).
* Once something is published under MIT, you can't revoke that license for the copies people
  already have. Choose before you publish. Alternatives: Apache-2.0 (adds an explicit patent
  grant), GPL-3.0 (derivatives must stay open source), or "All rights reserved" (source
  visible but not reusable).
* Contributions are accepted under the same MIT License (see CONTRIBUTING.md).

## Publishing checklist

1. `python3 scripts/secret-scan.py` passes (tracked files **and** full history).
2. `git status` shows no `Config/Local.xcconfig`, `.env`, `.p8` or exports.
3. `docs/ASSETS.md` confirms you hold the rights to every illustration.
4. CI is green.
5. Create the GitHub repository (public), push, then enable the settings listed in
   [SECURITY.md](../SECURITY.md#repository-settings-to-enable-on-github).
