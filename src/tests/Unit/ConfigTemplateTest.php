<?php

declare(strict_types=1);

use Tests\Support\RepoFile;
use Tests\Support\ShellProbe;

/*
|------------------------------------------------------------------------------
| Gabarits de configuration versionnés — Story 2.5
|------------------------------------------------------------------------------
|
| 🔴 LE DÉFAUT MESURÉ (2026-08-28, conteneurs `laravel-app_php` et
| `laravel-app_apache`). `docker/php/conf/php.ini:5` annonçait
| `memory_limit = 256M` ; la valeur EFFECTIVE valait **`4G`**, parce que
| `conf.d/composer-optimizations.ini` est lu APRÈS `php.ini` et gagne. Le seul
| fichier qu'un fork-streamer serait allé éditer pour régler PHP mentait déjà —
| et l'éditer aurait modifié un fichier VERSIONNÉ, bind-monté en écriture.
|
| ⚖️ CE QUE CE FICHIER GARDE, ET CE QU'IL NE PEUT PAS GARDER.
| Ici vivent les invariants STATIQUES : les cibles ne sont bind-montées nulle
| part, la liste d'autorisation de `envsubst` couvre exactement les variables
| des gabarits, chaque variable a un défaut posé CÔTÉ SHELL, la cible du rendu
| trie après tout ce que l'image pose déjà dans `conf.d`, et `gettext` est dans
| les deux images. Plus quatre sondes de COMPORTEMENT, qui appellent réellement
| la fonction de rendu sur un bac à sable.
|
| ⛔ CE QUI N'EST PAS ICI, ET POURQUOI. La VALEUR EFFECTIVE — `ini_get` via FPM
| d'un côté, via la CLI de l'autre — ne peut pas être mesurée depuis Pest : la
| suite tourne sous un SEUL SAPI, `cli`, et c'est précisément la distinction
| FPM/CLI qui fait toute la story. Elle est mesurée par
| `tests/bats/config-template.bats`, qui démarre un vrai `php-fpm` et
| l'interroge en FastCGI. Un garde qui lirait le CONTENU du fichier rendu en
| guise de preuve serait le 40ᵉ garde-fou silencieux de ce dépôt.
|
| ⚖️ ENVIRONNEMENT DE LA MESURE — L'INTERPRÉTEUR, PAS LA MACHINE. Les sondes
| lancent le sujet sous `ShellProbe::posixShell()` : `docker-entrypoint.sh` de
| `php` porte `#!/bin/sh` et l'image est `php:8.5-fpm-alpine`, où `/bin/sh` est
| **BusyBox ash**. Le binaire `envsubst` est lui aussi ÉPINGLÉ (`ENVSUBST_BIN`),
| pour que le refus « gettext absent » soit éprouvable sans démonter le `PATH`
| de la machine qui exécute Pest.
|
*/

/**
 * Le nom de fichier réellement rendu par l'entrypoint php pour une variable
 * de répertoire donnée (`PHP_CONF_D`, `PHP_FPM_D`).
 *
 * ⛔ POURQUOI L'EXTRAIRE PLUTÔT QUE DE L'ÉCRIRE EN DUR. Les deux gardes de tri
 * ci-dessous comparaient un littéral du TEST à ses concurrents — une propriété
 * vraie de la chaîne écrite ici, jamais de celle qu'exécute la production.
 * Mesuré le 2026-08-28 : renommer la cible en `zzz-fork.ini`, qui trie
 * EXACTEMENT comme `zz-fork.ini`, faisait rougir le garde ; il reconnaissait
 * donc un texte, pas un ordre de scan — alors que son commentaire affirmait
 * l'inverse. En dérivant le nom du sujet, `99-fork.ini` rougit parce qu'il
 * PERD le tri, et `zzz-fork.ini` reste vert parce qu'il le gagne.
 */
function cibleRendue(string $variableRepertoire): string
{
    $entrypoint = RepoFile::read('docker/php/scripts/docker-entrypoint.sh');

    $trouve = preg_match(
        '/rendre_gabarit\s+"[^"]+"\s+"\$' . preg_quote($variableRepertoire, '/') . '\/([A-Za-z0-9._-]+)"/',
        $entrypoint,
        $capture,
    );

    if ($trouve !== 1) {
        throw new RuntimeException(
            "Aucun appel `rendre_gabarit` vers \${$variableRepertoire} dans l’entrypoint php : "
            . 'le garde de tri ne peut pas mesurer une cible qui n’existe pas.',
        );
    }

    return $capture[1];
}

/**
 * Les variables `${NOM}` réellement écrites dans un gabarit.
 *
 * @return list<string>
 */
function variablesDuGabarit(string $relative): array
{
    preg_match_all('/\$\{([A-Z][A-Z0-9_]*)\}/', RepoFile::read($relative), $trouvees);

    $noms = array_values(array_unique($trouvees[1]));
    sort($noms);

    return $noms;
}

/**
 * La liste d'autorisation passée à `envsubst`, LUE dans l'entrypoint.
 *
 * ⛔ Elle est dérivée du fichier, jamais recopiée : écrite en dur ici, elle
 * resterait « juste » après une variable ajoutée au gabarit et non autorisée —
 * c'est-à-dire verte sur la directive qui ne serait plus jamais substituée.
 *
 * @return list<string>
 */
