# Sovi

An iPhone companion for organizing health and social-insurance matters in Austria. Built with SwiftUI, Swift 6 and SwiftData for iOS 18+.

## Features

- A life path with appointments, tasks, documents and vaccinations.
- Guided conversations for family support, life after hospital discharge, health promotion and child-related services.
- Reusable profiles and editable PDF form drafts.
- German and English UI, accessibility support and dark mode.

The demo works offline with fictional data. Optional online navigation chat requires a configured [PHP backend](apps/backend/README.md) and a prototype API token.

Sovi helps organize next steps. It does not provide medical advice, book appointments or submit applications.

## Run

1. Open `apps/ios/Sovi.xcodeproj` in Xcode 26+.
2. Select the **Sovi** scheme and an iPhone simulator running iOS 18+.
3. Press **⌘R**. No credentials are needed for the offline demo.

## Checks

```sh
./scripts/check-ios.sh
./scripts/check-life-path.sh
./scripts/test-ios.sh YOUR_SIMULATOR_UUID
```

## More

- [Demo walkthrough](DEMO.md)
- [AI integration](AI_INTEGRATION.md)
- [Validation status](docs/VALIDATION.md)
