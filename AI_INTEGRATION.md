# Conversation and document extraction

The welcome conversation, reusable form profiles, PDF drafts and four guided use-case examples are local. They do not call the online chat, and are not included in its transcript or background payload. Welcome answers/progress and guided conversations persist independently in the SwiftData snapshot. Location and notification choices are offered as optional real iOS permission steps. A fresh location can be used for online provider navigation, native MapKit contact search or explicit local place-name lookup through Apple; it does not populate the applicant's postal address. PDF prefill uses deterministic reviewed mappings to the seven supplied blank templates, with no model extraction or invented medical/eligibility values.

The care and discharge cases keep the applicant, document checklist, selected forms and reviewed recommendations in the local snapshot. The chat attachment reader accepts text, PDFs and single images. Scanned pages use on-device OCR and can be compared with the original. File imports are limited to 5 MB, PDFs to 100 pages, and extracted text to 2 MB. Report explanations cite the author’s findings, clarify familiar terms and identify supported administrative instructions. Each selected instruction creates an open task with its source passage and any explicit date. The insurer responsible for a payment or service is clarified in the guided case.

A saved-case progress query is handled on-device before online submission. It uses live profile/checklist/draft/task state and offers the relevant case (or a disambiguation choice). A form saved through a case records its case and applicant association. Application-type choices remain review metadata; PDF selection boxes, legal declarations, medical sections and signatures are not automatically filled. Common-case authority routing is based on reviewed official sources and explicit pension/current Pflegegeld payer answers, with uncertainty/special cases left unresolved.

The e-card scan posts the front and back as separate photos in the local welcome history. Sovi checks the sides and reads their fields on the device, then asks for review. Only the confirmed fields fill the profile.

The paperclip reads the selected file on the device. Dated encounters and recorded vaccinations create life events with the original passage and page. The attachment, events and receipt are saved together. When someone asks Sovi to explain a report, the device selects up to three short findings or documented next steps and filters identity fields. Only these passages and the language go to the report endpoint. Each returned sentence refers to a selected passage. The original file, e-card photos and profile stay on the device.

Navigation chat connects automatically through the hosted PHP endpoint. A restricted shared prototype token is supplied by the build through ignored Local.xcconfig and Info.plist; it is extractable from the app and suitable only for the controlled test group. The OpenAI key stays on the server. There is no end-user API setup, online toggle or language picker. The welcome terms explain chat processing. A short notice is shown to users who skipped them.

The mascot shows welcome, document, timeline and online replies together. SwiftData keeps the full displayed conversation and practice results locally, including drafts and unsuccessful sends. The chat API receives only a bounded recent context and up to four background entries the user selected. Switching topics or background keeps history. Only the explicit local-data deletion clears it. Practice coordinates and links survive relaunch. The device location used for the search is omitted from the saved reply.

OpenAI Responses chooses the next short question, reply buttons or search intent in German, English, Turkish or Arabic. PHP validates the action and supporting user quotes. A named service can be searched directly, and a symptom can lead to an offer that a plain yes accepts. Unrelated questions return to health navigation. The Vienna physician directory and native MapKit supply real practice records. The map and swipeable practice cards stay with their original reply. Contract-only requests lead to the official insurer search.

## Replaceable interfaces

`CompanionService.respond(to:context:state:now:) -> CompanionResponse` returns display text, evidence references and at most one structured `CompanionAction`. `DemoCompanionService` recognizes German variants for summaries, documents, evidence, administrative drafts, new appointments/events/tasks, completion and stored-data questions. Counts and outstanding steps come from the passed snapshot. It has no write access to `SoviStore`.

`PlanExtractor.extract(document:anchor:calendar:) -> [PlanProposal]` produces versioned review proposals and exact `EvidenceReference` passages. `DemoPlanExtractor` recognizes only supported synthetic fixture content; unknown input and unrelated C yield no care plan. B's vague medication instruction produces clarification only. A is bounded and complete. Relative dates are substituted once using the persisted fixture epoch/time zone. Fixture templates live under `Resources/Fixtures`.

`SoviStore.perform(AppCommand)` validates mutations, saves transactionally through SwiftData and publishes committed state. Both direct previews and conversational action cards open the same editors/commands. A conversation answer or extraction result cannot approve itself. Approval checks proposal identity, revision and pending status; repeated approval is idempotent. Medication creation additionally re-verifies the known fixture instruction independently of an injected extractor. Source passages stay separate from user-edited labels.

Documents are untrusted text. No instructions from a document can enable permissions, submit anything, call services, run code or bypass review. Exact demo matching is not a general safety system.

## What real AI would still require

- User-specific authentication and usage limits for a wider release.
- Explicit, granular user review of what document/chat data would leave the device, purpose, recipients and retention, including deletion and revocation behavior.
- Schema validation, evidence integrity checks against immutable source passages/page offsets, prompt-injection defenses, input/output limits and safe failure paths.
- An intended-purpose and privacy/security review before using real patient data; lawful consent/authority and caregiver relationships need their own product design.
- Source-grounding evaluation on representative Austrian organizational workflows, uncertainty handling, unsupported requests and incomplete/conflicting instructions. Factual eligibility or medical statements need appropriate reviewed sources; do not infer them from plausible model output.
- Durable command tokens, versioned proposals and auditability across any future network retries or concurrent editors. Keep application authorization separate from model suggestions.
- Production storage/migrations, export/data lifecycle, accessibility/localization, device permission and notification tests, and operational support. The current synthetic prototype is not clinical validation or official endorsement.

On-device recognition and speech playback are real native features, separate from the simulated companion. Speech recognition is used only if on-device recognition is available; no remote transcription fallback is allowed. Transcription must be reviewed as editable text before sending.

## Structured 33-year example

`LifePathSeed` loads the explicitly supplied structured fixture, not model-generated clinical history. `AppState.pathDays` groups typed records by Europe/Vienna calendar day. Original record categories and source assertions live in optional `LifeRecord` metadata, apart from mutable task/read/attendance state. Existing snapshots decode without this metadata and are preserved until explicit demo reload.

The questionnaire reminder links a canonical task ID and a shared `lifeDrafts` key. Companion summaries deduplicate that task and read actual attendance; 305 entries do not mean 305 completed tasks. The source's medication evidence is display-only and creates no schedule. Exact passages point to the bundled synthetic text, not invented attached scans. Public background links do not authenticate individual records.

The supplied test vaccination PDF is a separate, manually checked source. `VaccinationPass.swift` loads nine typed records with exact vaccine/date/batch fields and page-linked evidence, replaces only the 32 original vaccination placeholders, and marks the one-time demo update in the versioned snapshot. The original PDF remains available through PDFKit. Its different test identity is shown explicitly; it does not change the current profile or imply a real patient merge. For new imports, the reader parses labeled administration rows, presents the recorded holder and dates for review, and adds selected historical vaccinations with their original evidence. Updated copies with the same identifiable holder can supply a second source for a recorded vaccination.
