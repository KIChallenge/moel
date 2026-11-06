# Sovi: the 33-year example path

## Four guided use-case demonstrations

On first launch, Sovi introduces itself. Tap **Hi**, open the short **Nutzungsbedingungen**, then **Akzeptieren** to continue; the acceptance version and date are saved locally. First and last name are separate conversational questions. Birth date uses a date picker; the address is one question with Apple Maps suggestions and a manual option (`Straße Hausnummer, PLZ Ort`). A selected address populates the separate fields needed by forms. Phone/email formats are checked before sending, and the insurance input accepts at most ten digits, including paste. Enter fictional details or skip profile questions. **Später** completes the welcome without requiring answers. The history, including its terms link, can be reopened through settings → **Willkommensgespräch**. The final two steps offer location and notification access through the real iOS prompts; declining either continues normally. Address searches go to Apple Maps; the profile is separate from the supplied fictional history and is never automatically shared with OpenAI.

Tap Sovi → **Gemeinsam starten**. These four examples are bounded local workflows; they do not require backend credentials:

1. **Hilfe für meine Mutter** → **Beides** → **Wien**. Continue with **Erster Antrag** → **PV** → **Meine Mutter selbst** → **Ja, Unterlagen sind vorhanden**. Review the identified PV route for Pflegegeld and FSW route for Vienna home support. Select or add a separate applicant profile for the mother. Check the conditional document list, open a case-linked form, review its prefilled personal details, and save/export the draft. The selected first-application/increase choice is stored for review; the matching box in the PDF is still marked personally. Save the proposed tasks explicitly, mark progress, and reopen it. SVS/BVAEB answers lead to their official forms rather than using the included PV template. Unknown/special-case answers keep responsibility unresolved. Other places use regional care advice; the FSW template is only offered for Vienna support.
2. **Nach dem Spital** → **Fiktiven Beispielbrief verwenden** → preferred appointment time. This imports an actual two-page synthetic PDF through the same reader as **Brief importieren**. Review the page-2 quotes and use **Im Original ansehen** to compare them with the retained PDF. Press **Quelle geprüft · diesen Schritt vorbereiten** for each recommendation you want to adopt. Select the applicant, open the Kur/Reha form and save its case-linked draft. Save the source-linked tasks; opening a task retains the exact document evidence. A supplied text-bearing PDF or UTF-8 file can use the same route. Supported literal phrases are deliberately limited; symptoms, diagnoses and unsupported wording do not produce a recommendation. Images and scanned pages use on-device text recognition. Review the original before accepting a step.
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

Fresh installs seed it once. Existing 33-year demo installations receive the one-time vaccination update on the next launch, keeping their other progress and drafts. Unrelated older installations keep their data: open **Einstellungen** beside **Abschnitte** → **Pfad zurücksetzen** → confirm replacement to load the full updated example. This is intentionally separate from deleting local data. Ordinary relaunches never reseed or shift the dates.

## Walkthrough

