# Distribution: GitHub Releases, Obtainium, and F-Droid

Blushcraft ships APKs from GitHub when you push a `v*` tag (see `.github/workflows/create_release.yml`). This document explains how that relates to **Obtainium** and **F-Droid**.

## GitHub Releases (current setup)

- Tag format: `v0.2.0` (must match `v*` for the workflow).
- Artifacts: `app-debug.apk` and signed `app-release.apk`.
- Versioning: `versionName` from the tag; `versionCode` from `git rev-list --count HEAD` (see `tool/git_version.sh`).
- Release notes are generated from git history via `.github/scripts/generate-release-notes.sh`.

This is the source of truth for prebuilt binaries.

## Screenshots for listings

README embeds the animated demo (`docs/screenshots/round-demo.gif` / `.mp4`).

Static stills for Obtainium, F-Droid, or other profiles are generated from that video:

```bash
./tool/extract_store_screenshots.sh
# → docs/screenshots/store/01-home.png … 07-result.png
```

Keep a curated `store/01-home.png` if you want a sharper home still than the early demo frame.

## Signing (maintainers)

Same secret names as BumpDesk:

| Secret | Purpose |
|--------|---------|
| `SIGNING_KEY` | Base64 of `keystore/blushcraft-release.jks` (`base64 -w0 …`) |
| `SIGNING_STORE_PASSWORD` | Keystore password |
| `SIGNING_KEY_ALIAS` | Usually `blushcraft` |
| `SIGNING_KEY_PASSWORD` | Key password |

Local signed builds: copy `keystore.properties.example` → `keystore.properties`, generate the `.jks` under `keystore/`, then `./tool/build_apk.sh`.

## Obtainium (recommended for testers)

**Obtainium is not a store.** There is nothing to “submit.” Users install [Obtainium](https://github.com/ImranR98/Obtainium) and add your repo as an update source.

**Pros**

- Works with your existing GitHub Releases workflow immediately.
- Users get update notifications when you push new tags.
- No review queue, no separate build pipeline.

**Cons**

- Users must enable “Install unknown apps” / sideloading.
- APKs are signed with **your** release key, not F-Droid’s.
- You maintain release hygiene (changelog, asset names, tag discipline).

**Typical config**

| Field | Value |
|-------|--------|
| Source | GitHub |
| Repo | `electrikjesus/Blushcraft` |
| Release filter | `v*` tags |
| APK filter | `app-release.apk` (or `app-debug.apk` for debug builds) |

Share the Obtainium import link or these values in release notes so testers can one-tap subscribe.

## F-Droid (separate onboarding project)

**F-Droid is not triggered by your GitHub release workflow.** Inclusion is a **one-time merge request** to the [fdroiddata](https://gitlab.com/fdroid/fdroiddata) repository, plus ongoing metadata maintenance.

**What F-Droid does**

- Clones **source** from your public repo.
- Builds the APK on F-Droid infrastructure.
- Signs with an **F-Droid-specific** key (different fingerprint from GitHub release APKs).
- Publishes to [f-droid.org](https://f-droid.org) after review.

Treat F-Droid as a later milestone once the app is stable and policy-clean.

## Suggested channels

| Audience | Channel |
|----------|---------|
| Developers & early testers | GitHub Releases + Obtainium |
| Broader FOSS audience | F-Droid (later) |
| Play Store | Out of scope for this repo’s current workflow |