function listeAutorisation(string $entrypoint, string $variable): array
{
    $source = RepoFile::read($entrypoint);

    if (preg_match('/^' . preg_quote($variable, '/') . "='([^']*)'$/m", $source, $bloc) !== 1) {
        throw new RuntimeException("Liste d'autorisation « {$variable} » introuvable dans {$entrypoint}.");
    }

    preg_match_all('/\$\{([A-Z][A-Z0-9_]*)\}/', $bloc[1], $trouvees);

    $noms = array_values(array_unique($trouvees[1]));
    sort($noms);

    return $noms;
}

/**
 * Chemins CÔTÉ CONTENEUR de tous les bind-mounts déclarés, tous fichiers
 * compose confondus.
 *
 * @return list<string>
 */
function cheminsMontes(): array
{
    $cibles = [];

    foreach (glob(RepoFile::root() . '/docker-compose*.yml') ?: [] as $chemin) {
        $relatif = basename($chemin);

        foreach (RepoFile::section(RepoFile::yaml($relatif), 'services') as $definition) {
            if (! is_array($definition) || ! isset($definition['volumes']) || ! is_array($definition['volumes'])) {
                continue;
            }

            foreach ($definition['volumes'] as $volume) {
                /*
                 * ⛔ LES DEUX FORMES, PAS SEULEMENT LA COURTE. Compose accepte
                 * « hôte:conteneur:mode » (chaîne) ET la forme longue
                 * (`type: bind` / `target:`). Ne lire que la première rendait
                 * l'assertion centrale de ce fichier — « aucune cible de rendu
                 * n'est bind-montée » — vraie PAR OMISSION : il suffisait de
                 * réécrire un montage en forme longue pour qu'il devienne
                 * invisible au garde.
                 */
                if (is_string($volume)) {
                    $morceaux = explode(':', $volume);

                    if (count($morceaux) >= 2) {
                        $cibles[] = $morceaux[1];
                    }

                    continue;
                }

                if (is_array($volume) && isset($volume['target']) && is_string($volume['target'])) {
                    $cibles[] = $volume['target'];
                }
            }
        }
    }

    return array_values(array_unique($cibles));
}

/**
 * La valeur par DÉFAUT d'une variable de chemin, lue dans un entrypoint.
 *
 * Les chemins interdits au bind-mount sont ainsi DÉRIVÉS du sujet : écrits en
 * dur dans le test, ils resteraient « justes » après un déplacement de cible,
 * c'est-à-dire verts sur un rendu qui aurait recommencé à viser le dépôt.
 */
function repertoireParDefaut(string $entrypoint, string $variable): string
{
    $motif = '/^' . preg_quote($variable, '/') . '="\$\{' . preg_quote($variable, '/') . ':-([^}]+)\}"$/m';

    if (preg_match($motif, RepoFile::read($entrypoint), $capture) !== 1) {
        throw new RuntimeException("Aucun défaut pour {$variable} dans {$entrypoint}.");
    }

    return $capture[1];
}

/**
 * Les couples « gabarit → cible » RÉELLEMENT appelés dans un entrypoint.
 *
 * ⛔ Un `preg_match` simple ne voit que le PREMIER appel : une troisième cible
 * ajoutée plus bas échapperait à toutes les assertions d'ordre et de montage.
 * On les prend TOUS, et l'appelant asserte sur chacun.
 *
 * @return list<array{gabarit: string, cible: string}>
 */
function ciblesRendues(string $entrypoint): array
{
    preg_match_all(
        '/^\s*rendre_gabarit\s+"([^"]+)"\s+"([^"]+)"/m',
        RepoFile::read($entrypoint),
        $appels,
        PREG_SET_ORDER,
    );

    return array_map(
        static fn (array $appel): array => [
            'gabarit' => $appel[1],
            'cible' => $appel[2],
        ],
        $appels,
    );
}

/**
 * Les fichiers que l'image dépose dans `conf.d`, sous LES DEUX écritures.
 *
 * ⛔ `$PHP_INI_DIR/conf.d/…` est déjà employé par le même Dockerfile
 * (`:94`, `:254-255`) : un motif littéral `/usr/local/etc/php/conf.d/` rate ces
 * voisins-là, et un concurrent écrit ainsi rendrait la cible perdante sans
 * faire rougir quoi que ce soit.
 *
 * @return list<string>
 */
function voisinsConfD(): array
{
    $noms = [];

    preg_match_all(
        '#(?:/usr/local/etc/php|\$PHP_INI_DIR|\$\{PHP_INI_DIR\})/conf\.d/([A-Za-z0-9._-]+)#',
        RepoFile::read('docker/php/Dockerfile'),
        $duDockerfile,
    );
    $noms = array_merge($noms, $duDockerfile[1]);

    foreach (cheminsMontes() as $cible) {
        if (str_starts_with($cible, '/usr/local/etc/php/conf.d/')) {
            $noms[] = basename($cible);
        }
    }

    return array_values(array_unique(array_filter(
        $noms,
        static fn (string $nom): bool => $nom !== '' && ! str_contains($nom, '*'),
    )));
}

/**
 * Fragment shell qui SOURCE l'entrypoint php et appelle `rendre_gabarit` dans
 * un bac à sable sous `/tmp`.
 */
