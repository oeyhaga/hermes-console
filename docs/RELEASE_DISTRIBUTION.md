# Release and distribution

Hermes Console has three Android flavors built from the same source:

| Distribution | Flavor | Artifact | Purpose |
|---|---|---|---|
| Google Play | `play` | AAB | Store distribution |
| Direct | `full` | APK | GitHub Releases and Obtainium |
| Emulator QA | `qa` | profile APK | Internal testing only |

The `qa` flavor uses a separate application ID and must never be attached to a
public release. Debug and profile artifacts are not release artifacts.

## Reproducible commands

```bash
flutter pub get
flutter analyze --fatal-infos
flutter test

# Google Play bundle
flutter build appbundle --release --flavor play \
  --dart-define=HERMES_FLAVOR=play

# Direct APKs for GitHub Releases and Obtainium
flutter build apk --release --flavor full --split-per-abi \
  --dart-define=HERMES_FLAVOR=full \
  --dart-define=HERMES_LOCAL_AGENT=true
```

These commands build the complete current product. The documented
`HERMES_LOCAL_AGENT=true` flag enables the direct-only Termux integration;
Voice mode, dictation and read-aloud are included in both public flavors.

## Signing

Release builds fail closed unless `key.properties` points to a valid signing
keystore. The keystore and all passwords must stay outside Git. The repository
ignores both files; never attach them to an issue, workflow log or release.

For GitHub Actions, configure these repository secrets before creating a tag:

- `KEYSTORE_BASE64`
- `STORE_PASSWORD`
- `KEY_PASSWORD`
- `KEY_ALIAS`

The public release workflow builds only `fullRelease` split APKs for GitHub and
Obtainium. It never builds, stores or publishes the Play AAB. The `playRelease`
AAB is produced only through the separately authorised private release process
and is handed directly to the owner for Google Play Console.

## Automated release evidence

Direct-release CI must archive, beside the GitHub/Obtainium APKs:

- deterministic source SBOMs and per-artifact inventories;
- `SHA256SUMS` covering every direct APK and the evidence files;
- `apksigner --print-certs` reports for the direct APKs;
- the exact source commit and source timestamp embedded by the SBOM generator.

These files prove what CI built; they do not replace emulator installation,
Google Play inspection, dependency-license review or owner approval. No hash or
certificate is documented as final until it is produced from the signed release
job for the selected commit.

## Release gate

Before tagging a version:

1. Confirm the working tree is clean and the version is intentional.
2. Run static analysis and the complete test suite.
3. Generate and review the SBOM and third-party notices.
4. Build the final artifact for the intended channel from a fresh clone; never
   substitute a `full` APK for Play or a `play` AAB for GitHub/Obtainium.
5. Scan the clone and Git history for secrets.
6. Verify package ID, version, signing certificate and SHA-256 digest.
7. Install the exact APK on an Android emulator and test chat, images,
   QR pairing, voice, background behavior and cleanup.
8. Publish only the signed release files; never publish QA/debug/profile builds,
   mappings, keystores or diagnostic bundles.

Google Play publication additionally requires the current privacy policy, Data
Safety answers, foreground-service declarations and store listing to match the
actual final manifest and runtime behavior.
