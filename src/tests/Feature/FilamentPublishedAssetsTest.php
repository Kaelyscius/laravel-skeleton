<?php

declare(strict_types=1);

use Illuminate\Support\Facades\Artisan;
use Tests\Support\RepoFile;

/**
 * Story 1.10a — AC8 : les assets publiés par Filament ne rentrent pas dans git,
 * et l'installation n'a rien réécrit du front.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CES FICHIERS SONT EXCLUS
 *
 * `filament:install` publie du CSS, du JS et des fontes sous `public/`. Ce sont
 * des fichiers DÉRIVÉS d'une version verrouillée dans `composer.lock`, au même
 * titre que `/public/build` (Vite) et `/public/fonts` (@fontsource, Story 1.9).
 * Les committer créerait une seconde source de vérité, capable de diverger de la
 * version installée sans qu'aucun test ne le voie.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⚠️ POURQUOI CE TEST INTERROGE `git check-ignore` ET NON LE TEXTE DU `.gitignore`
 *
 * Un test qui cherche la chaîne « /public/css/filament » dans le fichier
 * vérifie une ORTHOGRAPHE, pas un effet. Il resterait vert si la règle était
 * écrite dans une section désactivée, annulée par une négation `!` plus bas, ou
 * simplement mal placée. `git check-ignore` répond à la seule question qui
 * compte : ce chemin entrerait-il dans un commit ?
 *
 * C'est la même correction de visée que celle appliquée à l'AC2 pendant cette
 * story (lire le tableau que `bootstrap/providers.php` retourne plutôt que son
 * texte).
 */

/**
 * Vrai si git ignorerait ce chemin, relatif à la racine du dépôt.
 *
 * ⚠️ On interroge un chemin qui EXISTE réellement sur le disque : `check-ignore`
 * répond aussi pour des chemins inexistants, ce qui rendrait ce test vert sur
 * une règle qui ne couvre rien de réel.
 */
function gitIgnoresPath(string $relative): bool
{
    $root = RepoFile::root();
    $escapedRoot = escapeshellarg($root);
    $escapedPath = escapeshellarg($relative);

    exec("git -C {$escapedRoot} check-ignore -q -- {$escapedPath} 2>/dev/null", $output, $status);

    // check-ignore : 0 = ignoré, 1 = non ignoré, 128 = erreur.
    return $status === 0;
}

/**
 * Les répertoires d'assets que Filament a RÉELLEMENT publiés, relatifs à la
 * racine du dépôt.
 *
 * ⚠️ Dérivé du disque, jamais écrit à la main : une liste en dur avait fait
 * porter un tiers du garde-fou sur `public/fonts/filament`, qui n'existe pas
 * (finding Q7). `check-ignore` répondant « ignoré » pour n'importe quel chemin,
 * l'assertion était verte sans sujet.
 *
 * @return list<string>
 */
function publishedFilamentAssetDirectories(): array
{
    $found = [];

    foreach (glob(RepoFile::root() . '/src/public/*/filament', GLOB_ONLYDIR) ?: [] as $absolute) {
        $found[] = ltrim(str_replace(RepoFile::root(), '', $absolute), '/');
    }

    sort($found);

    return $found;
}

/**
 * La règle de `.gitignore` qui décide effectivement d'ignorer ce chemin, au
 * format `fichier:ligne:motif` rendu par `git check-ignore -v`.
 *
 * C'est la seule façon de distinguer « ignoré par la règle qu'on a écrite » de
 * « ignoré par une règle voisine posée pour autre chose » — distinction que
 * `check-ignore -q` efface, et sur laquelle le garde-fou précédent s'est fait
 * prendre (finding Q7).
 */
function gitIgnoreRuleFor(string $relative): string
{
    $escapedRoot = escapeshellarg(RepoFile::root());
    $escapedPath = escapeshellarg($relative);

    exec("git -C {$escapedRoot} check-ignore -v -- {$escapedPath} 2>/dev/null", $output, $status);

    return $status === 0 ? implode("\n", $output) : '';
}

it('has published Filament assets on disk to reason about', function (): void {
    // Sans ce préalable, tous les tests suivants seraient verts sur des chemins
    // vides — une exclusion parfaite de fichiers inexistants.
    expect(is_dir(RepoFile::root() . '/src/public/css/filament'))->toBeTrue(
        'Aucun asset Filament publié : lancez `php artisan filament:install --panels`.',
    );
    expect(is_dir(RepoFile::root() . '/src/public/js/filament'))->toBeTrue();
});