function sondeRendu(string $corps): string
{
    return <<<BASH
        set -e
        bac="\$(mktemp -d)"
        # Même garde que les sondes voisines : un test qui échoue est un
        # incident, un test qui salit le dépôt en échouant en est deux.
        case "\$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
        esac

        mkdir -p "\$bac/bin" "\$bac/conf.d" "\$bac/fpm.d"

        # ⛔ LES CIBLES VIVENT DANS LE BAC. Sans ces trois chemins, la sonde
        # écrirait dans le `conf.d` RÉEL de la machine qui exécute Pest.
        PHP_TEMPLATE_DIR="\$GABARITS"
        PHP_CONF_D="\$bac/conf.d"
        PHP_FPM_D="\$bac/fpm.d"
        export PHP_TEMPLATE_DIR PHP_CONF_D PHP_FPM_D

        LARAVEL_ENTRYPOINT_SOURCE_ONLY=true
        export LARAVEL_ENTRYPOINT_SOURCE_ONLY
        . "\$ENTRYPOINT"

        GABARIT="\$PHP_TEMPLATE_DIR/php-fork.ini.template"
        CIBLE="\$PHP_CONF_D/zz-fork.ini"

        {$corps}

        rm -rf "\$bac"
        BASH;
}

/**
 * @return array<string, string>
 */
function environnementSonde(): array
{
    return [
        'ENTRYPOINT' => RepoFile::root() . '/docker/php/scripts/docker-entrypoint.sh',
        'GABARITS' => RepoFile::root() . '/docker/php/conf',
        'SH' => ShellProbe::posixShell()['path'],
    ];
}

// =============================================================================
// FAMILLE 1 — invariants STATIQUES
// =============================================================================

it('installe `gettext` dans les DEUX images, sans quoi rien n’est rendu', function (): void {
    /*
     * ⛔ MUTATION PRÉVUE PAR L'AC5 : retirer `gettext` d'un des deux Dockerfiles.
     * Sans ce garde, l'entrypoint refuserait de démarrer en production sans
     * qu'aucun test ne l'ait dit — et le refus, lui, est correct : c'est bien
     * la CONSTRUCTION qui aurait régressé.
     */
    foreach (['docker/php/Dockerfile', 'docker/apache/Dockerfile'] as $dockerfile) {
        expect(RepoFile::read($dockerfile))
            ->toMatch('/^\s*gettext \\\\$/m', "{$dockerfile} n’installe plus « gettext » : « envsubst » manquera et l’entrypoint refusera de démarrer.");
    }
});

it('copie les gabarits php HORS de leurs répertoires cibles', function (): void {
    // ⚖️ Un gabarit copié dans `conf.d` serait lu PAR PHP en plus d'être rendu :
    // deux fichiers pour une décision, dont un contenant des `${…}` littéraux.
    $dockerfile = RepoFile::read('docker/php/Dockerfile');

    expect($dockerfile)
        ->toContain('COPY docker/php/conf/php-fork.ini.template /usr/local/etc/php/templates/')
        ->toContain('COPY docker/php/conf/php-fpm-fork.conf.template /usr/local/etc/php/templates/');

    // ⚠️ Deux `expect` distincts : `->not` ne se rechaîne pas après un
    // `toContain` (PHPStan niveau 10 le voit, l'exécution non).
    expect($dockerfile)
        ->not->toContain('.template /usr/local/etc/php/conf.d');
    expect($dockerfile)
        ->not->toContain('.template /usr/local/etc/php-fpm.d');
});

it('la cible du rendu `conf.d` TRIE APRÈS tout ce que l’image y pose déjà', function (): void {
    /*
     * 🔴 L'AC1 D'ORIGINE PRESCRIVAIT `99-fork.ini`, « dernier dans l'ordre
     * alphabétique ». C'est faux : PHP scanne `conf.d` par ordre ASCII et `9`
     * PRÉCÈDE les lettres. Mesuré dans les deux sens le 2026-08-28 —
     * `99-fork.ini` → effectif `4G` (il perd contre
     * `composer-optimizations.ini`), `zz-fork.ini` → `512M` (il gagne).
     *
     * ⛔ MUTATION PRÉVUE PAR L'AC5 : renommer la cible en `99-fork.ini`.
     * Ce garde rougit, et il rougit pour la BONNE raison — pas parce qu'un
     * littéral a changé, mais parce que l'ordre de scan replacerait le fichier
     * avant un concurrent réel.
     */
    $voisins = voisinsConfD();

    // Anti-vacuité : sans concurrent, « trier après » ne dit rien.
    expect(count($voisins))
        ->toBeGreaterThanOrEqual(3);

    // ⛔ ET LE CONCURRENT QUI COMPTE EST NOMMÉ. Sans cette ligne, un relevé de
    // voisins qui cesserait de voir `composer-optimizations.ini` — c'est
    // exactement ce que faisait le motif littéral avant correction — laisserait
    // le garde vert sur trois voisins sans importance.
    expect($voisins)
        ->toContain('composer-optimizations.ini');

    // ⛔ TOUTES LES CIBLES `conf.d`, pas seulement la première : un troisième
    // `rendre_gabarit` ajouté plus bas échapperait à un `preg_match` simple.
    $cibles = array_values(array_filter(
        ciblesRendues('docker/php/scripts/docker-entrypoint.sh'),
        static fn (array $appel): bool => str_starts_with($appel['cible'], '$PHP_CONF_D/'),
    ));

    expect(count($cibles))
        ->toBeGreaterThanOrEqual(1, 'Aucun rendu vers conf.d : le garde de tri ne mesure rien.');

    foreach ($cibles as $appel) {
        $cible = basename($appel['cible']);

        foreach ($voisins as $voisin) {
            expect(strcmp($cible, $voisin))
                ->toBeGreaterThan(0, "« {$cible} » est scanné AVANT « {$voisin} » : il perdrait contre lui, et le gabarit serait correct dans un fichier inerte.");
        }
    }
});

