# Sovi prototype intake backend

Deploy **four files: `index.php`, `sovi.php`, `.htaccess`, and private `config.php`**. PHP 8.2+, cURL, Apache 2.4 with `.htaccess` overrides and `mod_rewrite`, outbound HTTPS to `api.openai.com`, and a writable private PHP temporary directory are required. No Composer, database, framework or cron job. `config.example.php` is the checked-in configuration template; `config.php` is ignored by Git.

`action=understand` extracts explicit requests. **`action=chat` (version 3)** adds short follow-ups, answer buttons, selected background and navigation. OpenAI writes the next short turn and suggests actions. PHP validates the structured response, the supporting user quotes and the destination. Unrelated requests return two localized health-navigation choices. Neither endpoint diagnoses, assesses clinical urgency, books or mutates the life path.

## Online chat in the app

Replace the hosted `sovi.php` with the current copy, retaining your configured `config.php`. Health must report **version 3**. The app uses `https://sovi.elzahaby.at/?action=chat`, the root of a dedicated API subdomain. Existing index/access rules remain compatible. The iOS build supplies the existing server `api_token` through `SOVI_CHAT_ACCESS_TOKEN` in ignored `apps/ios/Configuration/Local.xcconfig`; users start chatting immediately. `Configuration/Info.plist` expands this build value. Do not set it to the OpenAI key. A bundled shared token is extractable and only suitable for the controlled prototype group. Existing server authentication and global 10/minute, 200/day limits remain in force. Old device settings cannot disable the automatic connection or force a language override. Location sharing remains voluntary and is requested during onboarding; it can be revoked under Your data. The app saves the complete displayed history in local SwiftData. Only recent online turns are sent to the server. The explicit delete-local-data action clears the history.

- “I want a doctor's appointment” asks the doctor type or purpose, with suggested answers and **type another answer**. The composer always accepts free text. It does not assume a specialty or book anything.
- “My shoulder hurts” asks what support is wanted: assessment, daily support, a recommended service or guidance when unsure. This is navigation, not a clinical symptom questionnaire.
- “My mother has trouble moving” can lead to regional care advice or medical assessment. Before searching for another person, the chat asks whose location to use.
- Short replies and buttons support **German, English, Arabic and Turkish**. `locale=auto` detects language; the app always uses automatic detection. Other input languages can be understood with English reply fallback. Arabic uses right-to-left layout. Original directory facts and source quotes retain their language.
- In More → Share context, select up to **four** dated local summaries: ID, title, date, synthetic-demo flag. A local title filter finds older entries. Only these reviewed summaries are sent, never the whole path or documents. A possible link to an incident prompts confirmation, not a causal conclusion or automatic specialty choice. Demo data is labeled fictional. Changing the shared context preserves the conversation. The selection itself lasts for the current app session.

Once the user chooses a named service or primary care for initial assessment, PHP can return up to three physician locations from City of Vienna WFS (`ARZTOGD`). It filters specialty and sorts by straight-line distance where suitable GPS is available; a named place overrides GPS. Coverage is limited to Vienna and the implemented physician specialties. For supported services with no registry matches, iOS uses MapKit to find practices around the shared location or requested town. Dentistry uses native search and the official dental directory. Other service directories remain available. Contract-only requests use official verification instead of unverified local cards. No contract, available appointment or opening hours is invented.

Each reply keeps its own native **MapKit map** and horizontal practice carousel, including directions, attribution and retrieval time. Only public practice pins are saved with the reply. Directory-only answers have no guessed pins. A public Vienna dataset snapshot is cached in the server temporary directory for up to 24 hours; messages, background and GPS are not cached.

`POST /?action=chat` uses the existing token/consent/body/history/rate limits. `locale` accepts `auto`, `de`, `en`, `ar`, `tr`. Optional `background` contains at most four reviewed `{id,title,date,is_synthetic}` records; duplicate IDs and malformed/oversized entries are rejected. Output: `version:3`, `language`, `status`, `reply`, `choices`, `actions`, `providers`, `notice`, `sources`, `context_used`, `interpretation`, `search_area`. Choices with `opens_composer:true` open typing without sending a placeholder. GPS never enters the model payload; selected background is untrusted data, separate from user statements. Invented background references fail validation. A model-reported possible emergency bypasses ordinary follow-ups, but is **not a validated emergency detector**; users must not wait for chat in an emergency.

`POST /?action=report` accepts the response language, processing consent and up to three short finding excerpts. The app filters identity fields on the device. The server asks OpenAI to explain only what the passages say and validates their cited indices. Both OpenAI requests use `store: false`. Local tests mock the model. Release checks also exercise the hosted service with synthetic messages and locations.

## SiteGround setup

