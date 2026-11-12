# External TestFlight Release Checklist

This checklist prepares an external TestFlight build without weakening Travels' local-first privacy model. Uploading, submitting for TestFlight App Review, and inviting testers remain deliberate App Store Connect actions.

## 1. Account and version prerequisites

- Confirm all Apple Developer Program agreements are accepted.
- Confirm the App Store Connect app record uses `com.adigitalanalog.travels`.
- Confirm the marketing version is `2.0.0`.
- In App Store Connect, find the highest build number already uploaded and choose a larger unused positive integer.
- Confirm the public privacy policy will be available at `https://github.com/dkrnet/travels-ios/blob/main/PRIVACY.md` after this change is merged.
- Confirm MPL-covered source remains publicly available to TestFlight recipients.

## 2. Validate the source tree

Run:

```bash
scripts/run_regression_tests.sh
```

Complete the real-device checks in the manual release validation section of `requirements.md`, especially background location, permissions, photo import, privacy lock, backup, and restore.

## 3. Create and validate the archive

Replace `BUILD_NUMBER` with the unused App Store Connect build number:

```bash
scripts/archive_testflight.sh --build-number BUILD_NUMBER
```

The script validates the archived bundle identifier, marketing version, numeric build number, encryption declaration, bundled privacy manifest, and that App Store icons contain no alpha channel. It does not upload the archive.

To also produce an IPA for Transporter without uploading it:

```bash
scripts/archive_testflight.sh --build-number BUILD_NUMBER --export
```

Do not reuse an archive or export path. Do not reuse a build number previously uploaded to App Store Connect.

## 4. App Store Connect metadata

Before external testing, review and complete:

- Privacy Policy URL.
- App Privacy answers. Travels' developer does not receive or retain user location history; records remain local unless the user explicitly shares them. Verify the current questionnaire treatment of optional Apple reverse-geocoding services before publishing the answers.
- Export compliance. The app declares that it does not use non-exempt encryption; revisit this if custom cryptography is ever added.
- TestFlight beta description and feedback email.
- Beta App Review contact information.
- Beta App Review notes. Travels has no account or login. Explain that background-route testing requires Location permission and that address lookup is disabled by default.
- Screenshots or category information if App Store Connect requests them.

Suggested beta description:

> Travels is a privacy-first personal location-history app. It stores history locally, supports map and list browsing, automatic and manual capture, Shortcuts, search, GPX import/export, optional photo import, optional Apple address lookup, and a privacy lock.

Suggested What to Test text:

> Please test permission onboarding, automatic foreground and background location capture, map/list browsing, search, trip filtering, manual and Shortcuts captures, GPX import/export, photo import, optional address lookup, settings persistence, and privacy lock. Report unexpected gaps, duplicates, excessive battery use, freezes, or confusing permission behavior without attaching private location history.

## 5. Upload and external testing

- Upload through Xcode Organizer or Transporter only after inspecting the validated archive or IPA.
- Wait for App Store Connect processing and resolve all warnings.
- Create an internal testing group before creating the first external testing group.
- Create the external group, add one eligible build, provide What to Test text, and submit it for TestFlight App Review.
- Do not enable automatic tester notification until the intended tester list or public-link criteria have been reviewed.
- The first external build requires TestFlight App Review; later builds for the same version may receive a shorter review.
- TestFlight builds expire after 90 days.

## 6. Post-upload checks

- Install the processed TestFlight build on a device that does not have a development build.
- Confirm the About screen reports the expected version and build.
- Confirm the Developer Diagnostics menu is absent.
- Repeat permission, background-location, import/export, backup/restore, and privacy-lock smoke tests.
- Confirm TestFlight feedback does not unintentionally include private location history before sharing it outside the development team.