it('la cible du fragment de pool trie après `zz-docker.conf`, posé par l’image officielle', function (): void {
    // ⚠️ `zz-docker.conf` n'est pas dans ce dépôt : il vient de
    // `php:8.5-fpm-alpine` (mesuré le 2026-08-28, il y pose `listen = 9000`).
    // Le littéral est donc assumé, et sa provenance est écrite.
    $cibles = array_values(array_filter(
        ciblesRendues('docker/php/scripts/docker-entrypoint.sh'),
        static fn (array $appel): bool => str_starts_with($appel['cible'], '$PHP_FPM_D/'),
    ));

    expect(count($cibles))
        ->toBeGreaterThanOrEqual(1, 'Aucun rendu vers php-fpm.d : le garde de tri ne mesure rien.');

    foreach ($cibles as $appel) {
        expect(strcmp(basename($appel['cible']), 'zz-docker.conf'))
            ->toBeGreaterThan(0);
    }
});

it('AUCUNE cible de rendu n’est bind-montée, et le gabarit apache l’est en LECTURE SEULE', function (): void {
    /*
     * ⛔ C'EST LA CONTRAINTE CENTRALE DE LA STORY. Un rendu qui viserait un
     * bind-mount réécrirait un fichier VERSIONNÉ à chaque démarrage — la
     * famille de défaut que cette story existe pour supprimer, et que
     * `php.ini` (monté en ÉCRITURE, `docker-compose.yml:44`) rendait possible.
     */
    /*
     * ⛔ LES CHEMINS INTERDITS SONT DÉRIVÉS DU SUJET, PAS RECOPIÉS. Écrits en
     * dur, ils resteraient « justes » après un déplacement de cible — donc
     * verts sur un rendu qui aurait recommencé à viser le dépôt.
     */
    $entrypointPhp = 'docker/php/scripts/docker-entrypoint.sh';
    $entrypointApache = 'docker/apache/scripts/docker-entrypoint.sh';

    $repertoires = [
        '$PHP_CONF_D/' => repertoireParDefaut($entrypointPhp, 'PHP_CONF_D'),
        '$PHP_FPM_D/' => repertoireParDefaut($entrypointPhp, 'PHP_FPM_D'),
    ];

    $interdits = [];

    foreach (ciblesRendues($entrypointPhp) as $appel) {
        foreach ($repertoires as $prefixe => $repertoire) {
            if (str_starts_with($appel['cible'], $prefixe)) {
                /*
                 * ⚖️ ON N'INTERDIT QUE LES FICHIERS CIBLES, PAS LEUR
                 * RÉPERTOIRE. Monter un VOISIN dans `conf.d` est légitime et
                 * déjà pratiqué (`opcache.ini`, `xdebug.ini`) ; ce qui ne l'est
                 * pas, c'est de monter le RÉPERTOIRE — et ce cas-là est
                 * attrapé par le sens ancêtre ci-dessous, sans faire rougir les
                 * montages de voisins.
                 */
                $interdits[] = $repertoire . '/' . basename($appel['cible']);
            }
        }
    }

    $rendusApache = repertoireParDefaut($entrypointApache, 'VHOST_RENDERED_DIR');
    $interdits[] = $rendusApache . '/laravel.conf';
    $interdits[] = repertoireParDefaut($entrypointApache, 'HTTPD_CONF');

    $interdits = array_values(array_unique($interdits));

    // Anti-vacuité : les cibles ont bien été retrouvées dans les entrypoints.
    expect(count($interdits))
        ->toBeGreaterThanOrEqual(4, 'Les cibles de rendu n’ont pas été dérivées : ce garde ne compare rien.');

    $montes = cheminsMontes();

    // Anti-vacuité : la lecture des volumes fonctionne bel et bien.
    expect($montes)
        ->toContain('/var/www/html');

    foreach ($montes as $cible) {
        foreach ($interdits as $interdit) {
            /*
             * 🔴 LE SENS DESCENDANT SEUL LAISSAIT PASSER LE CAS LE PLUS
             * PROBABLE, ET C'EST DÉMONTRÉ. La version précédente ne demandait
             * que « le montage EST-il la cible, ou dessous ? ». Elle ne
             * demandait jamais « le montage CONTIENT-il la cible ? ».
             * Consolider les montages existants en
             * `./docker/php/conf.d:/usr/local/etc/php/conf.d` — un geste de
             * rangement parfaitement naturel — ferait rendre `zz-fork.ini`
             * DANS L'ARBRE DU DÉPÔT à chaque démarrage, et le garde restait
             * VERT. Les deux sens sont donc testés.
             */
            $montageEstSousLaCible = $cible === $interdit || str_starts_with($cible, $interdit . '/');
            $montageContientLaCible = str_starts_with($interdit, $cible . '/');

            expect($montageEstSousLaCible)
                ->toBeFalse("« {$cible} » est bind-monté : le rendu y écrirait dans un fichier du dépôt à chaque démarrage.");

            expect($montageContientLaCible)
                ->toBeFalse("Le bind-mount « {$cible} » CONTIENT la cible de rendu « {$interdit} » : le rendu écrirait dans l’arbre du dépôt à chaque démarrage.");
        }
    }

    // …et la contrepartie POSITIVE : le répertoire des gabarits apache est
    // monté, et il est `:ro`. C'est ce `:ro` qui rend le rendu sur place
    // impossible — et donc qui justifie la cible séparée.
    expect(RepoFile::read('docker-compose.yml'))
        ->toContain('./docker/apache/conf/sites-enabled:/etc/apache2/sites-enabled:ro');
});

