<?php

declare(strict_types=1);

use Tests\Support\RepoFile;

/**
 * Story 1.10a — AC1 : un seul paquet entre, et rien de ce qui est installé ne recule.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CE TEST LIT `composer.json` ET JAMAIS `composer.lock`
 *
 * Le lock prouve qu'un paquet est *installé*. Il ne prouve jamais qu'il est
 * *voulu* : une dépendance transitive y figure exactement comme une dépendance
 * choisie. La leçon est datée — 2026-07-30, `livewire/livewire` — et elle est
 * transverse : la contrainte déclarée dans `require` est la seule trace d'une
 * décision.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI LES TROIS ASSERTIONS « INCHANGÉ » NE SONT PAS DU REMPLISSAGE
 *
 * La rédaction d'origine de cette story (`epics.md:1171`) prescrivait :
 *
 *     composer require filament/filament:^3.0 laravel/sanctum:^4.0 \
 *                      spatie/laravel-permission:^7.0
 *
 * Exécutée telle quelle sur ce dépôt, cette commande **rétrograde**
 * `spatie/laravel-permission` de `^8` (installé, 8.3.0) vers `^7` — c'est-à-dire
 * la bibliothèque dont dépendent les AC3 et AC4 de cette même story. Ce n'est
 * pas une hypothèse : `composer require` réécrit la contrainte de
 * `composer.json`, il ne la compare pas.
 *
 * Les assertions ci-dessous figent donc les trois versants du risque :
 * Filament **entre** en `^5` (ADR-0010 : v3 ne supporte pas Laravel 13), et
 * Sanctum, Permission et le framework **ne bougent pas**. Un futur `composer
 * require` maladroit — ou un copier-coller de la commande d'`epics.md` —
 * rougit ici avant d'atteindre la production.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⚠️ POURQUOI AUCUNE ASSERTION N'UTILISE `toHaveKey($clé, $message)`
 *
 * La signature de Pest est `toHaveKey($key, $value = null)` : le second
 * argument est la **valeur attendue**, pas un message. Écrit avec un message,
 * `toHaveKey('spatie/laravel-permission', 'AC3/AC4 en dépendent…')` compare la
 * phrase française à `'^8'` — l'assertion échoue pour une raison qui n'a rien
 * à voir avec ce qu'elle prétend vérifier. Observé rouge ici même le
 * 2026-08-09, avant correction.
 *
 * C'est la même famille que le piège de la Story 1.8 (`toContain()` variadique
 * sur les *needles*, où le message devenait un needle et rendait la négation
 * toujours vraie). Le remède du projet est identique et il est appliqué
 * ci-dessous : passer par une fonction PHP explicite — `array_key_exists()` —
 * et porter le message sur `toBeTrue()` / `toBeFalse()`, dont la signature
 * n'accepte QUE ça.
 *
 * @see docs/adr/ADR-0010-laravel-13-supersedes-filament-v3-lock.md
 */

/**
 * Section `require` de `src/composer.json`, décodée une fois.
 *
 * @return array<string, mixed>
 */
function adminPanelRequireSection(): array
{
    return RepoFile::section(RepoFile::json('src/composer.json'), 'require');
}

it('declares filament/filament in ^5 as a direct production dependency', function (): void {
    $require = adminPanelRequireSection();

    expect(array_key_exists('filament/filament', $require))
        ->toBeTrue(
            'Filament doit figurer dans `require` — le panel tourne en production, pas en dev.',
        );

    expect($require['filament/filament'])->toBe(
        '^5',
        'ADR-0010 : Filament v5. La v3 prescrite par epics.md ne supporte pas Laravel 13.',
    );
});

it('keeps filament out of require-dev', function (): void {
    $requireDev = RepoFile::section(RepoFile::json('src/composer.json'), 'require-dev');

    expect(array_key_exists('filament/filament', $requireDev))
        ->toBeFalse(
            'Le panel /admin est servi en production : `filament/filament` en require-dev le rendrait absent du déploiement.',
        );
});