it('keeps every published Filament asset directory out of git', function (): void {
    /*
     * 🔴 UN TIERS DE CE GARDE-FOU NE GARDAIT RIEN — finding Q7, revue du
     *    2026-08-20, vérifié deux fois sur le disque.
     *
     * La liste contenait `src/public/fonts/filament`, décrit comme « Fontes Inter
     * embarquées par Filament ». CE RÉPERTOIRE N'EXISTE PAS : Filament v5 ne
     * publie ici que `public/css/filament` et `public/js/filament`. `check-ignore`
     * répond « ignoré » pour un chemin inexistant — ce que le docblock de
     * `gitIgnoresPath()` met précisément en garde de ne pas faire, quinze lignes
     * plus haut. Et la règle qui répondait n'était même pas la nouvelle :
     * `git check-ignore -v` désignait `src/.gitignore:24:/public/fonts`, héritée
     * de la Story 1.9.
     *
     * La liste est désormais DÉRIVÉE DU DISQUE : ce qui est publié est ce qui est
     * vérifié, et rien d'autre. Une quatrième publication future y entrera d'elle-
     * même ; un répertoire qui disparaît n'y laissera pas d'assertion fantôme.
     */
    $published = publishedFilamentAssetDirectories();

    expect($published)
        ->not->toBe([], 'Aucun asset Filament publié : `filament:install --panels` n\'a pas tourné.');

    foreach ($published as $path) {
        expect(gitIgnoresPath($path))
            ->toBeTrue(
                "{$path} n'est pas ignoré par git. Ces fichiers sont dérivés de la version "
                        . 'verrouillée dans composer.lock : les suivre créerait une seconde source de vérité.',
            );
    }
});

it('does not let any published Filament asset rely on an inherited rule alone', function (): void {
    /*
     * ⚠️ CE TEST A CHANGÉ DE SUJET LE 2026-08-20 (finding Q7).
     *
     * Il exigeait `str_contains($gitignore, '/public/fonts/filament')` — c'est-à-
     * dire une ORTHOGRAPHE, pour un répertoire qui n'existe pas, en s'appuyant
     * sur un raisonnement (« la règle @fontsource pourrait disparaître ») qui
     * était juste mais dont le sujet était faux. Il vérifiait donc la présence
     * d'une ligne, ce que le même fichier condamne vingt lignes plus haut.
     *
     * La propriété qui compte est la même, mais posée sur ce qui existe : chaque
     * répertoire RÉELLEMENT publié doit être couvert par une règle qui NOMME
     * Filament, et non par une règle voisine posée pour autre chose — parce que
     * `check-ignore` ne distingue pas les deux, et que retirer la règle voisine
     * en toute bonne foi remettrait les assets sous suivi sans qu'un test bouge.
     *
     * `check-ignore -v` rend la règle qui a décidé : c'est elle qu'on inspecte.
     */
    foreach (publishedFilamentAssetDirectories() as $path) {
        // ⚠️ PAS `toContain('filament', $message)` : pour une chaîne, le 2ᵉ
        // argument de `toContain()` est une SECONDE AIGUILLE, pas un message —
        // le test cherchait alors la phrase d'erreur dans la sortie de git et
        // rougissait sur lui-même. Ce dépôt a déjà payé ce piège avec
        // `toHaveKey($clé, $message)`. Constaté ici le 2026-08-20.
        $rule = gitIgnoreRuleFor($path);

        expect(str_contains($rule, 'filament'))
            ->toBeTrue(
                "L'exclusion de {$path} repose sur la règle [{$rule}], qui ne nomme pas Filament : "
                    . 'retirer cette règle-là (posée pour autre chose) remettrait ces assets '
                    . 'sous suivi git sans avertissement.',
            );
    }
});

