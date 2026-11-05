# Sovi

A native iPhone prototype of an Austrian health and social-insurance **organizer**, with an offline path and optional online navigation chat. Home is a winding path of useful raised buttons and one original SwiftUI companion. Tap a button for direct actions, or tap Sovi to zoom into a conversation and return to the same scroll position.

The offline build uses synthetic fixtures and deterministic responses. It has no medical advice, provider booking, submission, external AI, analytics, accounts, HealthKit, ELGA or insurer access.

Optional online chat: deploy the version 3 PHP update, then open Sovi → chat settings (sliders), enter the prototype API token and consent. It connects to `https://sovi.elzahaby.at/`, asks short follow-ups with buttons or free text, and supports German/English/Arabic/Turkish replies. Only online messages and individually reviewed background summaries go to OpenAI; optional foreground GPS stays on the PHP server. Sourced Vienna physician coordinates appear in MapKit; other services/regions use official directories. It provides navigation, not diagnosis, urgency assessment or booking. See [backend setup](apps/backend/README.md).

## Launch

1. Open `apps/ios/Sovi.xcodeproj` with Xcode 26+ and an installed iOS 18+ simulator runtime.
2. Select the shared **Sovi** scheme and an iPhone simulator; press **⌘R**.
3. First launch opens a skippable **welcome conversation**. Answers and progress are saved locally, including optional location and notification permission steps. Reusable profile details stay separate from the fictional life path and online chat. After onboarding, the supplied fictional **33-year-old male** example opens at **Mein Tag · 05.11.2026**. Every year stays visible in one continuous scroll; planned dates appear separately in **Ausblick**. Existing installations preserve their data: use the overflow → **Pfad zurücksetzen** and confirm to load the updated example.

Swift 6, iOS 18+ (retaining the repository baseline), SwiftUI, SwiftData, PDFKit, MapKit, CoreLocation, UserNotifications, Speech and AVFAudio. No third-party runtime packages. Offline mode needs no credentials; online chat requires the separately configured prototype token. Physical-device signing: copy `apps/ios/Configuration/Local.xcconfig.example` to ignored `Local.xcconfig`, supply your team and a registered bundle identifier.

```sh
./scripts/check-ios.sh
./scripts/check-life-path.sh  # Foundation-only checks, no simulator
xcrun simctl list devices available
./scripts/test-ios.sh YOUR_IPHONE_SIMULATOR_UUID
# Domain tests only:
./scripts/test-ios.sh YOUR_IPHONE_SIMULATOR_UUID -only-testing:SoviTests
```

Tests produce native `.xcresult` bundles under ignored `artifacts/TestResults`. UI smoke tests use `--uitesting` for a separate in-memory store; normal app launches persist changes. UI tests attach real path/Focus screenshots, including the keyboard. Audio availability and OS notification delivery need a suitable simulator or physical device; neither is simulated.

## Implemented

- A resumable welcome chat using the same mascot bubbles, one optional question at a time, with a saved local conversation. Common name/address/contact/insurance details can be reused in forms. Location and notifications are requested only from explicit onboarding buttons; declining does not block the app. Additional profile details and separate relatives' profiles are editable under **Profile und Formulare**. No identity is imported from the fictional timeline.
- Four bounded, deterministic guided examples under **Gemeinsam starten**: support for a mother, organization after discharge, health promotion and child-related services. They ask focused questions, show official sources and offer explicit approval of persistent, undated tasks. The care case additionally asks application type, pension/current Pflegegeld payer, signing role and available records; it routes common cases to PV/SVS/BVAEB and Vienna home support to FSW, with an explicit unresolved/special-case path. Reopening retains conversation, applicant, document checklist, linked draft and actual task status. These journeys work without API credentials and do not call OpenAI.
- A connected discharge demonstration imports a text-bearing PDF/text document, retains the original PDF locally, finds a small set of explicit rehabilitation/follow-up/physiotherapy phrases, and displays exact quotes with page references. Only individually reviewed recommendations become source-linked steps. The bundled two-page fictional PDF uses the same importer as user-selected files; unsupported wording produces no invented recommendation. The Kur/Reha form is linked to the selected applicant and saved case. This is bounded source extraction with user review, not general medical document interpretation or OCR.
- The main chat can resume stored cases with questions such as **Was fehlt noch für den Antrag meiner Mutter?** or **What is missing for my rehabilitation application?**. Answers read current case questions, applicant completeness, document checks, linked drafts and task status on-device, even when online chat is configured. Ambiguous requests offer a choice of saved cases.
- Seven original supplied PDF forms with reviewed field mappings, personal-data prefill, editable text drafts, PDF preview and interactive PDF export. Form drafts are separate for each person and template. Unknowns, selection boxes, signatures, declarations and professional medical sections are left open; exports are drafts, never submissions or signed official applications. Blank originals are bundled unchanged in `Resources/Fixtures/Forms`; the catalog records filenames and hashes. Existing saved drafts are not silently refreshed after profile edits.
- Foreground GPS selected in onboarding is reused for online provider searches. In the guided examples, native MapKit can find nearby primary-care, pediatric or rehabilitation contacts; users can type a different town instead. Insurance, suitability and appointment availability remain unverified. A relative's location needs an explicit selection. Resolving a local place name and MapKit searches use Apple services; coordinates are not stored in the local profile.

