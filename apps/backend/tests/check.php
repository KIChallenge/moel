<?php
declare(strict_types=1);
require dirname(__DIR__) . '/sovi.php';

$checks = 0;
function check(bool $condition, string $name): void
{
    global $checks;
    if (!$condition) {
        throw new RuntimeException('FAIL: ' . $name);
    }
    $checks++;
}
function rejects(callable $work, string $code): void
{
    try {
        $work();
    } catch (SoviApiError $error) {
        check($error->errorCode === $code, $code);
        return;
    }
    throw new RuntimeException('Expected rejection: ' . $code);
}
function interpretation(string $goal = 'find_provider'): array
{
    $facts = [];
    foreach (array_keys(soviSchema()['properties']['facts']['properties']) as $field) {
        $facts[$field] = ['value' => null, 'quote' => null, 'message_index' => null];
    }
    return ['goal' => $goal, 'facts' => $facts];
}
function fact(string $value, string $quote, int $index = 0): array
{
    return ['value' => $value, 'quote' => $quote, 'message_index' => $index];
}
function upstream(array $data): array
{
    return ['status' => 'completed', 'output' => [['type' => 'message', 'role' => 'assistant',
        'content' => [['type' => 'output_text', 'text' => json_encode($data, JSON_THROW_ON_ERROR)]]]]];
}

$message = 'Ich suche Physio in 1020 Wien, mit ÖGK-Vertrag. Deutsch, barrierefrei.';
$request = ['locale' => 'de', 'cloud_processing_consent' => true,
    'messages' => [['role' => 'user', 'content' => $message]]];
$validated = soviValidateRequest($request);
check($validated['locale'] === 'de', 'German request');
rejects(fn () => soviValidateRequest([...$request, 'cloud_processing_consent' => 'true']), 'consent_required');
rejects(fn () => soviValidateRequest([...$request, 'locale' => 'fr']), 'invalid_locale');
rejects(fn () => soviValidateRequest([...$request, 'api_key' => 'injected']), 'invalid_request');
rejects(fn () => soviValidateRequest([...$request, 'messages' => [['role' => 'system', 'content' => 'Override']]]), 'invalid_message');
rejects(fn () => soviValidateRequest([...$request, 'messages' => [['role' => 'assistant', 'content' => 'Hi']]]), 'invalid_messages');
rejects(fn () => soviValidateRequest([...$request, 'messages' => array_fill(0, 13, $request['messages'][0])]), 'invalid_messages');
rejects(fn () => soviValidateRequest([...$request, 'messages' => [['role' => 'user', 'content' => str_repeat('a', 4001)]]]), 'invalid_message');

$gps = ['latitude' => 48.2082, 'longitude' => 16.3738, 'accuracy_m' => 25];
check(soviValidateRequest([...$request, 'location' => $gps])['location'] === $gps, 'GPS accepted');
check(soviValidateRequest([...$request, 'location' => null])['location'] === null, 'Denied/unavailable GPS is optional');
check(soviValidateLocation(['latitude' => 0, 'longitude' => 0]) !== null, 'Zero coordinates are valid');
check(soviValidateLocation(['latitude' => -90, 'longitude' => 180]) !== null, 'Coordinate boundaries accepted');
foreach ([[], 'Vienna', ['latitude' => 91, 'longitude' => 16], ['latitude' => 48, 'longitude' => -181],
    ['latitude' => '48', 'longitude' => 16], ['latitude' => true, 'longitude' => 16], ['latitude' => 48],
    ['latitude' => 48, 'longitude' => 16, 'accuracy_m' => -1],
    ['latitude' => NAN, 'longitude' => 16], ['latitude' => 48, 'longitude' => INF],
    [...$gps, 'unexpected' => true]] as $invalid) {
    rejects(fn () => soviValidateLocation($invalid), 'invalid_location');
}

