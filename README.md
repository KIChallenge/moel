# Sovi

An iPhone companion for organizing health and social-insurance matters in Austria. Built with SwiftUI, Swift 6 and SwiftData for iOS 18+.

## Features

- A life path with appointments, tasks, documents and vaccinations.
- Guided conversations for family support, life after hospital discharge, health promotion and child-related services.
- Reusable profiles and editable PDF form drafts.
- German and English UI, accessibility support and dark mode.

The path, forms and document reader work offline with fictional data. Chat connects automatically to the hosted [PHP backend](apps/backend/README.md), detects the conversation language and offers follow-up answers. Users enter no API credentials.

Sovi helps organize next steps. It does not provide medical advice, book appointments or submit applications.

## Run

1. Open `apps/ios/Sovi.xcodeproj` in Xcode 26+.
2. Select the **Sovi** scheme and an iPhone simulator running iOS 18+.
3. For a connected build, set `SOVI_CHAT_ACCESS_TOKEN` once in the ignored `apps/ios/Configuration/Local.xcconfig` to the existing server prototype token. Never use the OpenAI key. The token is bundled for the controlled test group; it is not user authentication.
4. Press **⌘R**. Without a configured build token, local features still work and chat reports a connection error. UI tests use an isolated transport fixture.

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