1. The app opens at **Mein Tag · 05.11.2026**, with **Heute** beside the date and Sovi just below the button. The compact path shows **15 daily stops**: selected milestones, recent steps and the five outlook days. Personal additions and unfinished tasks always remain visible. Each raised button has a topic color, title and date; generic multi-entry days show the first two distinct entry titles. **Abschnitte → Alle Einträge anzeigen** exposes all **208 days / 305 entries**; **Kompakter Verlauf** returns to the shorter view.
2. The current button has **three halo segments**, one per entry. Tap it to open a matching card showing **Physiotherapie**, **Kostenerstattung**, and **Vorsorge**. Choosing an entry highlights its arc. A single current or selected entry has a continuous ring.
3. Open **Physiotherapie**: session 5 of 6 is scheduled for 16:00 in the fictional scenario. It starts with attendance unrecorded. A passed date does not change attendance. In Sovi chat, use **Teilgenommen**, **Nicht teilgenommen** or **Noch offen**; the local editor remains available too. Reports never change booking confirmation or source evidence. The four earlier documented sessions remain separate from this appointment and from medical recovery.
4. Open **Kostenerstattung**. The entry links the synthetic text passages for the 1 October therapy order, 29 October invoice and 30 October payment. Open **Entwurf öffnen** for an editable draft with missing fields. Export is a real text file; it remains **Entwurf · nicht eingereicht**. There is no reimbursement promise, verified amount or submission.
5. Open **Vorsorge** → **Anamnesebogen öffnen**. Save some fictional notes, leaving unknown answers blank. The **Anamnese** reminder on **23.11.2026** opens this same draft and task. Completing or reopening either reference updates their shared task state, while both day entries and all halo segments remain present.
6. In **Ausblick**, open the planned therapy session on 12 November, arm follow-up on 19 November, preparation on 23 November, check-up on 24 November and results discussion on 1 December. These are plans, not completed treatments or available results. The separate medication-list preparation does not make the historical DEMO-A plan current.
7. Use **Abschnitte** to jump to a visible year, **Ausblick**, or saved **Eigene Schritte**; **Heute** returns to the current day. Tap the system status bar to return to the latest recorded day (future outlook dates are excluded; a new undated personal entry can be the latest). Enable **Alle Einträge anzeigen** to browse every historical year. All source records remain stored and linked, including entries omitted from the compact overview.
8. Tap a single-entry day to read its summary and use its actions directly on the path. For a multi-entry day, choose an entry within the same card. **Details** opens the full record. Close the card or tap outside it to return to the same place.
9. Source actions show exact passages in the bundled synthetic text, with the original P-number and entry number. The named clinical documents are proposed fictional source types; no scans or ELGA records are attached. Public Q0–Q9 references are background context, not proof of this person's history. Episode links connect the actual listed follow-ups without creating duplicates.
10. Historical medication prescriptions, dispensing, intake and plan-end records stay separate. The new default scenario creates **zero medication schedules** and no automatic medication reminders. No dose is guessed from this text.
11. Tap Sovi or **Sovi fragen** on an entry. Focus keeps the selected sub-entry as explicit context. Ask **Was steht heute an?**, **Was ist noch offen?**, or **My appointments** for local cards with real stored statuses, even with online chat enabled. Use **Erledigt / Nicht erledigt / Noch offen** for tasks. Buttons save the explicit answer, append it to local history and preserve an unsent draft; choices remain available to undo it. Pending/unrecorded items stay grey. Explicitly missed past appointments or past-day tasks turn red with an X and text; completed items regain their topic color and a checkmark. A day with any missed item is red; otherwise unfinished items keep it grey until all actionable items are complete. **Was steht als Nächstes an?** returns to the overview. Booking and symptom requests still use intake. Opening a card or letting a date pass never records an outcome. Close Focus to return to the same path position.
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

The path has round raised buttons and inline year headings. Settings sit beside the section menu.

At 09:00 on the example day, Sovi mentions **Physiotherapie at 16:00**. After 16:00, tap Sovi to answer whether you went. Choose **Ja, ich war dort**, **Nein, ich war nicht dort**, or **Später antworten**. You can also type your answer. The chat saves the question and your answer together with the appointment outcome. Answering later keeps the entry open and postpones the question until the next local day.

Sovi uses the current time to choose the most recent confirmed appointment with unknown attendance from the past 30 days. Otherwise the bubble shows an upcoming appointment or open task within 30 days, or asks **„Wie läuft’s bei dir?“**. Browse older entries to bring Sovi to the bottom edge, or browse ahead to bring it to the top edge. Tapping either opens the same conversation. Closing chat returns to that point on the path.

## Optional document-extraction demonstration

The earlier A/B/C fixtures remain available through Sovi → **Ich habe einen Entlassungsbrief.** They are separate synthetic extraction examples. A creates organizational proposals and a bounded fictional schedule only after review; B creates clarification without a schedule; C and unknown text create no invented care plan. Approved new steps appear on the same path. They do not silently replace the 33-year example or constitute real medical guidance.

## Checks

Run `./scripts/check-ios.sh` for compilation and `./scripts/check-life-path.sh` for the Foundation-only scenario checks (no simulator). Native XCTest/UI smoke suites are included for your own simulator run. See `docs/VALIDATION.md` for actual results.

## Interface copy

The app omits demo banners, profile/snapshot captions and repeated explanatory paragraphs. Sovi uses short responses. Controls retain essential local-action scope, missing-field prompts, permission errors, and destructive confirmations. Known stored fixture labels are mapped for display; original quotes, PDFs and user-entered text remain intact. Earlier assistant messages containing prototype scaffolding are omitted from the visible conversation history without deleting the stored conversation.

The compact path uses topic colors for historical entries, grey for pending actions, and red for explicitly missed actions. All entries are tappable. The four header counts represent appointment entries, documents, vaccinations and open tasks. VoiceOver reads the full names and values. Accessibility sizes or the straight-path preference show full labels.

## Path cards, detail sheets and glass

