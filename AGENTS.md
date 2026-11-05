# Working on Sovi

- Keep the setup and implementation simple. The current scope is the offline path-and-companion prototype described in README.md and DEMO.md.
- Native SwiftUI, Swift 6, iOS 18+. Project: `apps/ios/Sovi.xcodeproj`, scheme: `Sovi`.
- Run `./scripts/check-ios.sh` to check the simulator build.
- Place screens in `Features`, shared UI in `DesignSystem`, and assets/localizations in `Resources`.
- Support German and English, Dynamic Type, VoiceOver, and light/dark appearance.
- Austria is the first market. The long-term idea is a companion people can join at any life stage.
- Keep website work in `apps/website`, research in `research`, brand assets in `design`, and campaigns in `marketing`.
- Do not add backend services, analytics, health data collection, clinical guidance, or extra dependencies without a concrete feature request.
- Keep signing overrides in ignored `apps/ios/Configuration/Local.xcconfig`. Never commit credentials or real health data.
