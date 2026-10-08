# Android release signing

Release builds (`flutter build apk --release` / `flutter build appbundle`) are
signed with RUN-It's **upload key**, never the debug key. Without the key
material below, a release build fails with "Release signing isn't
configured" — that's deliberate.

## Where the key material lives

Nothing secret is in this repo. Two files hold it, both outside git:

| File | What it is |
|---|---|
| `~/.run-it-signing/run-it-upload-keystore.jks` | The upload keystore (PKCS12, alias `upload`, RSA 4096, valid until 2054-02-13) |
| `~/.run-it-signing/key.properties` | Backup copy of the passwords + keystore path |
| `android/key.properties` | The copy Gradle actually reads (gitignored — never commit it) |

`android/.gitignore` ignores `key.properties`, `*.jks` and `*.keystore`.

## Back it up — now, and outside this machine

If the keystore **and** its password are both lost, RUN-It can't ship an
update under the same app identity (`com.bridgitcampus.app`) — unless the app is
enrolled in Play App Signing (below), in which case Google can reset a lost
upload key after identity verification.

Keep **both** of these somewhere safe, off this laptop:

1. the file `~/.run-it-signing/run-it-upload-keystore.jks`
2. the password (the `storePassword` line in `~/.run-it-signing/key.properties`;
   `keyPassword` is the same value)

A password manager entry with the `.jks` attached plus the password is ideal.

To check a backup is the right key, its certificate fingerprint must be:

```
SHA-256: E8:E0:78:27:0D:62:D1:EC:68:82:59:E0:15:C0:EB:8F:DF:70:AA:C7:F8:53:B6:14:AD:F0:04:DA:D9:5A:BE:8B
```

(`keytool -list -v -keystore run-it-upload-keystore.jks -alias upload`)

## Play App Signing (recommended)

When the app is first uploaded to Google Play, opt in to Play App Signing
(the default for new apps; required for `.aab` uploads). Google then holds the
key that signs what users install, and this keystore becomes only the
*upload* key — losable and resettable via Play Console support instead of
fatal. Until then, treat it as irreplaceable.

## Restoring on a new machine

1. Put the keystore back (any path works).
2. Create `android/key.properties`:

   ```properties
   storeFile=/absolute/path/to/run-it-upload-keystore.jks
   storePassword=<password>
   keyAlias=upload
   keyPassword=<password>
   ```

3. `flutter build apk --release`, then verify the signer matches the
   fingerprint above:

   ```sh
   $ANDROID_HOME/build-tools/<version>/apksigner verify --print-certs \
     build/app/outputs/flutter-apk/app-release.apk
   ```