it('left the frontend build configuration untouched', function (): void {
    /*
     * Piège armé par la Story 1.9 et recopié mot pour mot dans cette story :
     * « Vérifier que l'installation de Filament v5 (1.10a) n'a pas réécrit la
     * configuration Vite sous les preloads. » C'est ici que le contrôle s'exécute.
     *
     * ─────────────────────────────────────────────────────────────────────────
     * 🔴 POURQUOI LE SHA N'EST PLUS ÉCRIT EN DUR — finding Q4, revue du 2026-08-20
     *
     * La version précédente faisait `git diff --name-only 3f345f2 -- …` et
     * assertait `$status === 0`. Deux défauts indépendants, tous deux vérifiés :
     *
     *   1. Le job de tests de `.github/workflows/ci.yml` ne pose PAS de
     *      `fetch-depth` (défaut : 1) — seul le job gitleaks pose `fetch-depth: 0`.
     *      Sur un clone superficiel, l'objet `3f345f2` est absent, `git diff` sort
     *      **128**, et le test rougit pour une raison sans rapport avec le front.
     *      Il ne passait aujourd'hui QUE parce que `3f345f2` se trouvait être HEAD.
     *
     *   2. Une fois la story committée, toute évolution légitime ultérieure du
     *      front (un `npm audit fix` suffit) le rend DÉFINITIVEMENT rouge, avec un
     *      message accusant l'installeur Filament d'un changement qu'il n'a pas
     *      fait. Le docblock argumentait contre une empreinte figée… puis figeait
     *      un commit.
     *
     * La propriété visée n'a jamais eu besoin de git : ce qu'on veut savoir, c'est
     * que le front porte TOUJOURS ce que les Stories 1.8/1.9 y ont mis et que
     * `filament:install` aurait pu écraser, et qu'il ne porte RIEN de Filament. On
     * l'interroge donc directement. Un test qui ne dépend d'aucun historique ne
     * peut être ni rouge par infrastructure, ni rouge par ancienneté.
     */
    $vite = RepoFile::read('src/vite.config.js');

    expect(str_contains($vite, 'laravel-vite-plugin'))
        ->toBeTrue('vite.config.js ne charge plus laravel-vite-plugin : le front a été réécrit.');
    expect(str_contains($vite, 'resources/css/app.css'))
        ->toBeTrue('vite.config.js ne déclare plus l\'entrée resources/css/app.css.');

    // Les tokens de la Story 1.8 : c'est ce que `filament:install` aurait pu
    // emporter en réécrivant la feuille de style d'entrée.
    expect(str_contains(RepoFile::read('src/resources/css/app.css'), 'tokens.css'))
        ->toBeTrue('app.css n\'importe plus tokens.css : les design tokens de la 1.8 ont sauté.');

    // Les fontes self-hostées de la Story 1.9.
    expect(json_decode(RepoFile::read('src/resources/fonts.json'), true))
        ->not->toBeNull('fonts.json n\'est plus un JSON lisible : la 1.9 a été écrasée.');

    // Et la contre-preuve, qui est la propriété d'AC8 elle-même : l'installeur
    // n'a RIEN ajouté au front.
    foreach (['src/vite.config.js', 'src/resources/css/app.css', 'src/package.json'] as $frontFile) {
        expect(stripos(RepoFile::read($frontFile), 'filament'))
            ->toBeFalse(
                "{$frontFile} mentionne Filament : l'installeur a touché au front, "
                    . 'ce qu\'aucun AC de cette story n\'autorise (AC8).',
            );
    }
});

it('names a Filament command that actually exists in post-autoload-dump', function (): void {
    /*
     * ⚠️ LA MOITIÉ QUI MANQUAIT AU GARDE DE Q2/D6.
     *
     * `AdminPanelDependenciesTest` assert que `post-autoload-dump` contient
     * `filament:assets`. C'est une orthographe dans un fichier JSON : verte sous
     * `composer install --no-scripts` — employé par `docker/php/Dockerfile:137`,
     * `.github/workflows/security.yml:73,238` et `docker.yml:328` —, c'est-à-dire
     * exactement dans le déploiement « panel sans CSS ni JS » que son message
     * d'échec décrit. Finding D6, revue du 2026-08-20.
     *
     * Ici on demande à l'application, bootée, si la commande existe.
     */
    $scripts = RepoFile::section(RepoFile::json('src/composer.json'), 'scripts');

    /** @var array<int, string> $postAutoloadDump */
    $postAutoloadDump = array_values(array_filter(
        is_array($scripts['post-autoload-dump'] ?? null) ? $scripts['post-autoload-dump'] : [],
        'is_string',
    ));

    $registered = array_keys(Artisan::all());

    foreach ($postAutoloadDump as $script) {
        if (preg_match('/artisan\s+([a-z0-9:_-]+)/i', $script, $matches) !== 1) {
            continue;
        }

        expect(in_array($matches[1], $registered, true))
            ->toBeTrue(
                "post-autoload-dump appelle `php artisan {$matches[1]}`, commande qui n'est "
                    . 'enregistrée nulle part : chaque `composer install` échouera — ou, sous '
                    . '`--no-scripts`, ne fera rien pendant que le garde de composer.json reste vert.',
            );
    }
});