it('gabarit ≠ cible, et le gabarit du vhost sort du glob `*.conf`', function (): void {
    $racine = RepoFile::root();

    expect(is_file($racine . '/docker/apache/conf/sites-enabled/laravel.conf.template'))
        ->toBeTrue('Le gabarit de vhost a disparu.');

    // ⛔ SI `laravel.conf` REVENAIT, il serait ramassé par un `Include *.conf`
    // et l'on servirait DEUX `<VirtualHost>` concurrents pour le même port.
    expect(is_file($racine . '/docker/apache/conf/sites-enabled/laravel.conf'))
        ->toBeFalse('`laravel.conf` est de retour dans le répertoire monté : deux VirtualHost concurrents.');

    foreach (glob($racine . '/docker/apache/conf/sites-enabled/*') ?: [] as $fichier) {
        expect(str_ends_with($fichier, '.conf'))
            ->toBeFalse("« {$fichier} » se termine par .conf : il rentrerait dans le glob d’un Include.");
    }

    // Les trois gabarits php/apache ne peuvent pas être leur propre cible.
    $entrypointPhp = RepoFile::read('docker/php/scripts/docker-entrypoint.sh');
    expect($entrypointPhp)
        ->toContain('$PHP_TEMPLATE_DIR/php-fork.ini.template');
    expect($entrypointPhp)
        ->not->toContain('PHP_TEMPLATE_DIR="/usr/local/etc/php/conf.d"');

    $entrypointApache = RepoFile::read('docker/apache/scripts/docker-entrypoint.sh');
    expect($entrypointApache)
        ->toContain('VHOST_TEMPLATE="${VHOST_TEMPLATE:-/etc/apache2/sites-enabled/laravel.conf.template}"')
        ->toContain('VHOST_RENDERED_DIR="${VHOST_RENDERED_DIR:-/usr/local/apache2/conf/sites-rendered}"');
});

it('la liste d’autorisation `envsubst` couvre EXACTEMENT les variables des gabarits', function (): void {
    /*
     * ⛔ MUTATION PRÉVUE PAR L'AC5 : supprimer la liste d'autorisation.
     * Sans premier argument, `envsubst` substitue TOUTE variable de
     * l'environnement présente dans le gabarit — un `$HOME`, un secret exporté
     * par Compose passeraient dans un fichier de configuration.
     *
     * ⚖️ ET L'ÉGALITÉ EST DANS LES DEUX SENS. Une variable de gabarit absente
     * de la liste ne serait JAMAIS substituée (directive rendue avec un `${…}`
     * littéral) ; une variable listée mais absente des gabarits est une
     * autorisation sans objet, qui survivrait à la suppression de la directive.
     */
    $cas = [
        'php' => [
            'entrypoint' => 'docker/php/scripts/docker-entrypoint.sh',
            'liste' => 'PHP_TEMPLATE_VARS',
            'gabarits' => [
                'docker/php/conf/php-fork.ini.template',
                'docker/php/conf/php-fpm-fork.conf.template',
            ],
        ],
        'apache' => [
            'entrypoint' => 'docker/apache/scripts/docker-entrypoint.sh',
            'liste' => 'VHOST_VARS',
            'gabarits' => ['docker/apache/conf/sites-enabled/laravel.conf.template'],
        ],
    ];

    foreach ($cas as $nom => $definition) {
        $duGabarit = [];

        foreach ($definition['gabarits'] as $gabarit) {
            $duGabarit = array_merge($duGabarit, variablesDuGabarit($gabarit));
        }

        $duGabarit = array_values(array_unique($duGabarit));
        sort($duGabarit);

        // Anti-vacuité : un gabarit SANS variable rendrait ce test vert en ne
        // comparant que deux listes vides — donc vert sur un gabarit qui aurait
        // cessé d'être réglable.
        expect(count($duGabarit))
            ->toBeGreaterThanOrEqual(2, "Les gabarits « {$nom} » ne déclarent plus de variable : plus rien n’est réglable.");

        expect(listeAutorisation($definition['entrypoint'], $definition['liste']))
            ->toBe($duGabarit, "La liste d’autorisation « {$nom} » ne correspond plus aux variables des gabarits.");
    }
});

it('chaque variable a son DÉFAUT posé côté shell — `envsubst` ignore `${VAR:-…}`', function (): void {
    /*
     * ⛔ POURQUOI LE DÉFAUT NE PEUT PAS VIVRE DANS LE GABARIT. `envsubst` ne
     * connaît pas la substitution par défaut du shell : il rendrait
     * `${PHP_MEMORY_LIMIT:-256M}` LITTÉRALEMENT dans le fichier de
     * configuration. Le défaut est donc posé avant l'appel, et un gabarit qui
     * en contiendrait un est une erreur silencieuse.
     */
    $cas = [
        'docker/php/scripts/docker-entrypoint.sh' => [
            'docker/php/conf/php-fork.ini.template',
            'docker/php/conf/php-fpm-fork.conf.template',
        ],
        'docker/apache/scripts/docker-entrypoint.sh' => [
            'docker/apache/conf/sites-enabled/laravel.conf.template',
        ],
    ];

    foreach ($cas as $entrypoint => $gabarits) {
        $source = RepoFile::read($entrypoint);

        foreach ($gabarits as $gabarit) {
            $contenu = RepoFile::read($gabarit);

            expect($contenu)
                ->not->toMatch('/\$\{[A-Z][A-Z0-9_]*:-/', "{$gabarit} porte un défaut à la mode shell : envsubst le rendrait littéralement.");

            foreach (variablesDuGabarit($gabarit) as $variable) {
                expect($source)
                    ->toMatch(
                        // ⚠️ `.+` ET NON `[^}]+` : le défaut de
                        // `PHP_CLI_MEMORY_LIMIT` est lui-même une substitution
                        // (`${PHP_CLI_MEMORY_LIMIT_DEFAUT:-2G}`, posée par
                        // l'étage de build). Un motif interdisant l'accolade
                        // interne refuserait la seule forme correcte.
                        '/^' . preg_quote($variable, '/') . '="\$\{' . preg_quote($variable, '/') . ':-.+\}"$/m',
                        "{$entrypoint} ne pose aucun défaut pour {$variable} : une valeur vide rendrait une directive sans valeur.",
                    );
            }
        }
    }
});

