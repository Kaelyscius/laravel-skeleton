<?php

declare(strict_types=1);

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// Route de healthcheck pour Docker
Route::get('/health', function () {
    return response()->json([
        'status' => 'ok',
        'timestamp' => now()
            ->toISOString(),
        'service' => 'laravel',
        'app' => config('app.name', 'Laravel'),
    ]);
});