1. In **Site Tools → Devs → PHP Manager → PHP Version**, select PHP 8.2 or newer. Enable **Security → HTTPS Enforce** for the domain and use HTTPS for every API call, including the first request containing a token. Redirects cannot protect a token already sent over HTTP.
2. Create the local configuration if it does not already exist:

   ```sh
   cp -n apps/backend/config.example.php apps/backend/config.php
   php -r 'echo bin2hex(random_bytes(32)), PHP_EOL;'
   ```

   The second command generates a prototype access token. Keep it private. Do not replace an existing configured `config.php`.
3. In **`config.php` only**, put your OpenAI API key and generated token in the two empty fallback strings:

   ```php
   'openai_key' => getenv('OPENAI_API_KEY') ?: 'YOUR_OPENAI_API_KEY',
   'api_token' => getenv('SOVI_API_TOKEN') ?: 'YOUR_RANDOM_PROTOTYPE_TOKEN',
   ```

   Alternatively set those environment variables if your hosting configuration supports them. PHP does not automatically load `.env` files. Never put either secret in checked-in source or a browser script. The OpenAI key must never enter the iOS bundle. The restricted shared prototype token is supplied to controlled app builds through ignored Local.xcconfig.
4. Using SiteGround File Manager or SFTP, upload **`index.php`, `sovi.php`, `.htaccess`, and `config.php`** into a dedicated `public_html/sovi-api/` directory. Enable hidden-file display so `.htaccess` is included. On later code updates, update the three code/access files and retain your configured `config.php`. Do not upload tests, this README, `.env` files or backups. The preferred URL is **`https://YOUR-DOMAIN/sovi-api/`**, including the trailing slash. `index.php` and the older `sovi.php` URL both use the same authentication and validation; there is no POST redirect.
   Install this `.htaccess` **only in the API directory**, not `public_html` or a directory containing your website. Its allowlist intentionally blocks every path except the directory entry point, `index.php` and `sovi.php`.
   Prefer configuration outside the web root when possible: set the server environment variable `SOVI_CONFIG_FILE` to an absolute private path, such as `/home/customer/www/YOUR-DOMAIN/sovi-config.php`, and upload the config there instead. This path is server-controlled and cannot be supplied by a chat request. A missing or invalid configuration returns 503. Direct HTTP access to an adjacent `config.php` is denied by the supplied rules; PHP can still require it internally. Never use a `.txt`, `.bak` or `.json` file for secrets in the public directory.
5. Open the endpoint URL. It should return `{"status":"ok","service":"sovi-intake","version":3}`. This checks PHP/configuration reachability only; it does not verify credentials, cURL, model access or outbound networking.
6. Send the synthetic request below to test the configured OpenAI connection. This is a billable API request. If Apache strips `Authorization`, use `X-Sovi-Token: YOUR_TOKEN` instead.
7. Verify `https://YOUR-DOMAIN/sovi-api/config.php` and `https://YOUR-DOMAIN/sovi-api/.htaccess` return **403**, and the directory URL returns health JSON, not a file listing. Also upload a temporary `probe.txt` containing only `PUBLIC-PROBE`, check that its URL returns 403, then delete it. This tests static-file blocking without using a real secret. SiteGround's NGINX Direct Delivery can serve static files before Apache; for the API host, disable it in **Speed → Caching → NGINX Direct Delivery** if the static probe bypasses the rules, and clear existing caches before repeating the check. This setting can affect the whole site, so a dedicated API subdomain may be useful. If everything returns 500, inspect the hosting error log for an unavailable directive/module; do not remove the protections and continue with secrets in the public directory.

The default model is `gpt-6-luna`, configurable in `config.php` (or with `SOVI_OPENAI_MODEL` when using the supplied template). Your OpenAI project needs API billing and access to the selected model. The request uses Responses API Structured Outputs and `reasoning.effort: low`. Select a model supporting both. No automatic fallback, retries or web tools.

## Calling it from the mascot chat

The following example documents the original `understand` endpoint. The iOS online chat instead sends `action=chat` as described above, with consent, optional foreground GPS and individually reviewed background. Do not send the entire life path, documents or identifiers. Display returned text as plain text.

```sh
# Set SOVI_URL and SOVI_API_TOKEN in your local shell first.
curl --fail-with-body "$SOVI_URL?action=understand" \
  -H "Authorization: Bearer $SOVI_API_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{
    "locale": "de",
    "cloud_processing_consent": true,
    "location": {"latitude": 48.2082, "longitude": 16.3738, "accuracy_m": 25},
    "messages": [
      {"role": "user", "content": "Ich suche Physiotherapie mit ÖGK-Vertrag."}
    ]
  }'
```