it('Compose injecte CHAQUE variable autorisée, sinon le `.env` racine reste lettre morte', function (): void {
    /*
     * 🔴 SANS `environment:`, RIEN N'ARRIVE. Le service `apache` n'en avait
     * AUCUN avant cette story, et le service `php` n'y déclarait aucune
     * variable `PHP_`. Un gabarit parfait dont la variable n'est jamais
     * injectée, c'est la promesse de configurabilité sans récepteur — le
     * défaut que cette story consigne par ailleurs pour `PHP_OPCACHE_*`.
     */
    $services = RepoFile::section(RepoFile::yaml('docker-compose.yml'), 'services');

    $cas = [
        'php' => listeAutorisation('docker/php/scripts/docker-entrypoint.sh', 'PHP_TEMPLATE_VARS'),
        'apache' => listeAutorisation('docker/apache/scripts/docker-entrypoint.sh', 'VHOST_VARS'),
    ];

    $exempleEnv = RepoFile::read('.env.example');

    foreach ($cas as $service => $variables) {
        $definition = $services[$service] ?? null;
        expect(is_array($definition))
            ->toBeTrue("Service « {$service} » absent de docker-compose.yml.");

        /** @var array<string, mixed> $definition */
        $environnement = $definition['environment'] ?? [];
        expect(is_array($environnement))
            ->toBeTrue("Le service « {$service} » n’a pas d’`environment:`.");

        /** @var array<int|string, mixed> $environnement */
        $lignes = array_values(array_filter($environnement, 'is_string'));

        foreach ($variables as $variable) {
            $injectee = false;

            foreach ($lignes as $ligne) {
                if (str_starts_with((string) $ligne, $variable . '=')) {
                    $injectee = true;
                }
            }

            expect($injectee)
                ->toBeTrue("{$variable} n’est pas injectée dans le service « {$service} » : le `.env` racine ne l’atteindra jamais.");

            // …et elle est DOCUMENTÉE là où un fork-streamer la cherchera.
            // ⚠️ `toContain` prend des AIGUILLES, pas un message — le message
            // passe donc par `toBeTrue`. Piège déjà rencontré cinq fois dans ce
            // dépôt, et rencontré une sixième en écrivant ce fichier.
            expect(str_contains($exempleEnv, $variable))
                ->toBeTrue("{$variable} n’est documentée nulle part dans le `.env.example` racine.");
        }
    }
});

it('le défaut de la limite CLI DIFFÈRE entre `production` et `development`', function (): void {
    /*
     * 🔴 UN DÉFAUT UNIQUE À `4G` ÉTAIT FAUX EN PRODUCTION, ET DANGEREUSEMENT.
     * `docker-compose.prod.yml` plafonne le conteneur php à `memory: 1G`
     * (`deploy.resources.limits`) et n'injecte PAS `PHP_CLI_MEMORY_LIMIT`.
     * Avant cette story la CLI de production valait `2G` — la valeur écrite
     * par le Dockerfile dans `composer-optimizations.ini`, que seul l'étage
     * `development` pousse à `4G`. Un défaut unique DOUBLAIT donc la limite
     * sous un cgroup de 1 Go : le kernel tue le processus avant que PHP
     * n'atteigne sa limite, donc SANS « Allowed memory size exhausted » pour
     * nommer le coupable.
     *
     * ⚠️ ET LA CLI N'EST PAS QUE COMPOSER : les workers **Horizon** tournent
     * sous ce SAPI, dans ce conteneur, en N processus enfants
     * (`docker/supervisor/conf.d/horizon.conf`). Une limite par processus × N
     * enfants sous 1 Go est la façon exacte de transformer un échec net en OOM
     * système.
     *
     * ⛔ MUTATION PRÉVUE : poser la même valeur aux deux étages. Ce garde
     * rougit — c'est tout son objet.
     */
    $dockerfile = RepoFile::read('docker/php/Dockerfile');

    // À quel étage appartient chaque `ENV` ? On lit les `FROM … AS <étage>`
    // qui le PRÉCÈDENT, plutôt que de supposer un ordre.
    preg_match_all('/^FROM\s+\S+\s+AS\s+(\S+)/m', $dockerfile, $etapes, PREG_OFFSET_CAPTURE);
    preg_match_all('/^ENV PHP_CLI_MEMORY_LIMIT_DEFAUT=(\S+)/m', $dockerfile, $defauts, PREG_OFFSET_CAPTURE);

    $parEtage = [];

    foreach ($defauts[1] as $index => $capture) {
        $position = $defauts[0][$index][1];
        $etage = null;

        foreach ($etapes[1] as $candidat) {
            if ($candidat[1] < $position) {
                $etage = $candidat[0];
            }
        }

        if ($etage !== null) {
            $parEtage[$etage] = $capture[0];
        }
    }

    // ⚠️ `toHaveKey` prend une VALEUR attendue en 2ᵉ argument, pas un message —
    // même famille de piège que `toContain` et ses aiguilles. Le message passe
    // donc par `toBeTrue`. (Septième rencontre dans ce dépôt.)
    expect(array_key_exists('production', $parEtage))
        ->toBeTrue('L’étage `production` ne pose aucun défaut de limite CLI.');
    expect(array_key_exists('development', $parEtage))
        ->toBeTrue('L’étage `development` ne pose aucun défaut de limite CLI.');

    expect($parEtage['production'])
        ->not->toBe($parEtage['development'], 'Les deux étages posent la MÊME limite CLI : la production hérite du réglage de développement, sous un cgroup qui ne le supporte pas.');

    /*
     * ⚖️ ET LE REPLI DE L'ENTRYPOINT EST LE SÛR, PAS LE CONFORTABLE. Si aucun
     * étage n'a rien posé, on ne suppose pas la machine de développement.
     */
    $entrypoint = RepoFile::read('docker/php/scripts/docker-entrypoint.sh');

    expect($entrypoint)
        ->toContain('PHP_CLI_MEMORY_LIMIT="${PHP_CLI_MEMORY_LIMIT:-${PHP_CLI_MEMORY_LIMIT_DEFAUT:-' . $parEtage['production'] . '}}"');
});

