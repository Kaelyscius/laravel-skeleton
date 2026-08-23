<?php

use Spatie\Health\Models\HealthCheckResultHistoryItem;
use Spatie\Health\Notifications\CheckFailedNotification;
use Spatie\Health\Notifications\Notifiable;
use Spatie\Health\ResultStores\EloquentHealthResultStore;

return [
    /*
     * A result store is responsible for saving the results of the checks. The
     * `EloquentHealthResultStore` will save results in the database. You
     * can use multiple stores at the same time.
     */
    'result_stores' => [
        EloquentHealthResultStore::class => [
            'connection' => env('HEALTH_DB_CONNECTION', env('DB_CONNECTION')),
            'model' => HealthCheckResultHistoryItem::class,
            'keep_history_for_days' => 5,
        ],

        /*
     * Spatie\Health\ResultStores\CacheHealthResultStore::class => [
     * 'store' => 'file',
     * ],
     * Spatie\Health\ResultStores\JsonFileHealthResultStore::class => [
     * 'disk' => 's3',
     * 'path' => 'health.json',
     * ],
     * Spatie\Health\ResultStores\InMemoryHealthResultStore::class,
     */
    ],

    /*
     * You can get notified when specific events occur. Out of the box you can use 'mail' and 'slack'.
     * For Slack you need to install laravel/slack-notification-channel.
     */
    'notifications' => [
        /*
         * Notifications will only get sent if this option is set to `true`.
         */
        'enabled' => env('HEALTH_NOTIFICATIONS_ENABLED', false),

        'notifications' => [
            CheckFailedNotification::class => ['mail'],
        ],

        /*
         * Here you can specify the notifiable to which the notifications should be sent. The default
         * notifiable will use the variables specified in this config file.
         */
        'notifiable' => Notifiable::class,

        /*
         * When checks start failing, you could potentially end up getting
         * a notification every minute.
         *
         * With this setting, notifications are throttled. By default, you'll
         * only get one notification per hour.
         */
        'throttle_notifications_for_minutes' => 60,
        'throttle_notifications_key' => 'health:latestNotificationSentAt:',

        /*
         * When set to true, notifications will only be sent when at least one
         * check has a 'failed' status. Warnings will be ignored.
         */
        'only_on_failure' => false,

        'mail' => [
            'to' => env('HEALTH_NOTIFICATION_EMAIL'),

            'from' => [
                'address' => env('MAIL_FROM_ADDRESS', 'hello@example.com'),
                'name' => env('MAIL_FROM_NAME', 'Example'),
            ],
        ],

        'slack' => [
            'webhook_url' => env('HEALTH_SLACK_WEBHOOK_URL', ''),

            /*
             * If this is set to null the default channel of the webhook will be used.
             */
            'channel' => null,

            'username' => null,

            'icon' => null,
        ],
    ],

    /*
     * You can let Oh Dear monitor the results of all health checks. This way, you'll
     * get notified of any problems even if your application goes totally down. Via
     * Oh Dear, you can also have access to more advanced notification options.
     */
    'oh_dear_endpoint' => [
        'enabled' => false,

        /*
         * When this option is enabled, the checks will run before sending a response.
         * Otherwise, we'll send the results from the last time the checks have run.
         */
        'always_send_fresh_results' => true,

        /*
         * The secret that is displayed at the Application Health settings at Oh Dear.
         */
        'secret' => env('OH_DEAR_HEALTH_CHECK_SECRET'),

        /*
         * The URL that should be configured in the Application health settings at Oh Dear.
         */
        'url' => '/oh-dear-health-check-results',
    ],

    /*
     * You can specify a heartbeat URL for the Horizon check.
     * This URL will be pinged if the Horizon check is successful.
     * This way you can get notified if Horizon goes down.
     */
    'horizon' => [
        'heartbeat_url' => env('HORIZON_HEARTBEAT_URL'),
    ],

    /*
     * You can specify a heartbeat URL for the Schedule check.
     * This URL will be pinged if the Schedule check is successful.
     * This way you can get notified if the schedule fails to run.
     */
    'schedule' => [
        'heartbeat_url' => env('SCHEDULE_HEARTBEAT_URL'),
    ],

    /*
     * You can set a theme for the local results page
     *
     * - light: light mode
     * - dark: dark mode
     */
    'theme' => 'light',

    /*
     * When enabled, completed `HealthQueueJob`s will be displayed
     * in Horizon's silenced jobs screen.
     */
    'silence_health_queue_job' => true,

    /*
     * The response code to use for HealthCheckJsonResultsController when a health
     * check has failed
     */
    'json_results_failure_status' => 503,

    /*
     * You can specify a secret token that needs to be sent in the X-Secret-Token for secured access.
     */
    'secret_token' => env('HEALTH_SECRET_TOKEN'),

    /**
     * By default, conditionally skipped health checks are treated as failures.
     * You can override this behavior by uncommenting the configuration below.
     * @see https://spatie.be/docs/laravel-health/v1/basic-usage/conditionally-running-or-modifying-checks
     * ⚠️ Story 2.4, revue 1 : cette clé était INERTE. La route `/health`
     * écrasait tout statut non-`ok` en `error`, donc `skipped` restait fatal
     * quoi qu'on écrive ici. Elle est désormais LUE par la route, et
     * `HealthEndpointTest` éprouve les deux valeurs.
     */
    // 'treat_skipped_as_failure' => false,

    /*
     |--------------------------------------------------------------------------
     | CLÉ DU PROJET — pas une clé de Spatie (Story 2.4)
     |--------------------------------------------------------------------------
     |
     | Budget CUMULÉ, en millisecondes, accordé aux sondes de la route
     | `/health` (`routes/web.php`). Au-delà, les sondes restantes ne sont pas
     | lancées et sont rapportées en ÉCHEC EXPLICITE — jamais omises, jamais
     | supposées saines.
     |
     | ⚠️ LA JUSTIFICATION PRÉCÉDENTE ÉTAIT FAUSSE (revue 1) : elle invoquait une
     | republication de ce fichier par
     | `scripts/install/35-configure-spatie-packages.sh`, qui ne publie en
     | réalité QUE si le fichier est ABSENT (`if [ ! -f config/health.php ]`) —
     | et il est versionné, donc le scénario ne peut pas survenir sur un clone.
     | Le vrai motif du défaut codé en dur est plus simple : une clé absente,
     | vide, non numérique, nulle ou NÉGATIVE donnerait une échéance déjà
     | dépassée, donc un `/health` qui ne sonde plus rien et rend `503` à
     | perpétuité sans nommer la moindre panne. `HealthEndpointTest` retire la
     | clé et pose des valeurs hostiles pour l'éprouver.
     |
     | Mesuré le 2026-08-23 (conteneur postgres réellement arrêté) : sans
     | budget, la réponse arrivait à 89 s et Apache rendait 504 à 60 s.
     */
    'probe_budget_ms' => env('HEALTH_PROBE_BUDGET_MS', 5000),

    /*
     |--------------------------------------------------------------------------
     | CLÉ DU PROJET — pas une clé de Spatie (Story 2.4, revue 1)
     |--------------------------------------------------------------------------
     |
     | Délai maximal, en secondes, accordé au PORTILLON de joignabilité de
     | chaque sonde (`App\HealthChecks\Support\BackendEndpoint`). Le portillon
     | ouvre UNE connexion TCP avant l'aller-retour applicatif : c'est ce qui
     | fait passer une base injoignable de ~10 tentatives à une seule.
     |
     | ⚠️ Le code porte son propre défaut (2.0 s) : `0` signifie « pas de
     | limite » pour `fsockopen()`, donc une valeur nulle ou négative rendrait
     | le portillon inopérant — la panne même qu'il existe pour éviter.
     */
    'probe_connect_timeout_seconds' => env('HEALTH_PROBE_CONNECT_TIMEOUT', 2.0),

    /*
     |--------------------------------------------------------------------------
     | CLÉ DU PROJET — pas une clé de Spatie (Story 2.4, revue 2)
     |--------------------------------------------------------------------------
     |
     | Porte de sortie du portillon de joignabilité. `false` le désarme
     | entièrement : les sondes reprennent le chemin du pilote, avec les ~10
     | tentatives que le framework enchaîne — donc ~31 s par sonde sur un hôte
     | qui ne résout plus (mesuré le 2026-08-23).
     |
     | ⚠️ N'EXISTE QUE POUR UN CAS, ET IL EST NOMMÉ : un hôte à plusieurs
     | enregistrements A. `fsockopen()` n'essaie qu'une adresse, donc le
     | portillon peut refuser alors qu'une autre répondrait — un `503` nommant
     | un backend joignable. Ce n'est pas un interrupteur de confort.
     */
    'probe_gate_enabled' => env('HEALTH_PROBE_GATE', true),
];
