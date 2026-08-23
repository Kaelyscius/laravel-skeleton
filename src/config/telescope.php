<?php

use Laravel\Telescope\Http\Middleware\Authorize;
use Laravel\Telescope\Watchers;

return [
    /*
    |--------------------------------------------------------------------------
    | Telescope Master Switch
    |--------------------------------------------------------------------------
    |
    | This option may be used to disable all Telescope watchers regardless
    | of their individual configuration, which simply provides a single
    | and convenient way to enable or disable Telescope data storage.
    |
    */

    'enabled' => env('TELESCOPE_ENABLED', env('APP_ENV') !== 'production'),

    /*
    |--------------------------------------------------------------------------
    | Telescope Domain
    |--------------------------------------------------------------------------
    |
    | This is the subdomain where Telescope will be accessible from. If the
    | setting is null, Telescope will reside under the same domain as the
    | application. Otherwise, this value will be used as the subdomain.
    |
    */

    'domain' => env('TELESCOPE_DOMAIN'),

    /*
    |--------------------------------------------------------------------------
    | Telescope Path
    |--------------------------------------------------------------------------
    |
    | This is the URI path where Telescope will be accessible from. Feel free
    | to change this path to anything you like. Note that the URI will not
    | affect the paths of its internal API that aren't exposed to users.
    |
    */

    'path' => env('TELESCOPE_PATH', 'telescope'),

    /*
    |--------------------------------------------------------------------------
    | Telescope Storage Driver
    |--------------------------------------------------------------------------
    |
    | This configuration options determines the storage driver that will
    | be used to store Telescope's data. In addition, you may set any
    | custom options as needed by the particular driver you choose.
    |
    */

    'driver' => 'database',

    'storage' => [
        'database' => [
            'connection' => env('DB_CONNECTION', 'pgsql'),
            'chunk' => 1000,
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Telescope Queue
    |--------------------------------------------------------------------------
    |
    | This configuration options determines the queue connection and queue
    | which will be used to process ProcessPendingUpdate jobs. This can
    | be changed if you would prefer to use a non-default connection.
    |
    */

    'queue' => [
        'connection' => env('TELESCOPE_QUEUE_CONNECTION'),
        'queue' => env('TELESCOPE_QUEUE'),
        'delay' => env('TELESCOPE_QUEUE_DELAY', 10),
    ],

    /*
    |--------------------------------------------------------------------------
    | Telescope Route Middleware
    |--------------------------------------------------------------------------
    |
    | These middleware will be assigned to every Telescope route, giving you
    | the chance to add your own middleware to this list or change any of
    | the existing middleware. Or, you can simply stick with this list.
    |
    */

    'middleware' => [
        'web',
        Authorize::class,
    ],

    /*
    |--------------------------------------------------------------------------
    | Allowed / Ignored Paths & Commands
    |--------------------------------------------------------------------------
    |
    | The following array lists the URI paths and Artisan commands that will
    | not be watched by Telescope. In addition to this list, some Laravel
    | commands, like migrations and queue commands, are always ignored.
    |
    */

    'only_paths' => [
        // 'api/*'
    ],

    'ignore_paths' => [
        'livewire*',
        'nova-api*',
        'pulse*',
        '_boost*',
        '.well-known*',

        /*
         * 🔴 `health` AJOUTÉ EN STORY 2.4 (revue 2), ET C'EST UNE MESURE.
         *
         * Telescope enregistre chaque requête, chaque requête SQL et chaque
         * interaction de cache — donc, sur `/health`, il rejoue vers les
         * dépendances que la route vient de déclarer INJOIGNABLES, hors du
         * portillon et hors du budget de sonde.
         *
         * Mesuré le 2026-08-23, conteneur redis réellement arrêté. D'abord la
         * CAUSE, par bascule des drapeaux (noyau HTTP dans le conteneur php) :
         *
         *   TELESCOPE=on  PULSE=on   handle = 13,77 s
         *   TELESCOPE=on  PULSE=off  handle = 12,91 s
         *   TELESCOPE=off PULSE=on   handle =  6,39 s   ← Telescope pèse ~6,5 s
         *   TELESCOPE=off PULSE=off  handle =  6,39 s   ← plancher : 2 portillons
         *
         * Puis l'EFFET de cette exclusion, sur de vraies requêtes HTTP :
         *
         *   avant : 13,74 s · 12,86 s        après : 9,59 s · 9,61 s
         *
         * ⚠️ ET LA PHRASE HONNÊTE EST CELLE-CI : l'exclusion retire ~4 s, pas
         * les 6,5 s de la bascule. `ignore_paths` empêche l'ENREGISTREMENT,
         * mais Telescope boote et ses observateurs restent branchés ; il reste
         * ~3,2 s au-dessus du plancher, NON LOCALISÉES. C'est moins que les
         * « ~7,5 s inexpliquées » de la revue 1, ce n'est pas zéro, et le dire
         * vaut mieux que d'arrondir. Report tenu à jour dans `deferred-work.md`.
         *
         * ⚠️ Un harnais CLI (`Request::create`) ne mesure PAS cette exclusion :
         * il rend 13,77 s même avec `health` dans la liste, parce que la requête
         * qu'il fabrique n'est pas celle que Telescope consulte au démarrage de
         * son enregistrement. Seule la mesure HTTP vaut ici.
         *
         * ⚖️ Et la sémantique le veut : une sonde de santé qui s'auto-observe
         * fausse sa propre mesure, et remplit Telescope d'entrées à chaque
         * sondage d'un superviseur.
         */
        'health',
    ],

    'ignore_commands' => [],

    /*
    |--------------------------------------------------------------------------
    | Telescope Watchers
    |--------------------------------------------------------------------------
    |
    | The following array lists the "watchers" that will be registered with
    | Telescope. The watchers gather the application's profile data when
    | a request or task is executed. Feel free to customize this list.
    |
    */

    'watchers' => [
        Watchers\BatchWatcher::class => env('TELESCOPE_BATCH_WATCHER', true),

        Watchers\CacheWatcher::class => [
            'enabled' => env('TELESCOPE_CACHE_WATCHER', true),
            'hidden' => [],
            'ignore' => [],
        ],

        Watchers\ClientRequestWatcher::class => [
            'enabled' => env('TELESCOPE_CLIENT_REQUEST_WATCHER', true),
            'ignore_hosts' => [],
        ],

        Watchers\CommandWatcher::class => [
            'enabled' => env('TELESCOPE_COMMAND_WATCHER', true),
            'ignore' => [],
        ],

        Watchers\DumpWatcher::class => [
            'enabled' => env('TELESCOPE_DUMP_WATCHER', true),
            'always' => env('TELESCOPE_DUMP_WATCHER_ALWAYS', false),
        ],

        Watchers\EventWatcher::class => [
            'enabled' => env('TELESCOPE_EVENT_WATCHER', true),
            'ignore' => [],
        ],

        Watchers\ExceptionWatcher::class => env('TELESCOPE_EXCEPTION_WATCHER', true),

        Watchers\GateWatcher::class => [
            'enabled' => env('TELESCOPE_GATE_WATCHER', true),
            'ignore_abilities' => [],
            'ignore_packages' => true,
            'ignore_paths' => [],
        ],

        Watchers\JobWatcher::class => env('TELESCOPE_JOB_WATCHER', true),

        Watchers\LogWatcher::class => [
            'enabled' => env('TELESCOPE_LOG_WATCHER', true),
            'level' => 'error',
        ],

        Watchers\MailWatcher::class => env('TELESCOPE_MAIL_WATCHER', true),

        Watchers\ModelWatcher::class => [
            'enabled' => env('TELESCOPE_MODEL_WATCHER', true),
            'events' => ['eloquent.*'],
            'hydrations' => true,
        ],

        Watchers\NotificationWatcher::class => env('TELESCOPE_NOTIFICATION_WATCHER', true),

        Watchers\QueryWatcher::class => [
            'enabled' => env('TELESCOPE_QUERY_WATCHER', true),
            'ignore_packages' => true,
            'ignore_paths' => [],
            'slow' => 100,
        ],

        Watchers\RedisWatcher::class => env('TELESCOPE_REDIS_WATCHER', true),

        Watchers\RequestWatcher::class => [
            'enabled' => env('TELESCOPE_REQUEST_WATCHER', true),
            'size_limit' => env('TELESCOPE_RESPONSE_SIZE_LIMIT', 64),
            'ignore_http_methods' => [],
            'ignore_status_codes' => [],
        ],

        Watchers\ScheduleWatcher::class => env('TELESCOPE_SCHEDULE_WATCHER', true),
        Watchers\ViewWatcher::class => env('TELESCOPE_VIEW_WATCHER', true),
    ],
];
