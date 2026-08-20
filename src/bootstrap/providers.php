<?php

/*
 * ⚠️ CE FICHIER EST INCONDITIONNEL — rien de ce qui y figure ne peut être
 * éteint par un `MODULE_*_ENABLED`.
 *
 * `CoreServiceProvider` y est *par décision* (ADR-0009 : le cœur est
 * transversal). `AppServiceProvider` y est parce que c'est LUI qui enregistre
 * ensuite les providers de module d'après `config/modules.php`.
 *
 * ⛔ `php artisan filament:install --panels` ajoute ici son
 * `AdminPanelProvider`. Il a été RETIRÉ le 2026-08-09 (Story 1.10a) : mesuré
 * avant retrait, `MODULE_ADMIN_ENABLED=false` servait quand même `/admin` en
 * 302 au lieu de 404 — ADR-0009 §Conséquences promet l'inverse. Le panel est
 * désormais enregistré par `AdminServiceProvider::register()`.
 *
 * Gardé par `tests/Feature/AdminPanelModuleGateTest.php`. Si un futur
 * `filament:install` le réintroduit, ce test rougit.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * 📌 L'ORDRE DE CE TABLEAU A CHANGÉ LE 2026-08-09, ET LE SILENCE ÉTAIT LE DÉFAUT
 *
 * L'ordre était `AppServiceProvider, CoreServiceProvider` ; il est désormais
 * `CoreServiceProvider, AppServiceProvider`. C'est une CORRECTION —
 * ADR-0009:102 exige que le cœur soit enregistré avant les modules, puisque
 * `AppServiceProvider::register()` enregistre les providers de module et que
 * ceux-ci peuvent dépendre des liaisons du cœur (`CurrentStreamer`, notamment).
 *
 * ⚠️ Ce changement était passé sans un mot : ni dans ce commentaire de 18 lignes
 * — qui expliquait pourquoi chaque entrée est là, jamais pourquoi l'ordre avait
 * bougé —, ni dans la File List, ni dans le Change Log. Dans un diff où chaque
 * ligne porte trois paragraphes, un changement de comportement non commenté est
 * la seule chose que personne ne relira. Relevé en revue (P6 le 2026-08-10, Q11
 * le 2026-08-20, deux fois de suite).
 *
 * ⛔ Aucun test n'observe l'ORDRE — les garde-fous d'activation n'observent que
 * l'ENSEMBLE des providers chargés. Cette note est donc, aujourd'hui, la seule
 * chose qui empêche quelqu'un de le réinverser en croyant ranger.
 */

return [
    App\Core\Providers\CoreServiceProvider::class,
    App\Providers\AppServiceProvider::class,
];
