# Distributing the iOS build to testers

Two practical paths. Pick TestFlight for a remote tester who will run the
field-test protocol for weeks (set up once, auto-updates); pick Ad Hoc for a
one-off "show it today" install.

Prerequisites (both paths): paid Apple Developer Program membership — this
project signs with team `HMG65UJ7YG`, automatic signing is already configured
in the Xcode project. Bundle id: `com.clockster.geoProbe`.

---

## Option 1 — TestFlight (recommended)

1. **Create the app record** in [App Store Connect](https://appstoreconnect.apple.com)
   → My Apps → **+** → New App, bundle id `com.clockster.geoProbe`.
   If the bundle id is not offered in the dropdown, register it first at
   developer.apple.com → Certificates, IDs & Profiles → Identifiers (or run
   one automatic-signing build in Xcode, which registers it for you).

2. **Build the release IPA:**

   ```bash
   cd geo_probe
   flutter build ipa --release
   ```

   Output: `build/ios/ipa/geo_probe.ipa`. Bump `version:` in `pubspec.yaml`
   before each upload (build number must be unique per version).

3. **Upload** the `.ipa` with the **Transporter** app (Mac App Store), or via
   Xcode → Window → Organizer → Distribute App.

4. **Invite the tester:** App Store Connect → your app → TestFlight →
   **Internal Testing** → create a group → add the tester's Apple ID email
   (they must first be added as a user under Users and Access, any role
   works). The tester installs the TestFlight app and accepts the email
   invite.

Why Internal (not External) testing matters here: **internal testers do not
go through Apple's beta review.** geo_probe requests Always location with no
prominent-disclosure screen (it is a diagnostic tool, not a product), which
an External-testing beta review could flag. Internal testing sidesteps that
entirely. Limits: up to 100 internal testers; each new uploaded build becomes
available to them automatically within minutes.

---

## Option 2 — Ad Hoc IPA (no App Store Connect involved)

1. **Get the tester's device UDID:** connect the iPhone to any Mac → Finder →
   click the device → click the serial-number line until UDID shows; or on
   the phone: Settings → General → About → long-press Serial Number.

2. **Register the device:** developer.apple.com → Certificates, IDs &
   Profiles → **Devices** → + (limit: 100 devices per membership year;
   removing devices does not free slots until the yearly reset).

3. **Build:**

   ```bash
   flutter build ipa --release --export-method ad-hoc
   ```

4. **Install** `build/ios/ipa/geo_probe.ipa` on the tester's phone:
   - cable + Mac: Finder (drag the ipa onto the device) or Apple
     Configurator 2, or
   - over the air: upload the ipa to a service like Diawi and send the
     tester the link to open on the phone.

Caveats: the device must be registered *before* the build (the ad-hoc
provisioning profile embeds the device list); updates are manual re-installs;
the profile — and with it the installed app — expires after 1 year.

---

## What does NOT work

- **Sharing a debug build** — it will not run on an unregistered device, and
  debug builds are JIT-mode (slow, and iOS kills JIT apps launched from the
  home screen on recent iOS versions).
- **`flutter run` install as a hand-off** — a development-signed install
  works only on registered devices, expires with the dev profile, and gets no
  updates.
- **Enterprise / unlisted distribution** — not applicable and, per the
  engineering spec (§7.4), not an escape hatch from review for the real
  product either.

## Reminder for uploads from this machine

iOS versioning for release archives comes from the pbxproj
(`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`) via Info.plist variables —
for this test project the Flutter defaults (`FLUTTER_BUILD_NAME/NUMBER` from
`pubspec.yaml version:`) are used, so bumping `pubspec.yaml` is sufficient.
