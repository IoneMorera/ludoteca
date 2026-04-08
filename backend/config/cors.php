<?php

return [
    'paths' => [
        'api/*',
        'login',
        'logout',
        'sanctum/csrf-cookie',
    ],

    'allowed_methods' => ['*'],

    'allowed_origins' => [
        'https://ludotecaraxar.netlify.app',
        'http://localhost',
        'http://localhost:5173',
    ],

    'allowed_origins_patterns' => [
        '^https:\/\/.*\.netlify\.app$',
        '^https?:\/\/192\.168\.\d{1,3}\.\d{1,3}(:\d+)?$',
    ],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => true,
];
