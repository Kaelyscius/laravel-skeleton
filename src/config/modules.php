<?php

declare(strict_types=1);

/*
|--------------------------------------------------------------------------
| Modules désactivables (ADR-0001 / ADR-0009)
|--------------------------------------------------------------------------
|
| Chaque clé pilote l'enregistrement conditionnel du service provider du
| module correspondant dans AppServiceProvider::register(). `core` n'est PAS
| ici : la couche Core est transversale et toujours active (bootstrap/
| providers.php). Activation au déploiement uniquement (pas de toggle runtime,
| philosophie Plausible-style anti-WordPress) — un fork-streamer désactive un
| module via MODULE_<NAME>_ENABLED=false sans toucher au code.
|
*/

return [
    'public' => env('MODULE_PUBLIC_ENABLED', true),
    'live' => env('MODULE_LIVE_ENABLED', true),
    'reviews' => env('MODULE_REVIEWS_ENABLED', true),
    'press_kit' => env('MODULE_PRESS_KIT_ENABLED', true),
    'admin' => env('MODULE_ADMIN_ENABLED', true),
];
