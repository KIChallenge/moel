# Validation status

Updated 5 November 2026. The original offline checks below and the current guided-prototype runtime checks at the end are separate validation stages.

## Checks actually completed

- `./scripts/check-ios.sh`: **passed, exit 0** for the app, including the continuous path, raised circular buttons, green year banners, on-path speech bubble, edge companion and existing supporting features.
- `./scripts/check-life-path.sh`: **38 checks passed, exit 0**, using the actual Foundation/CryptoKit domain, seed, path-invitation and companion sources. This runs without a simulator.
- Native macOS check of the actual Swift 6/SwiftData store: **passed, exit 0** for migration persistence, task/draft/custom-entry/profile preservation, repeat-load idempotence, normalized PDF-text deduplication, deletion and explicit reload. No simulator was used.
- Generic `xcodebuild build-for-testing`: **passed, exit 0**. The unit and UI test targets compile; no tests or simulator were launched.
- Eight native macOS SwiftUI component previews rendered for the current day, birth records with a bottom peek, future records with a top peek, a quiet check-in on a compact width, dark appearance and the accessibility layout branch, the two-vaccination day and vaccination source details. The actual route layout contains **208 day placements and 34 year headings**, with every year open and no collapse controls. These are component previews, not device screenshots; iOS font scaling and scroll/Focus interactions still need the user's runtime check.
- Swift syntax parsing passed for the app changes and XCTest/UI-test sources. Xcode project and German/English localization plists lint successfully.

The original 20 checks, updated for the revised demo, cover 305 entries → 208 unique calendar days; 67 exact-count halos; five planned outlook days; birth and current-day grouping; five appointments with unrecorded attendance; zero derived medication schedules; four historical therapy attendances; four unique open tasks with one questionnaire alias; exact original passages for every entry; stable identities/dates; JSON persistence round-trip; actual-state companion summaries; date-edit regrouping; age 33 at the supplied snapshot; 51 fictional respiratory episodes with only two explicitly titled influenza days; backward-compatible snapshot decoding; and reviewable reimbursement-draft routing.

Eight additional checks cover the bubble's exact appointment context/time, read-only generation, quiet check-ins without stale context, the inclusive 30-calendar-day boundary and actual edited appointment date, fallback beyond the boundary, exclusion of past/cancelled/draft/attendance-recorded appointments, date-only tasks throughout today, and exclusion of completed/cancelled/overdue/undated/distant/duplicate task references.

Ten vaccination checks cover nine records/eight days/five COVID-19/four influenza, same-day grouping, product/batch/PZN/dose/page details, two date-only records, separate administration/registration times and UTC offsets, original PDF/text links, replacement of only the 32 placeholders, preservation of the other 296 records, idempotent migration with user progress, no reseeding of empty/unrelated stores, and companion summaries without derived schedules. The bundled PDF was byte-compared with the supplied original (SHA-256 `da2002c80f2941836191fbaafc0c32af0f54216d6ae730fdf0a4095a1ebc3bbf`).

The original provided text is bundled without changing its content. Other clinical source types named in that text are not attached scans or retrieved patient records. The separately supplied two-page test vaccination PDF is bundled unchanged, with its original 1987 test identity intact; the app’s example profile remains born in 1993. The minimal interface now exposes provenance through source access. The public bibliography is retained as context and has not been re-verified as an individual medical history.

## Native suites provided for local execution

- 16 original domain tests, updated for the new seed.
- 10 companion-service tests, updated for unique tasks and the new scenario.
- 14 life-path tests for exact day/entry/halo counts, read-only opening, shared task/draft behavior, independent historical medication and attendance, appointment moves, persistence/deletion/reload, old snapshot preservation, repeat-source import, the 30-day path bubble, documented vaccination fields/pages, one-time migration and source reimport.
- Four UI smoke tests for the path, mascot Focus, typed interaction, keyboard, contextual day entries, large text and both peeking edges with invitation context, and the two-vaccination day with its original PDF.

The original suites were initially compile-checked only. Current unit and selected UI execution is recorded in the guided-prototype section below. OS microphone/notification permission behavior and notification delivery remain separate manual/device checks.

## Run locally

1. Open `apps/ios/Sovi.xcodeproj`, scheme **Sovi**, with Xcode 26+ and an iOS 18+ iPhone runtime.
2. Existing 33-year demo stores receive the vaccination update once on next launch, keeping other progress. Unrelated older stores remain untouched; use overflow → **Pfad zurücksetzen** and confirm replacement to load the full example. A fresh install seeds it once.
3. Press **⌘R** to run or **⌘U** to run the native suites. CLI: `./scripts/test-ios.sh YOUR_SIMULATOR_UUID`.
4. Follow `DEMO.md`: scroll all years continuously, open birth/current-day halos, inspect exact sources, complete/reopen the shared questionnaire task, record attendance explicitly, edit a local date, export a sample draft, restart, delete, and explicitly reload.
5. Browse older dates until Sovi peeks from the bottom, then ahead until it peeks from the top. Tap its bubble, check the selected context, close Focus and confirm the scroll position is retained. Open the two vaccinations on 3 November 2025 and verify fields and original PDF pages (including page 2 for 17 November 2021). Check compact/large iPhones, VoiceOver, Dynamic Type, Reduce Motion and dark appearance. Confirm speech is opt-in/on-device-only, transcription remains editable, audio stops on exit/background, notifications require opt-in and never imply completion.

The default example is fixed at 5 November 2026, 09:00 Europe/Vienna. The path does not predict later illness or generate unlimited fictional records. New explicit entries can extend the same continuous scroll.

## Minimal interface copy update

