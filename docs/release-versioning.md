# Orivyn release versioning

Every distributed update must increase **both** the marketing version and build
number. For example, after 0.1.1 (17), use 0.1.2 (18), not 0.1.1 (18).
SideStore's valid-semantic-version update check can ignore a changed build number
when the marketing version stays equal.

## Required release steps

1. Increase `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
   Marketing versions use canonical `major.minor.patch`; builds use Apple's
   numeric build form. Do not add target/configuration overrides for these keys.
2. Set the same literal `CFBundleShortVersionString` and `CFBundleVersion` in
   `JarvisEVO/Info.plist`. Update `OrivynReleaseNotes` with the actual changes,
   verification scope and outstanding limitations. The app displays this metadata.
3. Download the current trusted published Orivyn source and run:

   ```sh
   python3 scripts/release_version_guard.py --project project.yml --source current-source.json
   ```

   The guard fails closed for missing/malformed history and requires both values
   to exceed **every** published version, not just the first entry. A network
   failure must block publication, not replace history with an empty source.
4. Build/test the exact candidate and validate its actual packaged metadata:

   ```sh
   python3 scripts/release_version_guard.py --project project.yml --source current-source.json --ipa artifacts/package-only/Orivyn-0.1.2-build18-unsigned.ipa
   ```

   This supplements structural IPA validation, not runtime or device acceptance.
5. Before publication, fetch fresh history and run the guard again. Serialize
   releases so another publication cannot race this final check. Rerunning an
   already published release intentionally fails the strict increment check;
   verify that existing release separately rather than bypassing the guard.
6. Update the app's source catalogs and OmniForge registry/generated metadata
   with the **actual IPA** version/build, size/hash, URL and release date. Replace
   app-level description and release notes with current, truthful information,
   not merely a new version number. Preserve prior versions and unrelated apps.
   Regenerate unified source, verified fallback state and storefront together.
   Check the live source after publication. Never advertise a marketing version
   that differs from the IPA's `CFBundleShortVersionString`.

The guard does not publish, change signing or app data, or certify substantive
release-note accuracy. It does not certify physical-device behavior. Content
review and the exact-source native/runtime gates remain required.