`POST` defaults to `understand`; `GET` defaults to `health`. No other actions exist. Allowed body fields are `locale` (`de` or `en`, default `de`), `cloud_processing_consent` (literal `true`), `messages` (1–12 `user`/`assistant` messages), and optional `location` (GPS object or null). Limits: 4,000 UTF-8 **bytes** per message, 16,000 bytes of transcript, 32 KiB JSON body. Excess history is rejected, never silently truncated. If reducing history, ask the user to restate essential search criteria; do not supply an assistant-generated summary as user evidence.

GPS `latitude` and `longitude` must be JSON numbers in WGS84 decimal degrees, in [-90, 90] and [-180, 180]. Optional `accuracy_m` is a nonnegative number in metres. Strings, booleans, incomplete coordinates and unknown location properties are rejected with `invalid_location` (400). The client should send a fresh foreground location with each request, without requesting background tracking. If permission is declined or location is unavailable, omit `location` or send null; Sovi then asks for a town/postcode if needed. Freshness and permission are the client's responsibility; the backend does not verify GPS authenticity or reverse-geocode it.

For provider/pharmacy requests, `search_area` identifies the effective location. An explicit destination extracted from user text takes precedence over GPS. Otherwise `device_gps` supplies the search area without asking where the user is. A later “near me” request tells the extractor to clear the earlier named location. GPS is kept separate from quoted chat facts and **is not sent to OpenAI**. No external geocoder is called. Insurance/medical-handoff replies do not include a search area.

An illustrative response shape (actual extraction depends on the model):

```json
{
  "version": 2,
  "status": "ready_to_confirm",
  "reply": "Bitte prüfe die verstandene Anfrage unten. Du kannst sie vor der Suche korrigieren. Es wurde noch keine Einrichtung gesucht oder gebucht. Das Suchgebiet liegt rund um deinen geteilten Standort.",
  "interpretation": {
    "goal": "find_provider",
    "facts": {
      "service": {"value": "physiotherapy", "quote": "Physiotherapie", "message_index": 0},
      "need": {"value": null, "quote": null, "message_index": null},
      "location": {"value": null, "quote": null, "message_index": null},
      "insurer": {"value": "OEGK", "quote": "ÖGK", "message_index": 0},
      "payment_preference": {"value": "contract_only", "quote": "mit ÖGK-Vertrag", "message_index": 0},
      "language": {"value": null, "quote": null, "message_index": null},
      "accessibility": {"value": null, "quote": null, "message_index": null}
    }
  },
  "missing_fields": [],
  "search_area": {
    "source": "device_gps",
    "query": null,
    "coordinates": {"latitude": 48.2082, "longitude": 16.3738, "accuracy_m": 25}
  },
  "search_request": {
    "goal": "find_provider",
    "service": "physiotherapy",
    "need": null,
    "location": null,
    "insurer": "OEGK",
    "payment_preference": "contract_only",
    "language": null,
    "accessibility": null,
    "search_area": {
      "source": "device_gps",
      "query": null,
      "coordinates": {"latitude": 48.2082, "longitude": 16.3738, "accuracy_m": 25}
    }
  },
  "actions": [],
  "provider_search_performed": false
}
```

The client should:

- Append `reply` as the mascot message and send it back as an `assistant` message on subsequent turns. The server treats the whole transcript as untrusted data; client roles cannot inject API system instructions.
- For `needs_clarification`, show the single question and let the user answer. `missing_fields` lists all currently required fields.
- For `ready_to_confirm`, show editable facts. Require user confirmation **before a separate future provider-search implementation uses `search_request`**. It is a proposed filter, not a medical recommendation or an executed command. The server cannot enforce that future client's confirmation step.
- Use `search_request.search_area` as the canonical search location. Show “around your shared location” for `device_gps`; show `query` for `user_text` (whose `coordinates` are null). Do not infer a city from GPS, or mistake the null chat `location` fact for a missing GPS search area. Version 2 adds these fields; provider search is still separate.
- For `professional_guidance`, show the fixed professional-guidance text and call buttons. Sovi has not assessed urgency. The language model's category is not a validated emergency detector.
- For `understood`, show the captured insurance request for review. There is no eligibility answer or submission.
- On failure, retain the draft locally and offer an explicit retry. Never invent results or automatically repeat a paid request. A valid empty/default interpretation asks a clarification; refusals/incomplete/invalid responses are errors.

All seven fact objects are always present. Missing values have three null fields. Non-null facts must quote an actual **user** message using its zero-based index. Free-text values must occur inside the quote. Enum values can normalize wording (`ÖGK` → `OEGK`). This verifies source presence, **not semantic correctness**, the absence of contradictions, or medical appropriateness. User review and evaluation of actual model behavior are still needed.

## Prototype access and limits