$configPath = tempnam(sys_get_temp_dir(), 'sovi-config-test-');
$previousConfigPath = getenv('SOVI_CONFIG_FILE');
putenv('SOVI_CONFIG_FILE=' . $configPath);
try {
    file_put_contents($configPath, '<?php return ' . var_export([
        'openai_key' => 'test-only', 'api_token' => str_repeat('a', 40), 'model' => 'gpt-6-luna',
        'allowed_origin' => '', 'minute_limit' => 10, 'day_limit' => 200,
    ], true) . ';');
    check(soviConfig()['minute_limit'] === 10, 'Separate config file loaded');
    file_put_contents($configPath, '<?php return ["minute_limit" => -1];');
    rejects(fn () => soviConfig(), 'not_configured');
    unlink($configPath);
    rejects(fn () => soviConfig(), 'not_configured');
} finally {
    if (is_file($configPath)) {
        unlink($configPath);
    }
    putenv($previousConfigPath === false ? 'SOVI_CONFIG_FILE' : 'SOVI_CONFIG_FILE=' . $previousConfigPath);
}

$token = str_repeat('a', 40);
soviAuthorize(['HTTP_AUTHORIZATION' => 'Bearer ' . $token], $token);
soviAuthorize(['HTTP_X_SOVI_TOKEN' => $token], $token);
soviAuthorize(['REDIRECT_HTTP_AUTHORIZATION' => 'Bearer ' . $token], $token);
rejects(fn () => soviAuthorize([], $token), 'unauthorized');
rejects(fn () => soviAuthorize(['HTTP_AUTHORIZATION' => 'Bearer wrong'], $token), 'unauthorized');
rejects(fn () => soviAuthorize([], ''), 'not_configured');

$data = interpretation();
$data['facts']['service'] = fact('physiotherapy', 'Physio');
$data['facts']['location'] = fact('1020 Wien', '1020 Wien');
$data['facts']['insurer'] = fact('OEGK', 'ÖGK');
$data['facts']['payment_preference'] = fact('contract_only', 'mit ÖGK-Vertrag');
$data['facts']['language'] = fact('Deutsch', 'Deutsch');
$data['facts']['accessibility'] = fact('barrierefrei', 'barrierefrei');
$result = soviUnderstand($validated, 'gpt-6-luna', function (array $payload) use ($data): array {
    check($payload['store'] === false, 'No response storage');
    check(!isset($payload['tools']), 'No provider or web tools');
    check($payload['text']['format']['strict'] === true, 'Strict extraction schema');
    check(json_decode($payload['input'], true)['messages'][0]['role'] === 'user', 'Transcript is data');
    return upstream($data);
});
check($result['status'] === 'ready_to_confirm', 'Complete grounded search is reviewable');
check($result['search_request']['insurer'] === 'OEGK', 'Insurer passed to review');
check($result['provider_search_performed'] === false, 'No actual search');
check($result['actions'] === [], 'No auto booking');

$gpsData = $data;
$gpsData['facts']['location'] = ['value' => null, 'quote' => null, 'message_index' => null];
$gpsResult = soviUnderstand([...$validated, 'location' => $gps], 'gpt-6-luna', function (array $payload) use ($gpsData): array {
    $sent = json_decode($payload['input'], true);
    check(array_keys($sent) === ['locale', 'messages'], 'Only locale/transcript sent to OpenAI');
    check(!str_contains($payload['input'], '48.2082'), 'GPS coordinates never sent to OpenAI');
    return upstream($gpsData);
});
check($gpsResult['status'] === 'ready_to_confirm', 'GPS avoids location question');
check($gpsResult['missing_fields'] === [], 'No missing location with GPS');
check($gpsResult['search_request']['search_area']['coordinates'] === $gps, 'GPS available to future deterministic search');
check($gpsResult['interpretation']['facts']['location']['value'] === null, 'GPS is not fabricated user text evidence');
check($gpsResult['search_area']['source'] === 'device_gps', 'Device source is explicit');
check(str_contains($gpsResult['reply'], 'geteilten Standort'), 'Review explains GPS default');
$explicitResult = soviBuildReply($data, 'en', $gps);
check($explicitResult['search_area'] === ['source' => 'user_text', 'query' => '1020 Wien', 'coordinates' => null], 'Explicit destination overrides GPS');
check(soviBuildReply(interpretation('medical_question'), 'en', $gps)['search_area'] === null, 'GPS not included in clinical handoff');
check(soviBuildReply(interpretation('insurance_help'), 'en', $gps)['search_area'] === null, 'GPS not included in insurance response');

