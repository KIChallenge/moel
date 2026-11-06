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

## Path and chat scrolling

- Replaced the absolute path canvas with individually bounded rows. All year, outlook and undated-task headings are rendered; undated tasks show their names and statuses. The section menu reaches every year, outlook and saved own steps, with a separate Today action.
- The edge companion reserves scroll space instead of covering entries. Its space remains stable while Focus is open, and the underlying path ignores the chat keyboard. Large text uses a compact companion dock and accessible navigation labels. Scroll-state updates occur only at section/companion boundaries rather than for every dragged pixel.
- Guided and welcome conversations position the new assistant bubble after layout, before any long review/checklist. Main chat follows replies unless the user is browsing history, and offers a latest-message button.
- Follow-up buttons stay adjacent to their question before document review panels. Onboarding keeps the keyboard for consecutive text questions and gives Skip a full-width 44-point target. The form editor keeps Save visible below its scrolling fields, independently of system toolbar overflow.
- At accessibility text sizes, the path uses a compact year/section header and side-by-side icons with full-sized text. Controls retain 44-point targets; decorative/control symbols keep bounded sizes. Focus has an opaque full-screen surface with the selected context pinned below its header. Inline contact maps retain zoom and marker selection while one-finger vertical drags remain for the conversation; this map behavior was compile-checked without a live navigation request.
- Final compile-only simulator check passed. The 38 Foundation-only regression checks passed; core record/state logic was unchanged by this UI work.
- Seven distinct UI checks passed in focused runs: saved care steps/form-library return, both companion edges, discharge source → prefilled form → persistent Save, year/outlook navigation with the correct banner and keyboard return position, main chat input/return, largest text size with entry preview/context, and welcome through both optional permission choices. The first four passed in `artifacts/TestResults/20261105-214727.xcresult`; the final three passed together with a clean `TEST SUCCEEDED` in `artifacts/TestResults/20261105-215442.xcresult`. A final stronger main-chat check asserts the exact typed message and enabled Send button and passed cleanly in `artifacts/TestResults/20261105-215827.xcresult`.
- Earlier screenshots exposed oversized navigation at maximum text size and path content showing through the Focus fade; both were corrected. Actual final large-text path and opaque chat screenshots were exported and inspected. Welcome's first answer is also explicitly checked before advancing; its profile input now uses a stable single-line field with keyboard Submit support. All records used in UI testing were synthetic and in memory. No live map lookup or paid model request was made.

## Labeled buttons, half sheets and glass

- Every compact path disk now has a visible wrapped title, date and multi-entry count. Generic multi-entry days show actual entry titles (two at normal sizes, one at accessibility sizes); underlying records and grouping are unchanged.
- Entry/day/source/settings previews use native medium and large detents. The accessibility layout and longer form/document workflows start large. Shared sheets have rounded corners, a grabber and frosted backgrounds; Reduce Transparency uses an opaque background.
- Navigation pills, overflow, chat controls, context and input use native Liquid Glass on iOS 26+, with regular-material fallback on iOS 18. Increased contrast and Reduce Transparency give controls opaque surfaces.
- Simulator build passed. Three focused UI checks passed cleanly in `artifacts/TestResults/20261105-220439.xcresult`: actual typed chat input/return, half-sheet initial position and expansion, and largest-text entry/context navigation. The half-sheet check also passed cleanly in English/dark mode in `artifacts/TestResults/20261105-220740.xcresult`, including an actual entry-based button label. Simulator appearance was restored to light. Light and dark screenshots were exported and inspected; previews are under `artifacts/Previews/glass`.

## Chat button and layout repair

- Replaced the moving one-pixel scroll marker with stable message-row targets and viewport-size updates. Browsing history pauses following; the latest-message control returns to the current reply. Guided and welcome transcripts also use real row bounds.
- Assistant text uses the full bubble width; avatar/read-aloud controls sit in its header. The composer is wider, attachments/examples/forms are accessible in More, and the initial shortcuts stop repeating after each message. Buttons have explicit padded hit regions. Glass is a noninteractive background behind controls; decorative borders do not take touches.
- Reopening resumes the latest online/local discussion and draft instead of appending an unrelated appointment invitation. Local reply actions and case choices are restored. Sending validates before clearing input; retrying does not erase a separately typed draft. Answered choices are hidden during pending/failed requests.
- Seven controller/API tests and four UI workflows passed cleanly in `artifacts/TestResults/20261105-225636.xcresult`: care flow, actual answer-button edge taps, error/retry with draft retention and online resume, typed chat/return, and largest text size. Stronger offline draft/conversation resume and online retry checks passed again in `artifacts/TestResults/20261105-230430.xcresult`. A DEBUG-only transport activated by both `--uitesting` and `--chat-ui-fixture` supplies deterministic local replies and a failure; it never contacts the server, reads real credentials or requests GPS. Release and ordinary launches use the existing service.
- Final glass rendering separates the decorative surface from editable text/icons, with noninteractive decorative borders. The typed-chat/local-resume check and largest-text check passed again in `artifacts/TestResults/20261105-230639.xcresult`; the final compact accessibility toolbar passed in `artifacts/TestResults/20261105-231039.xcresult`. Final screenshots were inspected and saved under `artifacts/Previews/chat-repair`.

## User-facing wording