it('`php.ini` ne fait plus passer pour réglables deux lignes devenues inertes', function (): void {
    /*
     * ⛔ LE FICHIER QU'UN FORK IRAIT ÉDITER MENT UN CRAN PLUS PROFOND QU'AVANT.
     * `memory_limit` et `max_execution_time` y sont toujours écrits, mais
     * `conf.d/zz-fork.ini` est scanné après et gagne — et pour php-fpm, le
     * fragment de pool gagne encore au-dessus. Les éditer ne change RIEN, et
     * salit un fichier versionné bind-monté en écriture. La story a supprimé un
     * mensonge de configurabilité ; elle n'a pas le droit d'en laisser un
     * nouveau dans le fichier d'origine.
     */
    $phpIni = RepoFile::read('docker/php/conf/php.ini');

    expect(str_contains($phpIni, 'INERTES'))
        ->toBeTrue('`php.ini` ne dit pas que ses deux limites sont désormais écrasées : un fork les éditera pour rien.');

    // …et il NOMME les variables qui, elles, décident.
    foreach (['PHP_MEMORY_LIMIT', 'PHP_CLI_MEMORY_LIMIT', 'PHP_MAX_EXECUTION_TIME'] as $variable) {
        expect(str_contains($phpIni, $variable))
            ->toBeTrue("`php.ini` ne renvoie pas vers {$variable} : la note dit « ne modifiez pas » sans dire « modifiez quoi ».");
    }
});

it('le vhost candidat est éprouvé par `httpd -t` AVANT d’être promu', function (): void {
    /*
     * ⚖️ L'ORDRE EST L'INVARIANT. Promouvoir puis tester détruirait la
     * configuration précédente avant de découvrir qu'elle était la bonne : le
     * conteneur repartirait en boucle sans plus rien de valide à servir.
     * Le COMPORTEMENT correspondant est mesuré par `config-template.bats`, qui
     * fait réellement échouer un gabarit fautif dans un conteneur apache.
     */
    $source = RepoFile::read('docker/apache/scripts/docker-entrypoint.sh');

    $test = strpos($source, 'httpd -t -f "$conf_test"');
    $promotion = strpos($source, 'mv "$candidat" "$cible"');

    expect($test !== false)
        ->toBeTrue('Le test `httpd -t` du candidat a disparu.');
    expect($promotion !== false)
        ->toBeTrue('La promotion du candidat a disparu.');

    // ⚠️ `strpos` rend la PREMIÈRE occurrence : un `mv` ajouté plus haut — la
    // mutation « promouvoir puis tester » — déplace donc bien ce nombre.
    expect((int) $test)
        ->toBeLessThan((int) $promotion, 'Le candidat est promu AVANT d’être testé : un gabarit fautif détruirait la cible précédente.');
});

// =============================================================================
// FAMILLE 2 — sondes de COMPORTEMENT (la fonction de rendu est APPELÉE)
// =============================================================================

it('REFUSE de démarrer quand `envsubst` est introuvable, en le nommant', function (): void {
    /*
     * ⛔ MUTATION PRÉVUE PAR L'AC5, versant comportement : sans `gettext`,
     * l'alternative silencieuse serait de laisser passer et de servir la
     * configuration d'avant — un conteneur sain qui ignore ce qu'on lui demande.
     */
    $result = ShellProbe::run(sondeRendu(<<<'CORPS'
        statut=0
        ( ENVSUBST_BIN=envsubst-absent-pour-la-sonde \
            rendre_gabarit "$GABARIT" "$CIBLE" ) > "$bac/sortie" 2>&1 || statut=$?

        echo "STATUT=$statut"
        cat "$bac/sortie"
        if [ -e "$CIBLE" ]; then echo "CIBLE=creee"; else echo "CIBLE=absente"; fi
        CORPS), environnementSonde(), 60, ShellProbe::posixShell()['path']);

    expect($result['output'])
        ->toContain('STATUT=1')
        ->toContain('envsubst-absent-pour-la-sonde')
        ->toContain('gettext')
        // La cible n'est même pas amorcée : pas de fichier vide laissé derrière.
        ->toContain('CIBLE=absente');
});