it('republishes the Filament assets on every composer install', function (): void {
    /*
     * ─────────────────────────────────────────────────────────────────────────
     * QUESTION Q2 DE LA STORY 1.10a — TRANCHÉE : OUI, ET PAR NÉCESSITÉ
     *
     * `composer.json` est du JSON strict : il n'accepte pas de commentaire. Le
     * motif de cette ligne vit donc ici, à l'endroit où atterrira quiconque la
     * remettra en cause.
     *
     * La question posée était : faut-il ajouter `filament:upgrade` à
     * `post-autoload-dump`, alors que le 2026-08-09 ce projet a RETIRÉ
     * `boost:update` de `post-update-cmd` au motif qu'« un outil ne modifie pas
     * un fichier versionné en marge d'une commande composer » ?
     *
     * Le précédent ne s'applique pas, et l'AC8 de cette même story explique
     * pourquoi : les assets publiés par Filament sont **gitignorés**. Ils ne
     * sont donc pas versionnés, pas relus, et surtout PAS PRÉSENTS sur un
     * déploiement neuf.
     *
     * Ce qui transforme la question en réponse : sans cette ligne, un
     * `composer install --no-dev` en production produirait un panel servi
     * **sans CSS ni JS**. Et après un `composer update` qui monte filament/*,
     * les assets publiés seraient **périmés** par rapport à `vendor/` — une
     * panne silencieuse, puisque rien dans git ne la montrerait.
     *
     * Autrement dit : la décision d'exclure les assets (AC8) IMPOSE de les
     * republier (Q2). Les deux ne sont pas deux choix indépendants, c'est un
     * seul choix et sa conséquence. Séparer les deux, c'est reconstituer le
     * défaut.
     *
     * ⚠️ TROUVAILLE DE DÉVELOPPEMENT, 2026-08-09 : `php artisan filament:install
     * --panels` a ajouté cette ligne LUI-MÊME — et a par la même occasion
     * réécrit `composer.json` ENTIER en indentation 4 espaces, transformant un
     * ajout d'une ligne en un diff de 153 lignes où le changement de fond était
     * noyé. C'est exactement le motif qui avait fait retirer `boost:update`, en
     * pire : l'outil masquait sa propre modification. La mise en forme d'origine
     * a été restaurée à la main, et la ligne conservée DÉLIBÉRÉMENT, pour la
     * raison écrite ci-dessus — pas parce qu'un installeur l'avait décidé.
     *
     * ─────────────────────────────────────────────────────────────────────────
     * 🔴 Q2 RETRANCHÉE LE 2026-08-20 — LA COMMANDE ÉTAIT LA MAUVAISE (décision D6)
     *
     * La conclusion « il faut republier » tient. Le choix de `filament:upgrade`
     * pour le faire, non : `Filament\Support\Commands\UpgradeCommand::handle()`
     * enchaîne `AssetsCommand`, PUIS `config:clear`, `route:clear`, `view:clear`.
     * Or l'entrypoint de production exécute `config:cache`, `route:cache` et
     * `view:cache` au démarrage (`docker/php/scripts/docker-entrypoint.sh:79-81`).
     * Tout `composer install` ou `composer dump-autoload` sur un hôte déjà
     * démarré EFFAÇAIT donc silencieusement ses caches de production. La
     * justification de 40 lignes ci-dessus ne traitait que la republication
     * d'assets — elle ne savait pas ce que la commande faisait d'autre.
     *
     * `filament:assets` publie les assets et rien d'autre : c'est exactement ce
     * que Q2 avait décidé, sans l'effet de bord que Q2 n'avait pas vu.
     * `--no-interaction` est ajouté par la règle des guidelines Boost (toute
     * commande artisan scriptée), et parce qu'un `composer install` d'image
     * Docker n'a pas de terminal.
     *
     * ⚠️ ET LE GARDE CI-DESSOUS A CHANGÉ DE SUJET POUR LA MÊME RAISON. Il
     * assertait la présence d'une CHAÎNE dans `composer.json` — assertion
     * parfaitement verte sous `composer install --no-scripts`, employé par
     * `docker/php/Dockerfile:137`, `.github/workflows/security.yml:73,238` et
     * `docker.yml:328`, c'est-à-dire précisément dans le déploiement « panel sans
     * CSS ni JS » que son message d'échec décrit. Il vérifie désormais AUSSI que
     * la commande nommée existe réellement et qu'elle ne purge aucun cache.
     */
    $scripts = RepoFile::section(RepoFile::json('src/composer.json'), 'scripts');

    /** @var array<int, string> $postAutoloadDump */
    $postAutoloadDump = array_values(array_filter(
        is_array($scripts['post-autoload-dump'] ?? null) ? $scripts['post-autoload-dump'] : [],
        'is_string',
    ));

    $republishes = array_filter(
        $postAutoloadDump,
        static fn (string $script): bool => str_contains($script, 'filament:assets'),
    );

    expect($republishes)
        ->not->toBeEmpty(
            'post-autoload-dump ne republie plus les assets Filament. Or ils sont gitignorés (AC8) : '
                . 'un `composer install` sur un déploiement neuf servirait donc un panel sans CSS ni JS, '
                . 'et un `composer update` laisserait des assets périmés face à vendor/. '
                . 'Si cette ligne doit partir, les assets doivent redevenir versionnés — les deux vont ensemble.',
        );

    // ⛔ ET SURTOUT PAS `filament:upgrade` : elle republie les assets PUIS purge
    // `config`, `route` et `view`. Sur un hôte qui a exécuté `config:cache` au
    // démarrage, un simple `composer dump-autoload` lui retirait ses caches de
    // production, en silence. Décision D6, revue du 2026-08-20.
    expect(array_filter(
        $postAutoloadDump,
        static fn (string $script): bool => str_contains($script, 'filament:upgrade'),
    ))
        ->toBeEmpty(
            'post-autoload-dump appelle `filament:upgrade`, qui purge les caches de configuration, '
                . 'de routes et de vues à chaque `composer install`. L\'entrypoint de production les '
                . 'construit au démarrage : ils seraient effacés sans qu\'aucun log ne le dise. '
                . 'Utilisez `filament:assets`, qui publie les assets et rien d\'autre.',
        );

    // ⚠️ La seconde moitié — « la commande nommée EXISTE vraiment » — vit dans
    // `tests/Feature/FilamentPublishedAssetsTest.php` : elle demande une
    // application bootée, que ce fichier Unit n'a pas. Sans elle, l'assertion
    // ci-dessus n'observe qu'une orthographe dans un fichier JSON.
});

it('does not downgrade any package the admin panel depends on', function (): void {
    $require = adminPanelRequireSection();

    /**
     * Les trois contraintes que la commande d'`epics.md` aurait réécrites, et
     * le motif de chacune.
     *
     * @var array<string, array{0: string, 1: string}>
     */
    $frozen = [
        'spatie/laravel-permission' => ['^8', 'AC3/AC4 en dépendent ; epics.md demandait ^7, ce qui rétrograderait.'],
        'laravel/sanctum' => ['^4.0', 'AC9 : Sanctum est inerte et le reste ; la story n\'y touche pas.'],
        'laravel/framework' => ['^13', 'ADR-0010 : c\'est Laravel 13 qui a levé le verrou Filament v3.'],
    ];

    foreach ($frozen as $package => [$constraint, $why]) {
        expect(array_key_exists($package, $require))
            ->toBeTrue("{$package} a disparu de `require`. {$why}");
        expect($require[$package])
            ->toBe($constraint, "{$package} doit rester en {$constraint}. {$why}");
    }
});
