# Conversation and document extraction

The welcome conversation, reusable form profiles, PDF drafts and four guided use-case examples are local. They do not call the online chat, and are not included in its transcript or background payload. Welcome answers/progress and guided conversations persist independently in the SwiftData snapshot. Location and notification choices are offered as optional real iOS permission steps. A fresh location can be used for online provider navigation, native MapKit contact search or explicit local place-name lookup through Apple; it does not populate the applicant's postal address. PDF prefill uses deterministic reviewed mappings to the seven supplied blank templates, with no model extraction or invented medical/eligibility values.

The connected care and discharge cases extend this local path. `CasePreparation` stores selected applicant, sourced recommendations, reviewed document items and structured care-routing answers. `DischargeNavigationExtractor` recognizes only a small set of explicit phrases, retaining exact original quotes/page markers and requiring per-recommendation review. It does not infer recommendations from diagnoses, dose instructions or symptoms. PDF import retains the original bytes in the local snapshot, bounded to 5 MB/100 pages with extracted text bounded to 2 MB. Scanned documents without text have an explicit failure. This is not a general-purpose extraction model or a validated negation/clinical interpretation system.

A saved-case progress query is handled on-device before online submission. It uses live profile/checklist/draft/task state and offers the relevant case (or a disambiguation choice). A form saved through a case records its case and applicant association. Application-type choices remain review metadata; PDF selection boxes, legal declarations, medical sections and signatures are not automatically filled. Common-case authority routing is based on reviewed official sources and explicit pension/current Pflegegeld payer answers, with uncertainty/special cases left unresolved.

The local organizer and document extractor remain offline. Optional online navigation chat is available through a separately configured PHP endpoint. No OpenAI credential is included in the app; the user enters the prototype API token in chat settings and consents before online requests.

`LiveChatAPI` calls `https://sovi.elzahaby.at/?action=chat` (requires PHP version 3). `LiveChatController` owns a separate in-memory online transcript, cancellation, explicit retry and Keychain configuration. No automatic local path/document context is sent. The user may select up to four dated summaries in settings; synthetic entries retain that label, source references are validated, and inferred incident connections require confirmation. Optional CoreLocation positions are requested only in the foreground on send; GPS stays on the PHP server and explicit destinations take precedence. A relative's location is not assumed to equal the user's.

OpenAI extracts intent/evidence, not medical recommendations or provider URLs. PHP selects short fixed German/English/Arabic/Turkish copy, one follow-up at a time, answer buttons and free-text entry. Sourced Vienna physician candidates are matched by service/distance and displayed with MapKit pins; official directories cover other services/regions. Insurer contracts and availability remain unverified. Broad primary-care/care-advice navigation is not diagnosis or validated triage. See `apps/backend/README.md` for source, coverage and deployment details. Local API tests use mocked responses; no paid/clinical validation is implied.

## Replaceable interfaces

`CompanionService.respond(to:context:state:now:) -> CompanionResponse` returns display text, evidence references and at most one structured `CompanionAction`. `DemoCompanionService` recognizes German variants for summaries, documents, evidence, administrative drafts, new appointments/events/tasks, completion and stored-data questions. Counts and outstanding steps come from the passed snapshot. It has no write access to `SoviStore`.

`PlanExtractor.extract(document:anchor:calendar:) -> [PlanProposal]` produces versioned review proposals and exact `EvidenceReference` passages. `DemoPlanExtractor` recognizes only supported synthetic fixture content; unknown input and unrelated C yield no care plan. B's vague medication instruction produces clarification only. A is bounded and complete. Relative dates are substituted once using the persisted fixture epoch/time zone. Fixture templates live under `Resources/Fixtures`.

`SoviStore.perform(AppCommand)` validates mutations, saves transactionally through SwiftData and publishes committed state. Both direct previews and conversational action cards open the same editors/commands. A conversation answer or extraction result cannot approve itself. Approval checks proposal identity, revision and pending status; repeated approval is idempotent. Medication creation additionally re-verifies the known fixture instruction independently of an injected extractor. Source passages stay separate from user-edited labels.

Documents are untrusted text. No instructions from a document can enable permissions, submit anything, call services, run code or bypass review. Exact demo matching is not a general safety system.

## What real AI would still require

- A separately configured backend/service adapter with no provider credential shipped in the iOS bundle.
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

The supplied test vaccination PDF is a separate, manually checked source. `VaccinationPass.swift` loads nine typed records with exact vaccine/date/batch fields and page-linked evidence, replaces only the 32 original vaccination placeholders, and marks the one-time demo update in the versioned snapshot. The original PDF remains available through PDFKit. Its different test identity is shown explicitly; it does not change the current profile or imply a real patient merge. No generic vaccine extraction, clinical schedule, eligibility or booster prediction is implemented.