- Removed rendered demo/test/prototype labels, snapshot/profile captions, repeated explanations and long companion responses. Essential actions, record fields, source/PDF access, local-action scope and destructive confirmations remain. German and English controls/response templates were updated; obsolete prototype localization entries were removed.
- `./scripts/check-ios.sh`: passed for the final UI. The 38 offline scenario checks also passed after updating their response assertions.
- Read-only presentation audit passed for every seeded record/source label and appointment field, including appointment preparation after a local edit. Original quoted evidence remains exact.
- Eight macOS component previews were refreshed; current-path and vaccination-detail previews were inspected. These are component renders, not iOS runtime screenshots.
- Original source files and stored/user-authored content remain unchanged. Conversation history omits old assistant prototype scaffolding from display; user messages remain visible.
- See the current guided-prototype section below for later simulator execution.

## Reference-style path update

- Compile-only app check passed after the compact path redesign; the existing unit/UI test targets also compiled with generic `build-for-testing`. No simulator was launched.
- Native macOS rendering refreshed eight component previews. Layout assertions confirm 208 unique day placements, 34 year boundaries, the current day centered at 195pt on a 390pt canvas, and a 106pt pitch to the next outlook day. Current, historical and dark edge-peek previews were inspected. These are component renders, not runtime/device screenshots.
- The layout now uses compact raised disks, small dates, a smooth wave, persistent green section context, a current-day pointer and real local record counts. All record statuses and sources are unchanged. Larger text/straight layout retains full labels; current-day emphasis is independent of completion.
- End spacing lets Sovi reach the top peeking state even with the five supplied future days; no extra medical records are generated.
- User runtime checks: verify initial anchoring near today, banner changes at year/outlook boundaries, both edge peeks, Focus return position, compact-width and accessibility text layouts.

## Welcome chat, forms and four guided scenarios

- Simulator build: `./scripts/check-ios.sh` passed for the welcome conversation, reusable profiles, optional permission steps, seven PDF templates, saved guided workflows and native nearby contact map.
- Foundation-only offline regression: all 38 existing scenario checks passed after including the new Codable types in the validation harness.
- Native XCTest: all 52 unit cases passed. Six new cases cover welcome validation/resume, separate permission questions with no implicit opt-in, relative/profile/form persistence and deletion, four explicit-review/idempotent task journeys, refusal to derive a rehabilitation recommendation from a symptom, and prefill/export of all seven supplied PDFs.
- Three selected simulator UI cases passed with a clean `TEST SUCCEEDED` result: guided care conversation and form-library navigation, the existing Focus keyboard/return interaction, and the welcome conversation through both optional permission choices. Result: `artifacts/TestResults/20261105-201926.xcresult`. The UI tests continue without granting permissions; actual iOS permission grants, notification delivery and live nearby search still need a device/manual check.
- Seven exported synthetic PDFs were reopened using an independent PDF parser. All 52 expected canonical field values matched; filled widgets agreed with their field tree values and had nonempty appearances. All 14 pages carrying prefilled values were rendered and visually inspected, including repeated insurance-number fields and bank details. Interactive widgets and original page counts were retained. Blank bundled originals match the seven supplied sources byte-for-byte; hashes are in `Resources/Fixtures/Forms/catalog.json`.
- The first run exposed a hierarchical field name in the Pflegegeld PDF (`Fam.Name`) and a parent accessibility identifier overriding the demo buttons. Both were corrected before the successful run. Declining the optional notification prompt also clears its generic settings warning; final compilation was repeated after that small change.
- No real personal/health records or paid model calls were used. The guided journeys are deterministic local demonstrations, and PDF support is reviewed text prefill/edit/export rather than general medical document understanding or automatic completion of checkboxes, signatures and professional sections.

## Connected discharge and parent-support journeys

- All 60 native unit cases passed with a clean `TEST SUCCEEDED` after adding eight focused case tests. Coverage includes exact quotes and native PDF page ranges, retention of the original PDF bytes, source-review gating, evidence on saved tasks, repeated-import/save protection, PV/SVS/BVAEB common-case routing and unresolved cases, conditional document checks, corrected answers, linked applicant/draft persistence, live missing-item responses, and case disambiguation. A literal page reference inside a plain-text document does not establish a PDF page number.
- The care UI journey passed after its additional first-application/payer/signing-role/available-record questions; the existing Focus keyboard/return regression also passed in `artifacts/TestResults/20261105-204721.xcresult`. The completed discharge PDF → reviewed quotes → selected applicant → prefilled Kur/Reha form → saved case-linked draft UI path passed in `artifacts/TestResults/20261105-205340.xcresult`. Its actual screenshot was exported and inspected.
- The two-page fictional discharge asset was rendered and both pages inspected. The app imports the bundled sample through the same PDF reader as a selected external file; it is not a preconstructed source-less response. Recommendations are a bounded phrase recognizer, never diagnosis-based inference or broad clinical document interpretation.
- Independent PDF rendering exposed a PDFKit radio-widget interoperability issue: although PDFKit reopened the selected value, another reader could display an empty application-type checkbox. The exporter therefore preserves open boxes. The explicitly selected application type remains visible and saved in the case/form editor for personal review; the user marks the original PDF box themselves. No automatic signature, declaration or medical-field filling was added.
- Rehab/accident forms no longer assume that the saved health insurer is the responsible rehabilitation carrier. That field stays open and the case asks the user to clarify it with the treating practice. This safeguard and the final build are checked again with the focused case suite.
- The original 38 Foundation-only life-path regression checks remain passing. No new runtime dependencies, backend deployment, real patient records or paid model calls were used.
- Final simulator build passed without app warnings/errors. The focused eight-case suite was rerun after the rehab-carrier safeguard and passed with a clean `TEST SUCCEEDED`: `artifacts/TestResults/20261105-210106.xcresult`.