it('REFUSE une directive sans valeur, et laisse la cible PRÉCÉDENTE intacte', function (): void {
    /*
     * 🔴 `memory_limit =` N'EST PAS UNE ERREUR POUR PHP : il l'interprète comme
     * la chaîne vide, donc `0` — un refus d'allouer quoi que ce soit. Le
     * conteneur démarrerait, et échouerait sur chaque requête. C'est le cas
     * « variable vide » de la matrice, et il ne peut pas se contenter d'un
     * démarrage réussi.
     *
     * ⚖️ Le stub `envsubst` vide TOUTES les valeurs : la sonde ne dépend donc
     * ni de `gettext` ni du contenu exact du gabarit.
     */
    $result = ShellProbe::run(sondeRendu(<<<'CORPS'
        printf '%s\n' '#!/bin/sh' 'exec sed "s/=.*$/= /"' > "$bac/bin/envsubst-vide"
        chmod +x "$bac/bin/envsubst-vide"

        # Une cible PRÉCÉDENTE, reconnaissable : c'est elle qui doit survivre.
        echo "; configuration precedente" > "$CIBLE"

        statut=0
        ( ENVSUBST_BIN="$bac/bin/envsubst-vide" \
            rendre_gabarit "$GABARIT" "$CIBLE" ) > "$bac/sortie" 2>&1 || statut=$?

        echo "STATUT=$statut"
        cat "$bac/sortie"
        echo "CIBLE_APRES=[$(cat "$CIBLE")]"
        if [ -e "$CIBLE.rendu" ]; then echo "TEMPORAIRE=laisse"; else echo "TEMPORAIRE=nettoye"; fi
        CORPS), environnementSonde(), 60, ShellProbe::posixShell()['path']);

    expect($result['output'])
        ->toContain('STATUT=1')
        ->toContain('Directive sans valeur')
        ->toContain('CIBLE_APRES=[; configuration precedente]')
        ->toContain('TEMPORAIRE=nettoye');
});

it('REFUSE de rendre un gabarit sur lui-même', function (): void {
    // ⚖️ « gabarit ≠ cible » n'est pas qu'une convention de nommage : confondus,
    // le rendu détruirait sa propre source au premier démarrage.
    $result = ShellProbe::run(sondeRendu(<<<'CORPS'
        statut=0
        ( rendre_gabarit "$GABARIT" "$GABARIT" ) > "$bac/sortie" 2>&1 || statut=$?

        echo "STATUT=$statut"
        cat "$bac/sortie"
        CORPS), environnementSonde(), 60, ShellProbe::posixShell()['path']);

    expect($result['output'])
        ->toContain('STATUT=1')
        ->toContain('confondus');
});

it('est REJOUABLE : deuxième rendu identique, gabarit jamais réécrit', function (): void {
    /*
     * ⚖️ CE QUE CETTE SONDE MESURE, ET CE QU'ELLE NE MESURE PAS. Avec un
     * `envsubst` stubé en `cat`, elle prouve l'idempotence du rendu et
     * l'INTÉGRITÉ DU GABARIT — l'invariant qui distingue cette story d'un `sed`
     * en place. La substitution réelle, elle, est mesurée par
     * `config-template.bats` avec le vrai `envsubst`.
     */
    $result = ShellProbe::run(sondeRendu(<<<'CORPS'
        # ⛔ UN STUB `cat` NE SUFFIT PLUS, ET C'EST VOULU : l'entrypoint refuse
        # désormais tout marqueur survivant au rendu. Le stub SUBSTITUE donc,
        # bêtement mais réellement — la sonde reste indépendante de `gettext`
        # sans pour autant contourner le garde.
        Q="'"
        printf '%s\n' '#!/bin/sh' \
            "exec sed -e ${Q}s/[\$]{[A-Z_][A-Z0-9_]*}/256M/g${Q}" \
            > "$bac/bin/envsubst-neutre"
        chmod +x "$bac/bin/envsubst-neutre"

        AVANT="$(cksum < "$GABARIT")"

        ENVSUBST_BIN="$bac/bin/envsubst-neutre" rendre_gabarit "$GABARIT" "$CIBLE" > /dev/null
        UN="$(cksum < "$CIBLE")"

        ENVSUBST_BIN="$bac/bin/envsubst-neutre" rendre_gabarit "$GABARIT" "$CIBLE" > /dev/null
        DEUX="$(cksum < "$CIBLE")"

        APRES="$(cksum < "$GABARIT")"

        if [ "$UN" = "$DEUX" ]; then echo "RENDU=identique"; else echo "RENDU=divergent"; fi
        if [ "$AVANT" = "$APRES" ]; then echo "GABARIT=intact"; else echo "GABARIT=reecrit"; fi
        # Anti-vacuité : la cible a bien été écrite, on ne compare pas deux vides.
        if [ -s "$CIBLE" ]; then echo "CIBLE=ecrite"; else echo "CIBLE=vide"; fi
        CORPS), environnementSonde(), 60, ShellProbe::posixShell()['path']);

    expect($result['output'])
        ->toContain('RENDU=identique')
        ->toContain('GABARIT=intact')
        ->toContain('CIBLE=ecrite');
});