- One root scene with Path and Sovi Focus, a coordinated mascot transition, retained route position and composer draft, contextual previews, optional transcript, and a discreet local-controls sheet.
- The supplied 1993–2026 example: **208 daily buttons, 305 sub-entries and 67 segmented halos**. Life stages/year headings are orientation; all years remain visible in one continuous scroll. One button per known calendar day, source-linked individual details, a fixed current-day anchor and five planned outlook days. Halos count entries, never health or progress.
- Compact raised topic buttons, a smooth winding layout and a persistent solid green section banner. The top strip shows stored appointment, document, vaccination and open-task counts. Sovi peeks from the bottom while browsing older records and from the top while browsing ahead, once its on-path position leaves view. Its bubble uses the next confirmed local appointment or open dated task within 30 calendar days, otherwise a simple check-in. Tapping it opens the same Focus with that entry's context.
- Independent task, reading, source-record, appointment/attendance and medication-occurrence states. The questionnaire reminder links one shared task/draft; four past therapy attendances and five explicit future/current appointments stay distinct. Historical medication records generate no schedules.
- A/B/C fixtures, explicit source-grounded proposal review, editable titles separate from original evidence, repeat-import/approval protection, text and text-bearing PDF imports. Unknown content remains viewable without invented results.
- A bounded fictional medication schedule with six occurrences and correction history; local appointments distinguish drafts, user-recorded confirmation and participation.
- Editable sample administrative draft, visible missing fields, and a real `.txt` share-sheet export. Export never submits anything.
- SwiftData persistence of typed records in a versioned transactional snapshot. The life-path snapshot stays fixed at 5 November 2026, 09:00 Vienna; optional extraction fixture dates and time zone are anchored once. Storage errors are surfaced without automatic reset.
- Optional local reminders with generic wording, stable identifiers, cancellation and notification-context navigation. Optional on-device-only push-to-talk yields editable text. Spoken replies are opt-in and interruptible.
- Separate confirmed deletion/reseed controls. Deletion clears records, conversations, pending/delivered notifications, owned temporary exports and audio; the empty state survives relaunch. Externally shared copies cannot be recalled.
- German primary UI, English translations for controls, Dynamic Type, VoiceOver labels, dark appearance, Reduce Motion, and a straightened representation of the same route for large text/accessibility.

## Simulated and unsupported

`DemoCompanionService` matches German phrasing variants and queries actual state; `DemoPlanExtractor` matches only the exact supported synthetic fixtures. They are demonstration engines, not general AI or clinical validation. Speech and notifications use real native APIs, with explicit permission and failure handling. No OCR, camera scanning, provider messaging, real booking/submission, eligibility calculation, or live medical interpretation exists.

The default life path records historical **DEMO-A** without a usable dose schedule. The separate optional extraction example is **Demo-Präparat A — kein echtes Arzneimittel**. Sovi cannot suggest treatment changes or catch-up doses. Local record edits do not change an appointment with a provider.

## Repository

`apps/ios` app and tests · `apps/backend` optional PHP navigation API with separate configuration ([setup](apps/backend/README.md)) · `apps/website` future website · `design` brand/mascot · `marketing` campaigns/assets · `research` findings · `operations` launch/business notes · `docs` product notes · `scripts` development helpers.

The checked-in Xcode project is runnable directly. If adding source files outside Xcode, optional `ruby scripts/update-xcode-project.rb` regenerates source/test references (requires the `xcodeproj` Ruby gem); normal builds do not require Ruby. See `DEMO.md`, `AI_INTEGRATION.md`, and `docs/VALIDATION.md`.

The original provided text and its structured conversion are bundled at `apps/ios/Sovi/Resources/Fixtures/life-path-33.txt` and `life-path-33.json`. `scripts/import-life-path.py SOURCE.txt` validates and rebuilds the conversion. The referenced Q0–Q9 material is background, not verified individual evidence. The separately supplied test `Impfpass.pdf` is bundled unchanged as `vaccination-pass-2026.pdf`, with native text and a manually checked JSON transcription. Its nine entries replace the 32 original vaccination placeholders; other named historical source documents are not attached scans.

The vaccination update runs once on existing 33-year demo stores, preserving tasks, drafts, custom entries and the current profile. Deleted stores and unrelated older profiles are not seeded. The PDF uses a different test profile (birth year 1987); the original PDF retains that identity while the path keeps its 1993 birth date. No booster dates, vaccination tasks, reminders or medication schedules are inferred.

Interface copy is intentionally minimal. Compact path nodes show a topic icon and short date; full labels/status are available through VoiceOver, the readable layout and entry sheets. Additional vaccination/provider fields use a disclosure. Original document text remains available under source actions; presentation helpers keep prototype scaffolding out of labels without rewriting evidence or user-authored records.
