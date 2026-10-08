# iOS signing and distribution — what's needed

Nothing is set up for iOS signing yet. Everything below waits on the Apple
Developer Program enrollment; this is the checklist for when it's done.

## Already in place

| | |
|---|---|
| Bundle ID | `com.bridgitcampus.app` (the same as Android's applicationId) |
| Firebase iOS app | **Not yet registered for `com.bridgitcampus.app`.** `Runner/GoogleService-Info.plist` and `lib/firebase_options.dart` still describe the old `com.runit.runIt` app (`1:694264652054:ios:5c18b92ed749f3b61f7037`) — replace them with `flutterfire configure` once the new iOS app is registered |
| Push entitlement | `Runner/Runner.entitlements` has `aps-environment`; `UIBackgroundModes` has `remote-notification` |
| Signing style | Automatic (Xcode manages certificates and profiles once a team is set) |
| Minimum iOS | 15.0 |
| Purpose strings | Camera, Face ID, location (when in use) |

## Needed on this Mac first (no Apple account required)

- **Xcode** (full app from the App Store, not just Command Line Tools —
  `xcodebuild` currently fails with "requires Xcode"). Plan for ~40 GB of
  free disk for the install plus simulators.
- **CocoaPods** (`brew install cocoapods`) — not installed; the Firebase
  plugins need it.
- Then `flutter build ios --no-codesign` should succeed — the first real
  check that the iOS side compiles at all.

## Once the Apple Developer account exists

1. **Team ID** — from developer.apple.com → Membership. Set it in Xcode
   (Runner target → Signing & Capabilities → Team). That writes
   `DEVELOPMENT_TEAM` into the project; commit that change (it isn't secret).
2. **App ID** — with automatic signing Xcode registers `com.bridgitcampus.app`
   itself. Make sure the **Push Notifications** capability is on for it.
3. **Certificates** — Xcode creates these automatically:
   - *Apple Development* (running on your own iPhone),
   - *Apple Distribution* (TestFlight / App Store builds).
   Export the distribution certificate with its private key (.p12) and back
   it up with a password, the same way as the Android keystore.
4. **Provisioning profiles** — also automatic:
   - Development (your registered test devices),
   - App Store (TestFlight + release).
   An *Ad Hoc* profile is only needed to ship iOS builds through Firebase
   App Distribution — every tester's iPhone UDID must be registered first
   (100 per year). **Recommendation: use TestFlight for iOS testers** —
   email invites, no UDIDs, and it's the same build that goes to the store.
5. **APNs key (required for any iOS push)** — developer.apple.com → Keys →
   new key with *Apple Push Notifications service*. Download the `.p8` once
   (it can't be re-downloaded), note its Key ID, and upload it in Firebase
   Console → Project settings → Cloud Messaging → Apple app configuration,
   with the Team ID. Keep the `.p8` out of the repo, like the other keys.
   Without this, FCM accepts iOS pushes but none arrive.
6. **App Store Connect** — create the app record (bundle ID
   `com.bridgitcampus.app`, name, SKU), then fill in the privacy questionnaire
   (email, location, photos/ID for KYC, payments), a privacy policy URL,
   and export compliance: the app only uses standard HTTPS, so add
   `ITSAppUsesNonExemptEncryption = NO` to `Info.plist` to skip the
   question on every upload.

## Building and uploading

```sh
flutter build ipa --release --dart-define=API_BASE_URL=https://<production backend>
```

then upload `build/ios/ipa/*.ipa` with Xcode's Organizer or Transporter, and
add testers in App Store Connect → TestFlight.

## Before the first submission, also check

- The rebrand on iOS (app icon set, launch screen, display name — currently
  `Run-It`).
- Face ID / biometric sign-in, the camera (KYC, QR scan) and the location
  prompt on a real iPhone — none of it has run on iOS yet.
- Push on a real iPhone (simulators can't receive APNs-backed FCM pushes
  reliably).
