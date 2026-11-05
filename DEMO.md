# Sovi: the 33-year example path

## Four guided use-case demonstrations

On first launch, Sovi welcomes the user in a conversational screen. Enter fictional details or skip questions. **Später** completes the welcome without requiring any answers. All answered turns remain stored and can be reopened through settings → **Willkommensgespräch**. The final two steps offer location and notification access through the real iOS prompts; declining either continues normally. The profile is separate from the supplied fictional history and is never automatically shared with OpenAI.

Tap Sovi → **Gemeinsam starten**. These four examples are bounded local workflows; they do not require backend credentials:

1. **Hilfe für meine Mutter** → **Beides** → **Wien**. Continue with **Erster Antrag** → **PV** → **Meine Mutter selbst** → **Ja, Unterlagen sind vorhanden**. Review the identified PV route for Pflegegeld and FSW route for Vienna home support. Select or add a separate applicant profile for the mother. Check the conditional document list, open a case-linked form, review its prefilled personal details, and save/export the draft. The selected first-application/increase choice is stored for review; the matching box in the PDF is still marked personally. Save the proposed tasks explicitly, mark progress, and reopen it. SVS/BVAEB answers lead to their official forms rather than using the included PV template. Unknown/special-case answers keep responsibility unresolved. Other places use regional care advice; the FSW template is only offered for Vienna support.
2. **Nach dem Spital** → **Fiktiven Beispielbrief verwenden** → preferred appointment time. This imports an actual two-page synthetic PDF through the same reader as **Brief importieren**. Review the page-2 quotes and use **Im Original ansehen** to compare them with the retained PDF. Press **Quelle geprüft · diesen Schritt vorbereiten** for each recommendation you want to adopt. Select the applicant, open the Kur/Reha form and save its case-linked draft. Save the source-linked tasks; opening a task retains the exact document evidence. A supplied text-bearing PDF or UTF-8 file can use the same route. Supported literal phrases are deliberately limited; symptoms, diagnoses and unsupported wording do not produce a recommendation. Photo/scanned-PDF OCR and broad clinical document understanding remain outside this demo.
3. **Etwas für meine Gesundheit tun** → **Vorsorge**, **Bewegung** or **Ernährung**. Save a small checklist and open the official service page. Bewegt im Park is seasonal; no currently available class is fabricated. Vorsorge can open native nearby contact search with current location or a typed town; no individual risk assessment or verified VU contract is claimed.
4. **Angebote für mein Kind** → age in years → **Vorsorge**, **Familienberatung** or **Bewegung**. Show the selected official information and save the preparation steps. No vaccination or examination schedule is inferred. Preventive-care contacts can be searched with MapKit; availability and insurance require confirmation.

Saved steps appear in **Eigene Schritte**, with no invented deadline. Open a step → **Vorgang öffnen** to resume the same example. The prototype keeps one saved demonstration per scenario; repeated saving does not duplicate tasks.

After closing either case, ask Sovi **Was fehlt noch für den Antrag meiner Mutter?**, **Wie geht es mit meinem Reha-Antrag weiter?**, or **What is missing for my application?**. The main chat answers from saved state and opens **Vorgang fortsetzen**; when both cases could apply, it asks which one. This works locally with online chat enabled and never transmits the case PDF or applicant profile to OpenAI. Checkmarks mean the user has reviewed/prepared an item, not that an authority has accepted it. No request is submitted by the app.

For the discharge demo, the downloadable/importable sample is `apps/ios/Sovi/Resources/Fixtures/demo-discharge-navigation.pdf`. All names and recommendations in it are fictional. The sample, its extracted text, source page and resulting task references remain inspectable.

The responsible rehabilitation carrier is deliberately left open in the PDF and appears in the checklist for clarification with the practice. A saved health insurer is not sufficient to fill this field. Native PDF page references come from importer-recorded page ranges; text merely mentioning another page does not establish a source page.

## Reusing details in the supplied forms

Open **Profile und Formulare** in chat or settings. Add/edit a fictional applicant, including optional bank/contact details, and select that person before opening one of the seven templates. Review the prefilled text, edit missing text fields, save the draft, inspect **PDF prüfen**, and use **PDF-Entwurf teilen** for a real interactive PDF. The German source form and its instructions are retained. Checkboxes, declarations, signatures, institution confirmations and clinical sections are not completed automatically. The hospital-only accident rehabilitation form only receives patient identity/contact details.

