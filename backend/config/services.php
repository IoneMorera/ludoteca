<?php

return [
    'bgg' => [
        'api_key' => env('BGG_API_KEY'),
        'default_user' => env('BGG_DEFAULT_USER', 'raxar'),
    ],
    'openai' => [
        'api_key' => env('OPENAI_API_KEY'),
        'model' => env('OPENAI_VISION_MODEL', 'gpt-4o'),
    ],
];