- Removed remaining demo/prototype labels from chat prompts, access settings, profile descriptions and shared path context. Saved German/English guided-chat prompts and the bundled discharge-letter filename use neutral presentation text. Original source quotations, PDFs, record metadata and draft/booking/coverage statuses remain intact.
- Updated local PHP reply/error templates and background confirmation wording. Server deployment is separate from these workspace changes.
- Simulator build, localization syntax, all 38 path checks and 129 backend/HTTP checks passed. Six onboarding/form journey tests and both discharge/form and path/half-sheet UI checks passed in `artifacts/TestResults/20261105-231711.xcresult`.

## Conversational onboarding

- Added a greeting with a **Hi** reply, two separate introduction/terms messages and a readable terms sheet. Version/date of acceptance and a persistent terms-message link are saved with the local conversation. Profile questions use shorter German/English copy; profile data remains excluded from online chat.
- Birth date uses a native picker. One address interaction supports real Apple Maps completions/resolution or manual entry, then stores separate street/house/postcode/city/country fields for form reuse. Earlier saved progress still uses its original field indices; entering a full address skips the remaining address questions.
- Phone/email formats are validated before sending. The native insurance input limits typing and paste to ten ASCII digits, retains leading zeroes and reports its count. Each question gets a new input identity; stale keyboard updates cannot overwrite the next answer. Transcript following accounts for keyboard/viewport changes, with suggestions inside the scrollable conversation. Large text uses a compact header.
- Final simulator build, localization syntax and 38 path checks passed. Eight onboarding/form unit checks plus English largest-text terms/date and live MapKit resolution checks passed in `artifacts/TestResults/20261105-233751.xcresult`; its earlier numeric-input UI failure was corrected and rerun. The full German onboarding, date picker, invalid/valid contacts, visible ten-digit limit/compact input and optional permissions passed cleanly in `artifacts/TestResults/20261105-234714.xcresult`. The keyboard/active-address-question check and live suggestion selection passed cleanly in `artifacts/TestResults/20261105-234503.xcresult`. Inspected screenshots are under `artifacts/Previews/onboarding`.

## Compact path and latest-entry shortcuts

- The default supplied path presents 15 selected days instead of 208; source records, grouped details, open tasks, personal additions and all five outlook days remain available. The Sections menu switches between compact and full history. Topic palettes now color the raised faces, shadows and symbols in light/dark appearance; the current marker remains separate from entry type/status.
- Tapping the green section banner jumps to the latest recorded day or personal undated entry, excluding future dated outlook items. A native scroll-delegate bridge intercepts the system status-bar shortcut, forwards SwiftUI's other callbacks and disables itself while chat is active.
- Simulator build, localization syntax, 38 source checks and all 16 path unit checks passed. Unit coverage includes the 15-day projection, retained personal/open entries, latest target, status-bar interception, delegate forwarding and restoration. The existing section/chat-position and largest-text UI workflows passed in `artifacts/TestResults/20261105-235626.xcresult`. The system-tap UI attempt on Duo could not verify its side-mounted system rail; the standard iOS 27.0 simulator stalled before tests and was shut down. A separate native-status-bar UI test remains available for a working standard iPhone simulator/device.
- The compact count, header-to-latest action and both full/compact menu switches passed cleanly in `artifacts/TestResults/20261106-000423.xcresult`.

## Chat outcome controls and path states

- Stored appointments/tasks have local chat cards with attended/not-attended/unrecorded and completed/not-done/open choices. Explicit buttons update the existing records, append local conversation turns, retain drafts and allow corrections. Appointment reports preserve booking status and provenance; future-day attendance cannot be recorded. The overview works locally with online chat enabled, while booking/symptom requests retain intake routing. Case summaries do not inherit unrelated entry controls.
- One shared progress calculation drives path/day/chat status: unrecorded or unfinished items remain grey even after time passes. Explicit negative reports turn red only after the appointment time or the task's calendar day is past; completed items have a checkmark and topic palette. Grouped days prioritize missed, then pending, then completed actionable entries. Cancelled entries remain grey. Task changes also reconcile pending reminders.
- Final simulator build, localization syntax and all 38 source checks passed. All 68 unit checks, online answer/retry/draft UI, care/form UI and largest-text UI passed in `artifacts/TestResults/20261106-002844.xcresult`. Its tracking-flow failure was a test helper that scrolled past the target; the recorded state/colour/draft checks completed successfully. After making that helper choose scroll direction, the complete English tracking workflow passed cleanly in `artifacts/TestResults/20261106-003418.xcresult`: grey unknown status, missed appointment/red day, saved draft, reopened selection, attendance correction, negative task choice and both task completions/checkmarked day. Retained screenshots were inspected.

## Multilingual chat and document imports · 6 November 2026

- The working-tree simulator build passed, as did 85 unit tests and 38 offline path checks. A native check exercised all four challenge scenarios in German, English, Arabic and Turkish, and reopened all seven prefilled PDF templates.
- The supplied discharge report produced eight reviewable administrative steps. The three imaging reports produced source-linked explanations. The supplied Impfpass yielded nine administrations on eight dates. Reimporting preserved the count.
- Targeted simulator runs exercised the chat paperclip, report-to-task review, selected vaccination history, a German-device conversation in English, two case-linked form journeys, and the online transport fixture’s follow-up buttons, retry and draft restoration.
- The version 3 health endpoint responded. The PHP suite passed 110 backend checks and 19 HTTP checks with a mocked upstream. An authenticated live upstream response still requires a configured prototype client token.
