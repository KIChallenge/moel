# Native iOS app

Open `Sovi.xcodeproj`, choose **Sovi**, and run on an iOS 18+ iPhone simulator with Xcode 26+.

- `Sovi/App`: single root scene and recoverable startup.
- `Sovi/Core`: typed domain records, transactional SwiftData snapshot, commands, seeded fixtures and replaceable extraction. `LifePath.swift` loads the 33-year sample and projects 305 entries into 208 chronological day buttons.
- `Sovi/Features/Home`: continuous raised-button path, with all years visible and the mascot anchored to the fixed current day.
- `Sovi/Features/Focus`: mascot conversation, editable text and contextual action.
- `Sovi/Features/Sheets`: grouped day lists, individual historical/source previews, shared preparation forms, source review, editors, export and local controls.
- `Sovi/Services`: replaceable offline companion plus real native speech and notifications.
- `Sovi/DesignSystem`: shared colors and reusable vector character.
- `Sovi/Resources`: synthetic fixtures, icon, privacy manifest and translations.
- `SoviTests`, `SoviUITests`: domain/service tests and defining-interaction smoke tests.

The shared **Sovi** scheme includes both test bundles; **SoviTests** runs only unit tests. See the root README for commands, DEMO.md for a walkthrough and docs/VALIDATION.md for actual results. Physical-device development requires your own signing team and bundle identifier via ignored `Configuration/Local.xcconfig`.

Existing saved records are not automatically replaced. Use **Demo neu laden** in the overflow controls to load the new fixture. From the repository root, run `./scripts/check-life-path.sh` for simulator-free scenario checks.
