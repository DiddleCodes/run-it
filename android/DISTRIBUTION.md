# Sending Android builds to testers (Firebase App Distribution)

Signed release builds go to testers' phones through Firebase App Distribution
— no Play Store involved. Testers get an email invite, install the "App
Tester" app once, and every new build shows up there.

| | |
|---|---|
| Firebase project | `run-it-febca` |
| Android app | `com.runit.run_it` (`1:694264652054:android:96c2410f7f6bd4e61f7037`) |
| Tester group | `testers` ("RUN-It testers") |
| Signing | the upload key — see [SIGNING.md](SIGNING.md) |

## Sending a build

```sh
API_BASE_URL=https://<production backend> tool/distribute_android.sh "What changed"
```

The script:

1. builds a signed release APK pointing at `API_BASE_URL`, with the git
   commit count as the build number (so each build installs over the last);
2. refuses to continue unless the APK is signed by the upload key
   (fingerprint in SIGNING.md);
3. uploads it and sends it to the `testers` group with your release notes.

It needs the Firebase CLI logged in to an account with access to
`run-it-febca` (`firebase login`; if `firebase` isn't installed the script
uses `npx firebase-tools`).

**Until the backend is hosted** (Railway), there's no URL a tester's phone can
reach. `ALLOW_LOCAL_BACKEND=1` builds against `http://localhost:3000`, which
only works for a phone plugged into the dev machine with
`adb reverse tcp:3000 tcp:3000` — useful for checking the pipeline, not
for real testers. The script refuses a non-`https://` backend otherwise.

## Adding testers

```sh
firebase appdistribution:testers:add someone@example.com --group-alias testers --project run-it-febca
```

They get an invite email for the next build sent to the group. Remove with
`appdistribution:testers:remove`.

## Installing as a tester

1. Open the invite email on the Android phone → **Get started** → sign in
   with the invited Google account.
2. Install **App Tester** when prompted (allow installs from unknown sources
   for it).
3. Open the RUN-It build in App Tester → **Download** → **Install**.

New builds sent to the group appear in App Tester (and by email).