Drafts are stored separately by person and form; changing the profile does not overwrite an existing draft. Deleting local data clears profiles, welcome and scenario histories, form drafts and owned temporary exports. Copies shared outside the app cannot be recalled. All data in a presentation should be fictional.

The default fixture is the supplied **synthetic male, born 12 March 1993**, aged 33 at **5 November 2026, 09:00 Europe/Vienna**. It is not the user's health history. All historical dates and future plans belong to this fixed example snapshot.

## Load the updated example

Fresh installs seed it once. Existing 33-year demo installations receive the one-time vaccination update on the next launch, keeping their other progress and drafts. Unrelated older installations keep their data: use the top-right overflow → **Pfad zurücksetzen** → confirm replacement to load the full updated example. This is intentionally separate from deleting local data. Ordinary relaunches never reseed or shift the dates.

## Walkthrough

1. The app opens at **Mein Tag · 05.11.2026**, with a green current-day disk, HEUTE pointer and Sovi just below it, before the next steps. The path remains line-free. The small date identifies each icon; tap for its title and details; there are **208 daily buttons and 305 individual entries**.
2. The current button has **three halo segments**. Tap it to see **Physiotherapie**, **Kostenerstattung**, and **Vorsorge**. Each segment counts one entry, not progress, attendance, doses or health. A single-entry day has no segmented halo.
3. Open **Physiotherapie**: session 5 of 6 is scheduled for 16:00 in the fictional scenario. It starts with attendance unrecorded. A passed date does not change attendance. Edit attendance only with the explicit local editor. The four earlier documented sessions remain separate from this appointment and from medical recovery.
4. Open **Kostenerstattung**. The entry links the synthetic text passages for the 1 October therapy order, 29 October invoice and 30 October payment. Open **Entwurf öffnen** for an editable draft with missing fields. Export is a real text file; it remains **Entwurf · nicht eingereicht**. There is no reimbursement promise, verified amount or submission.
5. Open **Vorsorge** → **Anamnesebogen öffnen**. Save some fictional notes, leaving unknown answers blank. The **Anamnese** reminder on **23.11.2026** opens this same draft and task. Completing or reopening either reference updates their shared task state, while both day entries and all halo segments remain present.
6. In **Ausblick**, open the planned therapy session on 12 November, arm follow-up on 19 November, preparation on 23 November, check-up on 24 November and results discussion on 1 December. These are plans, not completed treatments or available results. The separate medication-list preparation does not make the historical DEMO-A plan current.
7. Scroll upward to historical years. Use **Abschnitte** to jump to any year, **Ausblick**, or saved **Eigene Schritte**; **Heute** returns to the current day. The pinned green banner follows the visible section; inline headings mark every boundary. These are orientation, not collapse controls. All records stay visible as you scroll. In **1993**, see birth, screening, insurance and pediatric records; **Geburt** has three entries. Keep scrolling through the other years for school, dental, vaccination, eye, check-up and self-reported infection episodes. No missing records become duties or invented diagnoses.
8. Tap a single-entry day: its detail opens directly. Tap a multi-entry day: choose one short sub-entry from its list. Opening alone changes no task, reading, attendance, vaccination or medication fact. A reading marker is a separate local flag.
9. Source actions show exact passages in the bundled synthetic text, with the original P-number and entry number. The named clinical documents are proposed fictional source types; no scans or ELGA records are attached. Public Q0–Q9 references are background context, not proof of this person's history. Episode links connect the actual listed follow-ups without creating duplicates.
10. Historical medication prescriptions, dispensing, intake and plan-end records stay separate. The new default scenario creates **zero medication schedules** and no automatic medication reminders. No dose is guessed from this text.
11. Tap Sovi or **Sovi fragen** on an entry. Focus keeps the selected sub-entry as explicit context. Ask **Was steht heute an?**, **Was ist noch offen?**, or **Warum steht das auf meinem Weg?**. Answers use the stored current-day entries, unique open tasks and recorded therapy attendance. Task-completion messages still require explicit review. Close Focus to return to the same path position.
12. Add or edit a local appointment through Sovi. Dated entries regroup by their actual calendar day; entries on the same day share one button. Undated manual steps stay in **Eigene Schritte** without an invented deadline. A local entry is not a provider booking.
13. Relaunch normally to verify progress and drafts persist. **Alle Daten löschen** leaves an empty path across relaunch. Only the separately confirmed **Pfad zurücksetzen** restores the fixed example. Shared copies outside the app cannot be recalled.