Above each disk, a one-word bubble describes what you can do, such as **Lesen** for information or **Auswählen** for a grouped day. Tap the bubble or the disk to open the same color-matched card. A pointer connects the card to the disk, above or below it depending on the available space. At larger text sizes the card scrolls independently of the path. Full records, sources and settings open in expandable sheets. Forms and longer workflows use a full-height presentation.

Today/Sections pills, the path settings button, chat header controls, selected context and message field use native Liquid Glass on iOS 26 and later. Older supported iOS versions use frosted material. Reduce Transparency and increased contrast use opaque control surfaces; text and record content retain readable backgrounds.

## Chat interaction

Messages use the full readable width, with read-aloud controls in the message header. The bottom field remains available for a free answer; attachments, forms, examples and a new online conversation are in **More / Mehr**. Initial example shortcuts disappear once a conversation begins, while the More menu remains available.

Reopening Sovi resumes the conversation and draft. New replies scroll into view using their actual row; browsing older messages pauses automatic following and offers a latest-message button. Pending/failed requests hide answered choices; Retry keeps a separately typed draft. Glass is drawn behind native controls.

## Attach a document and open its life event

Tap the paperclip in Sovi’s chat and select a PDF, plain-text file, or image. To try it without a file, choose **Mehr → Beispielbefund anhängen**. The example report was written on 16 October 2024 and records a visit on **14 October 2024**. Tap the event in Sovi’s reply to open that day on the path. The filename opens the saved document. Closing the document context returns to regular chat.

Text extraction, scan recognition, event matching and storage run on the device. Ask **Welche Ereignisse hast du gefunden?** to see the recorded dates for the selected document. Each event retains the passage that supplies its date and a page number when available. Attaching the same file again reuses its events. If the parser cannot establish an event date, the file stays in the chat for inspection. After returning to online chat, open **Anhänge in diesem Chat** to revisit the saved files and their event links.

The challenge’s imaging reports label outpatient visits separately from the report issue date. The discharge report labels the discharge date. Its follow-up requests remain available for review under **Mehr → Dokumente**. The eight tasks on pages 6 and 7 include home nursing, a rehabilitation application, a follow-up appointment and transport.

Compare a proposed step with its source page and select it to add an open task. A date printed as part of the instruction gives the task a calendar day. Steps whose timing remains open appear under **Eigene Schritte**. Opening the same report again preserves completed tasks. The rehabilitation action links to the Kur/Reha draft. Care allowance and home care go through the case questions about the responsible payer and region.

The reader uses labelled sections and explicit administrative instructions. It preserves the original wording for findings and conditions, explains recognized terms in the selected language, and leaves unsupported passages available for review in the original. Terms were checked against the Austrian Gesundheitsportal for [ultrasound](https://www.gesundheit.gv.at/labor/untersuchungen/ultraschall.html), [spinal regions](https://www.gesundheit.gv.at/krankheiten/koerper/bewegungsapparat/wirbelsaeule.html) and [compression](https://www.gesundheit.gv.at/lexikon/K/lexikon-kompression.html), NCI for [subcutaneous](https://www.cancer.gov/publications/dictionaries/cancer-terms/def/subcutaneous), [outpatient](https://www.cancer.gov/publications/dictionaries/cancer-terms/def/outpatient) and [lipoma](https://www.cancer.gov/publications/dictionaries/cancer-terms/def/lipoma), Gesundheitsportal for [fracture](https://www.gesundheit.gv.at/krankheiten/koerper/gelenkverletzungen/speichenbruch.html) and [hematoma](https://www.gesundheit.gv.at/lexikon/H/haematom.html), gesund.bund.de for [V. a.](https://gesund.bund.de/glossar/va), and MedlinePlus for [subluxation](https://medlineplus.gov/ency/patientinstructions/000524.htm).


## Import vaccinations from chat

Attach the Impfpass with the paperclip to add readable administrations to their recorded days. Tap the filename to inspect the person, products and source pages. Reattaching the same pass preserves existing path entries. For manual selection, open **Mehr → Dokumente**, choose the pass, select individual rows and tap **Impfungen zum Pfad hinzufügen**. Incomplete rows remain available in the original.

For a multilingual walkthrough, ask about help for a parent, preparing for discharge, prevention or services for a child in German, English, Turkish or Arabic. The chat chooses the language from the request or its language setting. When a form applies, select the applicant to prepare the draft. If the selected report has labeled personal details, **Person aus diesem Befund übernehmen** opens them for review before saving a new profile.
