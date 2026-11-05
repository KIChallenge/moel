<?php
declare(strict_types=1);

// Copy to config.php (ignored by Git) and edit that copy on your server.
// Alternatively set SOVI_CONFIG_FILE to a private path outside public_html.
return [
    'openai_key' => getenv('OPENAI_API_KEY') ?: '',
    'api_token' => getenv('SOVI_API_TOKEN') ?: '', // At least 32 random characters.
    'model' => getenv('SOVI_OPENAI_MODEL') ?: 'gpt-6-luna',
    'allowed_origin' => getenv('SOVI_ALLOWED_ORIGIN') ?: '', // Exact browser origin; native iOS needs none.
    'minute_limit' => 10,
    'day_limit' => 200,
];