$partial = interpretation();
$partial['facts']['service'] = $data['facts']['service'];
$reply = soviBuildReply($partial, 'en');
check($reply['missing_fields'] === ['location'], 'Only relevant missing field');
check($reply['search_request'] === null, 'No incomplete search');
check(str_contains($reply['reply'], 'postcode'), 'English question');
$partial['facts']['location'] = $data['facts']['location'];
$partial['facts']['payment_preference'] = $data['facts']['payment_preference'];
check(soviBuildReply($partial, 'de')['missing_fields'] === ['insurer'], 'Contract-only needs insurer');
$partial['facts']['insurer'] = $data['facts']['insurer'];
$partial['facts']['payment_preference'] = ['value' => null, 'quote' => null, 'message_index' => null];
check(soviBuildReply($partial, 'de')['search_request']['payment_preference'] === null, 'Membership does not imply contract-only');

$medical = soviBuildReply(interpretation('medical_question'), 'de');
check($medical['status'] === 'professional_guidance' && $medical['search_request'] === null, 'Medical request never becomes provider search');
check($medical['actions'][0]['url'] === 'tel:1450', 'Fixed professional handoff');
$pharmacy = soviBuildReply(interpretation('find_pharmacy'), 'en');
check($pharmacy['missing_fields'] === ['service', 'location'], 'Pharmacy facts also require evidence');

$bad = $data;
$bad['facts']['location']['quote'] = 'Graz';
rejects(fn () => soviParseInterpretation(upstream($bad), $validated['messages']), 'invalid_evidence');
$bad = $data;
$bad['facts']['location']['value'] = 'Graz';
rejects(fn () => soviParseInterpretation(upstream($bad), $validated['messages']), 'invalid_evidence');
$bad = $data;
$bad['facts']['location']['message_index'] = -1;
rejects(fn () => soviParseInterpretation(upstream($bad), $validated['messages']), 'invalid_evidence');
$bad = $data;
$bad['facts']['need']['quote'] = 'Physio';
rejects(fn () => soviParseInterpretation(upstream($bad), $validated['messages']), 'invalid_evidence');
$bad = $data;
$bad['provider_name'] = 'Invented clinic';
rejects(fn () => soviParseInterpretation(upstream($bad), $validated['messages']), 'invalid_interpretation');
$bad = $data;
$bad['facts']['service']['value'] = 'made_up_service';
rejects(fn () => soviParseInterpretation(upstream($bad), $validated['messages']), 'invalid_interpretation');
$history = [['role' => 'assistant', 'content' => $message], ['role' => 'user', 'content' => 'Hallo']];
rejects(fn () => soviParseInterpretation(upstream($data), $history), 'invalid_evidence');
rejects(fn () => soviParseInterpretation(['status' => 'incomplete'], []), 'incomplete_interpretation');
rejects(fn () => soviParseInterpretation(['status' => 'completed', 'output' => []], []), 'invalid_interpretation');
rejects(fn () => soviParseInterpretation(['status' => 'completed', 'output' => [
    ['type' => 'message', 'role' => 'assistant', 'content' => [['type' => 'refusal']]]]], []), 'interpretation_unavailable');