`index.php` loads the existing endpoint instead of creating a second API implementation. `.htaccess` disables directory listings and content negotiation, blocks non-entry-point files (including config, dotfiles, source copies, nested tests and backups), rejects extra path segments and unsupported methods reaching directory rules, and caps request bodies at 32 KiB. When `mod_headers` is available it also adds no-cache, no-sniff, anti-framing and restrictive content-policy headers. PHP independently removes its `X-Powered-By` header. Token checks, input validation and request limits still apply to every chat entry point.

These rules reduce exposure; they are not a guarantee against compromise or a substitute for supported PHP, protected credentials and host-level security. Apache handles `TRACE` before per-directory rules; disabling it requires the host's `TraceEnable Off` setting, which cannot be placed in `.htaccess`. `.htaccess` requires Apache overrides to be enabled and does not protect files served by a different frontend. Keep secrets outside the public directory where practical, and check the live URLs after deployment.

The access token is a manually distributed shared prototype secret, not user authentication. An iPhone app cannot permanently hide a bundled shared token. Use it only with a small controlled group, rotate it if exposed, and replace this mechanism before wider distribution. The OpenAI key stays server-side. Configure a dedicated OpenAI project with suitable usage controls.

The endpoint creates one private temporary counter file, containing only time buckets and counts. Limits are **10 valid attempts/minute and 200/day across this endpoint/token**, including upstream failures. A missing/corrupt/unwritable limiter fails closed. Temporary-file cleanup or rotating the token resets counters: these limits are not a billing guarantee. Other sites using the same OpenAI key are not counted.

Native iOS requests need no CORS setting. For a browser prototype only, set `allowed_origin` in `config.php` to one exact origin, e.g. `https://demo.example.com`. Unknown origins are rejected; CORS is not authentication. The backend makes one upstream request with a 5-second connection timeout and 20-second total timeout.

Errors have `{"error":{"code":"…","message":"…"}}`. HTTP codes: 400 invalid input/consent, 401 invalid token, 403 denied browser origin, 404 unknown action, 405 method, 413 oversized body, 415 content type, 422 model refusal, 429 local limit (with `Retry-After`), 502 upstream/interpretation failure, 503 configuration/limiter unavailable, 504 upstream timeout. Upstream error bodies are never returned.

## Data handling and limits of this prototype

This PHP code stores no chat history or coordinates and does not log prompts, responses, credentials or IP addresses. GPS is used in memory for the proposed search area and returned to the client; only locale and transcript are sent to OpenAI. The client owns conversation state. It sends `store: false` to OpenAI; this does **not** by itself guarantee zero retention. SiteGround/webserver and OpenAI processing/log retention are separate from this code. Use synthetic conversations until the intended-purpose, hosting and personal-data arrangements described in the repository's `AI_INTEGRATION.md` are established. Consent flags and source quotes alone do not establish a lawful or clinically validated deployment.

The clinical handoff text is an organizational fallback, not triage. Chat v3 has a bounded public Vienna directory cache and an iOS adapter; there is no live pharmacy opening-hours feed, insurance verification or booking integration.

## Local verification

```sh
python3 scripts/check-backend.py
python3 scripts/check-backend-apache.py
```

Runs PHP syntax checks, extraction/response tests with a mocked OpenAI transport, and a temporary local PHP HTTP server to test request boundaries. No OpenAI credentials, internet access, paid requests or third-party test packages are needed. Local binding to `127.0.0.1` must be allowed. Deployment and real model extraction must still be checked on the target hosting account.

The second command tests the actual `.htaccess` in a temporary unprivileged Apache 2.4 server, using harmless static fixtures instead of production PHP/config. It verifies the directory index, deny rules, method/body limits and security headers, including deployment under a subdirectory. It requires Apache and its modules; set `APACHE_HTTPD` and `APACHE_MODULE_DIR` if they are not in the default macOS/Linux paths. The PHP development server ignores `.htaccess`, so its tests alone cannot verify those protections. Neither local suite establishes the SiteGround account's configuration.

## References checked 5 November 2026

- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [OpenAI Responses API](https://developers.openai.com/api/reference/responses/overview)
- [GPT-6 Luna capabilities](https://developers.openai.com/api/docs/models/gpt-6-luna)
- [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data)
- [SiteGround PHP version management](https://www.siteground.com/kb/what-is-managed-php)
- [SiteGround HTTPS Enforce](https://www.siteground.com/kb/how-do-i-enforce-https)
- [SiteGround NGINX Direct Delivery](https://www.siteground.com/tutorials/supercacher/nginx-direct-delivery)
- [Apache access control](https://httpd.apache.org/docs/2.4/en/howto/access.html)
- [Apache .htaccess overrides](https://httpd.apache.org/docs/2.4/howto/htaccess.html)
- [Austrian health guidance](https://www.sozialversicherung.gv.at/cdscontent/?contentid=10007.843947&portal=svportal)
