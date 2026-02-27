<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return response()->json([
        'app' => 'Ludoteca API',
        'version' => '1.0.0',
    ]);
});
