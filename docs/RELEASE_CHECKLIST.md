# Klasify Release Checklist

Runbook for taking a build from this repo to the stores. The README explains
*how* things work; this file is the ordered *do*. Check items off as you go.

Already handled in this repo (do not redo):
- `targetSdk` / `compileSdk` pinned to **36+** in `android/app/build.gradle.kts`
- `useLegacyPackaging = false` pinned for 16 KB page-size support
- Opt-in crash reporting wired behind `--dart-define=KLASIFY_SENTRY_DSN`
- Privacy policy written at `docs/privacy-policy.html`
- 16 KB verifier available at `tool/check_16kb.py`

## 0. One-time setup (do once, ever)
- [ ] Confirm the `applicationId` (`io.github.carlsibug98_spec.klasify`) is final — it cannot change after the first release.
- [ ] Enable 2-Step Verification on: the Google/Play account, the Apple ID, and GitHub.
- [ ] GitHub backup exists (`carlsibug98-spec/klasify`, private). Push before and after every work session — see §9 for the one-command sync.

## 1. Local release gate (every build)
- [ ] `flutter analyze` — no new warnings.
- [ ] `flutter test` — full suite green (reminder logic, parser, widget tests).
- [ ] Integration tests pass on a real device or emulator.
- [ ] Manual smoke test on a real Android phone: create timetable → OCR import → set a reminder → reboot the phone → reminder still fires.
- [ ] Bump `version:` in `pubspec.yaml`; the `+NN` build number must strictly increase for Play.

## 2. Signing
- [ ] `android/key.properties` points at your upload keystore (kept out of source control).
- [ ] Keystore backed up in **two separate places** (e.g. password-manager vault + encrypted USB). A lost key means the listing can never be updated again.
- [ ] Passwords live in a password manager, never in shell history or notes.

## 3. Build + 16 KB / API-level verification (every build)
- [ ] `flutter build appbundle --release` (upload this .aab to Play).
- [ ] `python3 tool/check_16kb.py <the .aab or .apk>` → must print **PASS**. (Rule in force since Nov 1, 2025 for apps targeting Android 15+; cross-check Play Console's pre-launch report on the first upload.)
- [ ] For distribution builds with crash reporting, add the DSN define (see README "Crash reporting").

## 4. Privacy policy URL (blocks both stores)
- [ ] Host `docs/privacy-policy.html` publicly. GitHub Pages recipe (~2 min):
  1. Create a small **public** repo, e.g. `klasify-site`.
  2. Add the HTML as `index.html` at the repo root.
  3. Repo → Settings → Pages → Source: *Deploy from a branch* → `main` / `/ (root)` → Save.
  4. Wait ~1 minute; the URL is `https://carlsibug98-spec.github.io/klasify-site/`.
- [ ] Paste that URL into Play Console → App content → **Privacy policy**, and App Store Connect → **Privacy Policy URL**.
- [ ] Set a real support email as the store listing's **Developer contact** — the policy's contact section points there.

## 5. Google Play submission
- [ ] Play Console → Create app ("Klasify").
- [ ] App content: privacy policy URL; ads = none; **Data safety** form:
  - Build **without** the Sentry define → declare *No data collected*.
  - Build **with** Sentry → declare Diagnostics / Crash logs + device & OS info, *not linked to identity*, *not used for tracking*.
- [ ] Upload the .aab first to the **Internal testing** track (fast sanity check, up to 100 testers).
- [ ] Then the **Closed testing** track: personal (non-organization) accounts need **12 testers opted in continuously for 14 days** before production access. Start this clock as early as possible — it is the long pole; plan the semester calendar around it.
- [ ] Read the pre-launch report findings after the first upload; fix crash/ANR flags before production.
- [ ] After approval: staged rollout (e.g. 20% → 50% → 100%).

## 6. Apple App Store (optional, later)
- [ ] Privacy "nutrition labels": *Data Not Collected* (or Diagnostics only if a Sentry build ships).
- [ ] Privacy Policy URL = the same hosted page.
- [ ] Guideline 4.2 (minimum functionality) is comfortably met by OCR import + reminders + home-screen widget; say so in the review notes.

## 7. Launch + first 72 hours
- [ ] Day 0: notify the beta testers; start the staged rollout.
- [ ] Watch for 72 h: Play vitals (bad-behavior thresholds: crash rate 1.09%, ANR 0.47%), Sentry issues if enabled, and the first reviews.
- [ ] Success metric defined *before* launch, e.g. "≥ 20% of installs return in week 6" — read it from Play Console statistics; revisit onboarding if the number comes in low.

## 8. GitHub backup & zip sync (every work session)
The sandbox agent keeps the repo and the downloadable zip in sync with one
command: `/home/z/my-project/scripts/sync_github.sh "<commit message>"`.
It performs, in order:

1. **Commit** any pending changes (message = first argument).
2. **Push** `main` to `carlsibug98-spec/klasify`.
3. **Rebuild** `download/klasify-v<version>-build<N>.zip` (version derived from
   `pubspec.yaml`; full source **plus `.git`**, so the zip alone can restore the
   whole repo anywhere).
4. **Leak-scan** the zip: plaintext sweep plus a full-history
   `git log --all -S` pickaxe for `github_pat_`/`ghp_`/`gho_`/`ghs_`.
   On any hit the zip is destroyed and nothing is uploaded.
5. **Add** the zip as a new asset on the GitHub release **`latest-build`**
   (repo → Releases → "Latest build"). **Never replace or delete older
   assets** — every build's zip stays downloadable forever so previous
   versions can be pulled at any time. The newest build is simply one more
   asset on the same release, listed alongside all earlier ones.

Token handling: a fine-grained PAT scoped to **only** `carlsibug98-spec/klasify`
with *Contents: Read and write*, stored at
`/home/z/my-project/.secrets/klasify_gh_token` (chmod 600, symlinked to
`.secrets/github-token.txt`) or passed via `$KLASIFY_GH_TOKEN`. It is never
committed, never embedded in remote URLs or command lines. Revoke and rotate
immediately if it ever leaks, and before its expiry date.

## 9. Yearly maintenance
- [ ] Google Play raises the target-API bar every August (36 since Aug 31, 2026 → expect 37 by Aug 31, 2027). When the Flutter toolchain supports it, raise both `maxOf(..., 36)` numbers in `android/app/build.gradle.kts`.
- [ ] Re-run this checklist from step 1 for every release.