## Vaccinations from the supplied test PDF

The current demo contains **nine vaccination records across eight dates**. They replace all 32 vaccination placeholders from the original text. The path now has **208 day buttons, 305 entries and 67 multi-entry halos**. All other 296 original records remain unchanged.

| Date | COVID-19 | Influenza |
| --- | --- | --- |
| 3 June 2021 | Dose 1 | |
| 8 July 2021 | Dose 2 | |
| 17 November 2021 | | Dose 1 (PDF page 2) |
| 9 December 2021 | Dose 3 | |
| 4 December 2022 | Booster | |
| 22 November 2023 | | Booster |
| 6 November 2024 | | Booster |
| 3 November 2025 | Booster | Booster |

Browse to **3 November 2025 → Impfungen**. Its two halo segments open COVID-19 and influenza separately. Each entry shows the documented product, dose label, batch, PZN, provider, location, responsible person, setting/program when stated, and registration time. The two entries on this date have no stated administration time; the 14:02/14:03 registration times are not substituted for it. Seven other entries preserve their documented time and UTC offset.

Open **Warum steht das hier? → Impfpass.pdf → PDF öffnen** to inspect the source page. The unchanged two-page test PDF, native extracted text (only invisible NUL characters removed), and manually reviewed transcription are in `Resources/Fixtures/vaccination-pass-2026.*`. This is support for this supplied example, not a general vaccination-document extractor. Reimporting its native text does not duplicate entries.

The PDF's test profile is born in 1987 and differs from the 33-year example. The original PDF retains the separate test identity; the path keeps its birth date and other history. The interface shows concise record fields, with provider/registration details under **Weitere Angaben**. The update creates no future booster, task, appointment, medication plan or reminder. Ask Sovi **Welche Impfungen gibt es?** to read the stored counts or open a selected record's source. No protection assessment or next vaccination date is derived.

## Sovi on the edge

The screenshot reference informs the winding arrangement, round raised buttons and section banners. The continuous path keeps every year open and has no connecting line.

At the current day, Sovi's bubble mentions the next eligible local entry. In the fixed example at 09:00, this is **Physiotherapie at 16:00**. Browse older records until Sovi leaves the viewport: the same character peeks up from the bottom in reserved scroll space, leaving records reachable. Browse ahead past its position: it peeks from the top. Tap either the bubble or the character to open Focus with that appointment/task selected; closing returns to the same scroll position.

The bubble reads confirmed appointments with unrecorded attendance and open dated tasks, through the next 30 calendar days in the path's time zone. Cancelled appointments, request drafts, recorded attendance, completed/cancelled tasks, duplicate task references and overdue/undated entries do not become upcoming prompts. If nothing qualifies, Sovi asks **„Wie läuft’s bei dir?“**, opening a conversation without an old entry attached. The fixed example uses its documented snapshot time; ordinary local data uses the current clock. The bubble makes no status changes and sends no notifications.

## Optional document-extraction demonstration

The earlier A/B/C fixtures remain available through Sovi → **Ich habe einen Entlassungsbrief.** They are separate synthetic extraction examples. A creates organizational proposals and a bounded fictional schedule only after review; B creates clarification without a schedule; C and unknown text create no invented care plan. Approved new steps appear on the same path. They do not silently replace the 33-year example or constitute real medical guidance.

## Checks

Run `./scripts/check-ios.sh` for compilation and `./scripts/check-life-path.sh` for the Foundation-only scenario checks (no simulator). Native XCTest/UI smoke suites are included for your own simulator run. See `docs/VALIDATION.md` for actual results.

## Interface copy

The app omits demo banners, profile/snapshot captions and repeated explanatory paragraphs. Sovi uses short responses. Controls retain essential local-action scope, missing-field prompts, permission errors, and destructive confirmations. Known stored fixture labels are mapped for display; original quotes, PDFs and user-entered text remain intact. Earlier assistant messages containing prototype scaffolding are omitted from the visible conversation history without deleting the stored conversation.

The compact path uses neutral gray historical/future disks, a green current-day disk and a smooth curve. Gray entries are fully tappable. The four header counts represent appointment entries, documents, vaccinations and open tasks; full names and values remain available to VoiceOver. Accessibility sizes or the straight-path preference show full labels.
