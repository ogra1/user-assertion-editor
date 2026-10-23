# user_assertion_editor

A Yaru/Flutter desktop app for creating and signing **`system-user`
assertions** for Ubuntu Core. On systems where `console-conf` is suppressed
(grade `dangerous` / first-boot USB flow), a brand-signed `system-user`
assertion — bundled as `auto-import.assert` — is how a local system user is
created on a device. This app is the GUI for that workflow.

> Sibling projects with a very similar shell (nav-rail wizard + footer status
> bar + Yaru): `ubuntu-core-model-builder` (model assertions) and
> `gadget-editor`. If you already know one, you know the layout.

## Run / verify

```bash
export PATH="$PATH:/snap/bin"      # flutter is a snap in the dev container
flutter pub get
flutter analyze                    # expect: No issues found
flutter test                       # expect: all tests pass (incl. sha512crypt vectors)
flutter build linux --release      # -> build/linux/x64/release/bundle/
flutter run
```

Signing shells out to the real snapd CLI, so a working `snap` + a key in the
local keyring (`snap keys`) is required to actually sign — see the Sign step
in-app.

## Layout

```
lib/
  main.dart                     YaruTheme root + YaruWindowTitleBar init
  models/
    system_user_model.dart      the SystemUser value object (all assertion fields)
    wizard_state.dart           WizardState (ChangeNotifier): model, gating, busy, key, SignOutput
    wizard_step.dart            5 steps + labels/icons
  pages/                        one page per step: user, device, timing, sign, export
  services/
    assertion_builder.dart      JSON header builder + field validation (mirrors snapd rules)
    assertion_parser.dart       parse signed chains / JSON headers back
    assertion_verifier.dart     post-sign verification report (field-by-field)
    sign_service.dart           `snap sign -k <key> --chain` (JSON on stdin, chain on stdout)
    signing_key_service.dart    `snap keys --json`
    password_hasher.dart        pure-Dart sha512crypt ($6$) — see note below
    import_service.dart         load an existing .assert / .json back into the editor
    status_bar_service.dart     app-wide footer status (info/success/error)
  widgets/                      Yaru form/chip/status widgets
  theme/status_colors.dart
```

### UI conventions (keep these when changing the UI)
- Root is `YaruTheme(builder:)` → mirrors system light/dark + accent.
- `YaruWindowTitleBar` is the `Scaffold.appBar` (client-side chrome).
- Collapsible `NavigationRail` = the wizard; footer bar has status + Back/Next.
- **Controllers sync to the model only in event handlers (`onChanged`/
  `onSubmitted`), never during `build`** — calling `notifyListeners` in
  `build`/`initState` throws "setState called during build".
- A completed step shows a checkmark; a locked step is disabled. Gating:
  each step is enabled when all *previous* steps are complete. **The Signing
  Key step completes on key selection only — it must NOT require a
  signature** (signing happens on Export; requiring it there deadlocks).

## Critical snapd `system-user` JSON rules (baked into assertion_builder)
These are non-obvious and were hard-won. Do not regress:
- **`"format": "2"` must be a STRING.** `snap sign` copies headers via
  `asserts/headers.go copyHeader`, which only accepts string/`[]any`/map — a
  JSON *number* makes it **panic** ("unexpected value type copying headers").
  Omitting `format` defaults it to `0`, which then rejects `serials` (needs
  ≥1) and `user-presence` (needs ≥2). So: always the string `"2"`.
- **`series` is numeric `"16"`** — the original/only current snapd series.
- `password` must be a crypt(3) sha512crypt hash (`$6$salt$hash`, id ≥ 6);
  this app generates it in pure Dart (`password_hasher.dart`, verified
  byte-for-byte against glibc `mkpasswd`).
- Global assertions (no `models`) are limited to **365 days** of validity.
- `serials` require **exactly one** model.
- `force-password-change` requires a non-empty password.
- `user-presence: until-expiration` (delete user at expiry) requires format 2
  + a password + an `until` date.

## Tests
- `test/password_hasher_test.dart` — sha512crypt vectors (glibc ground truth).
- `test/widget_test.dart` — builder/parser/verifier unit tests + UI regression
  tests (wizard gating, chip draft behavior).

## Dev environment notes
- Dev container: `user-assertion-editor` (Ubuntu 26.04), flutter via snap,
  repo at `/root/user-assertion-editor`.
- Index this repo for RAG with `/root/reindex.sh` (source name
  `user-assertion-editor`).
- Upstream: https://github.com/ogra1/user-assertion-editor