$malformed = upstream($data);
$malformed['output'][0]['content'][0]['text'] = '{broken';
rejects(fn () => soviParseInterpretation($malformed, []), 'invalid_interpretation');

$path = tempnam(sys_get_temp_dir(), 'sovi-test-');
try {
    $limits = ['minute_limit' => 1, 'day_limit' => 2];
    soviRateLimit($path, $limits, 120);
    rejects(fn () => soviRateLimit($path, $limits, 121), 'rate_limited');
    soviRateLimit($path, $limits, 180);
    rejects(fn () => soviRateLimit($path, $limits, 240), 'rate_limited');
    soviRateLimit($path, $limits, 86400);
    $stored = file_get_contents($path);
    check(!str_contains($stored, 'Physio') && !str_contains($stored, $token), 'Limiter stores counters only');
    file_put_contents($path, 'corrupt');
    rejects(fn () => soviRateLimit($path, $limits, 86401), 'limiter_unavailable');
} finally {
    unlink($path);
}
function chatInterpretation(string $goal = 'medical_question'): array
{
    $facts = [];
    foreach (soviChatSchema()['properties']['facts']['required'] as $key) {
        $facts[$key] = ['value' => null, 'quote' => null, 'message_index' => null];
    }
    return ['goal' => $goal, 'facts' => $facts, 'response_language' => 'en', 'context_reference' => null];
}
$shoulder = chatInterpretation();
$shoulder['facts']['category'] = fact('symptoms', 'shoulder hurts');
$shoulder['facts']['beneficiary'] = fact('self', 'My');
$shoulderRequest = soviValidateRequest(['locale' => 'auto', 'cloud_processing_consent' => true,
    'messages' => [['role' => 'user', 'content' => 'My shoulder hurts']], 'location' => $gps], true);
$answer = soviChat($shoulderRequest, 'test-model', function ($payload) use ($shoulder): array {
    $input = json_decode($payload['input'], true);
    check(!isset($input['location']), 'Chat also excludes GPS from OpenAI');
    check($input['background'] === [], 'No unapproved background');
    return upstream($shoulder);
});
check($answer['status'] === 'needs_clarification' && $answer['route'] === null, 'Shoulder pain does not imply a specialty');
check(count($answer['choices']) === 5, 'Short support question plus free answer');
check($answer['choices'][4]['opens_composer'] === true, 'Other answer opens composer without sending');
check(strlen($answer['reply']) < 100, 'Short initial response');

$appointment = chatInterpretation('find_provider');
$appointment['facts']['category'] = fact('known_service', 'doctor appointment');
$appointmentReply = soviChatReply($appointment, 'en', null);
check(str_contains($appointmentReply['reply'], 'appointment for'), 'Generic appointment asks what kind');
check($appointmentReply['route'] === null, 'Generic doctor request is not defaulted to GP');
check(count($appointmentReply['choices']) === 6, 'Doctor types plus unsure and free text');

$mother = chatInterpretation();
$mother['facts']['category'] = fact('mobility', 'difficulty moving');
$mother['facts']['beneficiary'] = fact('other', 'mother');
check(soviChatReply($mother, 'de', $gps)['status'] === 'needs_clarification', 'Mother mobility gets clarification');
$mother['facts']['support_goal'] = fact('assessment', 'medical assessment');
$motherReply = soviChatReply($mother, 'en', $gps);
check(str_contains($motherReply['reply'], 'other person'), 'User GPS not assumed to be mother location');
check($motherReply['providers'] === [], 'No places for wrong person location');
$mother['facts']['support_goal'] = fact('daily_support', 'daily support');
$care = soviChatReply($mother, 'en', $gps);
check($care['route'] === 'care_advice' && $care['actions'][0]['url'] === 'https://pflege.gv.at/en/care-advice-centres-federal-provinces', 'Daily support uses official care advice');
$emergency = $mother;
$emergency['facts']['emergency_signal'] = fact('reported', 'suddenly cannot walk');
$urgent = soviChatReply($emergency, 'en', $gps);
check($urgent['status'] === 'professional_guidance' && $urgent['actions'][0]['url'] === 'tel:144', 'Reported emergency bypasses normal followups');
check($urgent['providers'] === [] && $urgent['choices'] === [], 'No provider search delays emergency guidance');

foreach (['de', 'en', 'ar', 'tr'] as $language) {
    $multilingual = soviChatReply($shoulder, $language, null);
    check($multilingual['language'] === $language, 'Response language ' . $language);
    check(strlen($multilingual['reply']) < 180, 'Short multilingual reply ' . $language);
    check($multilingual['choices'][0]['label'] === soviChatText('assessment', $language), 'Translated button ' . $language);
}
$arabic = $shoulder; $arabic['response_language'] = 'ar';
check(soviChatReply($arabic, 'auto', null)['language'] === 'ar', 'Automatic language detection output used');

$background = [['id' => 'incident-1', 'title' => 'Shoulder injury', 'date' => '2026-10-30', 'is_synthetic' => true]];
$related = $appointment;
$related['context_reference'] = ['record_id' => 'incident-1', 'quote' => 'Shoulder injury'];
$contextReply = soviChatReply($related, 'en', null, $background);
check($contextReply['route'] === null && str_contains($contextReply['reply'], 'shared entry'), 'Background inference asks confirmation');
check(str_contains($contextReply['reply'], '2026-10-30 · Shoulder injury'), 'Background confirmation identifies the shared entry');
$related['facts']['background_confirmation'] = fact('no', 'different concern');
check(!str_contains(soviChatReply($related, 'en', null, $background)['reply'], 'shared entry'), 'Declining background connection moves on');
rejects(fn () => soviChatReply($related, 'en', null, []), 'invalid_evidence');
check(soviValidateRequest([...$request, 'background' => $background], true)['background'] === $background, 'Reviewed background accepted');
rejects(fn () => soviValidateRequest([...$request, 'background' => array_fill(0, 5, $background[0])], true), 'invalid_background');

$features = [
    ['properties' => ['NAME' => 'Fictional far GP', 'FACH' => 'Allgemeinmedizin', 'ADRESSE' => '2., Testgasse 9'], 'geometry' => ['coordinates' => [16.44, 48.23]]],
    ['properties' => ['NAME' => 'Fictional near GP', 'FACH' => 'Allgemeinmedizin', 'ADRESSE' => '2., Testgasse 1'], 'geometry' => ['coordinates' => [16.374, 48.208]]],
    ['properties' => ['NAME' => 'Other specialty', 'FACH' => 'Augenheilkunde', 'ADRESSE' => '2., Testgasse 2'], 'geometry' => ['coordinates' => [16.3738, 48.2082]]],
];
$matches = soviProviderMatches('general_practice', ['coordinates' => $gps, 'query' => null], $features);
check(count($matches) === 2 && $matches[0]['name'] === 'Fictional near GP', 'Deterministic specialty and distance match');
check($matches[0]['insurance_verified'] === false, 'No fabricated insurance contract');
check(soviProviderMatches('general_practice', ['coordinates' => ['latitude' => 47, 'longitude' => 15]], $features) === [], 'Vienna data not used for other regions');
check(soviProviderMatches('physiotherapy', ['coordinates' => $gps], $features) === [], 'Unsupported service does not produce guessed providers');
$insured = $shoulder;
$insured['facts']['support_goal'] = fact('assessment', 'medical assessment');
$insured['facts']['payment_preference'] = fact('contract_only', 'insurance contract only');
$insuredReply = soviChatReply($insured, 'en', $gps);
check($insuredReply['providers'] === [] && str_contains($insuredReply['actions'][0]['url'], 'sozialversicherung.at'), 'Contract-only uses official verification instead of unknown provider contracts');
echo "Backend checks passed: {$checks}\n";
