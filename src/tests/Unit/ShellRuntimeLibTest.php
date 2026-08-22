<?php

declare(strict_types=1);

use Tests\Support\RepoFile;
use Tests\Support\ShellProbe;

/*
|--------------------------------------------------------------------------
| Primitives shell partagées — scripts/lib/runtime.sh (Story 2.1)
|--------------------------------------------------------------------------
|
| Suite Unit : aucun de ces tests ne boote Laravel. Ils lancent `bash` et
| lisent ce qu'il rend — c'est le seul véhicule capable de faire ROUGIR du
| shell tant que Bats n'est pas là (Story 2.4).
|
| Chaque test correspond à une ligne de la matrice de la story, ou à une des
| quatre voies de refus du pilote `scripts/install/00-prerequisites.sh`.
|
| Aucun helper ne vit ici : ils sont tous sur `Tests\Support\ShellProbe`, qui
| fixe aussi le cwd et l'environnement de chaque sonde. Un test du pilote qui
| hériterait du répertoire d'où pest a été lancé mesurerait une chose dans le
| conteneur et une autre en CI (`ubuntu-latest`, `working-directory: src`).
|
*/

// =============================================================================
// require_cmd
// =============================================================================

it('require_cmd rend 0 en silence quand le binaire est présent', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        require_cmd bash
        echo "APRES-REQUIRE-CMD"
        BASH);

    expect($result['status'])->toBe(0);
    expect(trim($result['output']))->toBe('APRES-REQUIRE-CMD');
});

it('require_cmd meurt en nommant le binaire absent', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        require_cmd binaire-absent-story-2-1
        echo "SUITE-NE-DOIT-PAS-TOURNER"
        BASH);

    expect($result['status'])->not->toBe(0);
    expect($result['output'])->toContain('binaire-absent-story-2-1');
    expect($result['output'])->toContain('ERREUR FATALE');
    expect($result['output'])->not->toContain('SUITE-NE-DOIT-PAS-TOURNER');
});

it('require_cmd nomme TOUS les binaires manquants, pas seulement le premier', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        require_cmd absent-un-2-1 bash absent-deux-2-1
        BASH);

    expect($result['status'])->not->toBe(0);
    expect($result['output'])->toContain('absent-un-2-1');
    expect($result['output'])->toContain('absent-deux-2-1');
});

it('die reste BRUYANT à travers une frontière de processus', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        # `bash -c` : nouveau processus. `die` y arrive par `export -f`, mais
        # `log()` y appelle `_should_log` — privée, et longtemps NON exportée.
        set +e
        bash -c 'die "mort-en-sous-processus" 42'
        echo "CODE=$?"
        BASH);

    // 🔴 Mesuré le 2026-08-22 : le code de sortie était juste (42) et la
    // bannière ABSENTE — `if ! _should_log "$level"` sur une commande
    // introuvable vaut 127, donc `!` le rend VRAI, donc `log()` sortait tôt
    // sans écrire. Une primitive fatale silencieuse est un garde-fou qui ne
    // garde rien : `die` était muet dans tout `bash -c`, `xargs`, `find -exec`.
    expect($result['output'])->toContain('ERREUR FATALE');
    expect($result['output'])->toContain('mort-en-sous-processus');
    expect($result['output'])->not->toContain('_should_log');
    expect($result['output'])->toContain('CODE=42');
});

it('require_cmd nomme les arguments VIDES et les manquants dans le même refus', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        require_cmd "" absent-trois-2-1 bash ""
        BASH);

    expect($result['status'])->not->toBe(0);

    // La garde « nom vide » vivait DANS la boucle : le premier argument vide
    // tuait le processus sans jamais regarder les suivants, en contradiction
    // avec le docblock qui promet « vérifie TOUS les binaires avant de mourir ».
    expect($result['output'])->toContain('2 nom(s) de binaire vide(s)');
    expect($result['output'])->toContain('absent-trois-2-1');
});

// =============================================================================
// retry
// =============================================================================

it("retry n'exécute qu'une fois quand la commande réussit d'emblée", function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        compteur="$(mktemp)"
        essai() { echo "x" >> "$compteur"; return 0; }

        status=0
        retry 3 essai || status=$?

        echo "STATUS=$status"
        echo "RUNS=$(wc -l < "$compteur" | tr -d ' ')"
        rm -f "$compteur"
        BASH);

    expect($result['status'])->toBe(0);
    expect($result['output'])->toContain('STATUS=0');
    expect($result['output'])->toContain('RUNS=1');
    expect(ShellProbe::retryDelays($result['output']))->toBe([]);
});

it('retry réussit au 3e essai en doublant le délai (1s puis 2s)', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        compteur="$(mktemp)"
        essai() {
            echo "x" >> "$compteur"
            [ "$(wc -l < "$compteur" | tr -d ' ')" -ge 3 ]
        }

        status=0
        retry 3 essai || status=$?

        echo "STATUS=$status"
        echo "RUNS=$(wc -l < "$compteur" | tr -d ' ')"
        rm -f "$compteur"
        BASH
        , [], 40);

    expect($result['status'])->toBe(0);
    expect($result['output'])->toContain('STATUS=0');
    expect($result['output'])->toContain('RUNS=3');
    // Le backoff est lu dans le JOURNAL, pas mesuré à l'horloge : une horloge
    // rend un test instable, et « ça a mis à peu près 3 secondes » ne distingue
    // pas 1+2 de 2+1.
    expect(ShellProbe::retryDelays($result['output']))->toBe(['1', '2']);
});

it('retry ne dort pas du tout quand RETRY_BASE_DELAY vaut 0', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        compteur="$(mktemp)"
        essai() { echo "x" >> "$compteur"; return 7; }

        status=0
        retry 3 essai || status=$?

        echo "STATUS=$status"
        echo "RUNS=$(wc -l < "$compteur" | tr -d ' ')"
        rm -f "$compteur"
        BASH
        , [
            'RETRY_BASE_DELAY' => '0',
        ], 10);

    expect($result['output'])->toContain('RUNS=3');
    expect(ShellProbe::retryDelays($result['output']))->toBe(['0', '0']);
    // Même compte d'essais, sans la moindre attente : c'est ce qui rend la
    // suite payable. Avec le délai par défaut, ce cas coûterait 3 secondes.
    expect($result['seconds'])->toBeLessThan(2.0);
});

it('retry épuisé rend le code de la commande, sans die implicite', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        compteur="$(mktemp)"
        essai() { echo "x" >> "$compteur"; return 7; }

        status=0
        retry 3 essai || status=$?

        echo "STATUS=$status"
        echo "RUNS=$(wc -l < "$compteur" | tr -d ' ')"
        rm -f "$compteur"
        BASH
        , [
            'RETRY_BASE_DELAY' => '0',
        ], 10);

    expect($result['status'])->toBe(0);
    expect($result['output'])->toContain('STATUS=7');
    expect($result['output'])->toContain('RUNS=3');
    expect($result['output'])->toContain('a échoué après 3 essai');
    // `retry` ne décide pas à la place de l'appelant : un échec épuisé n'est
    // pas fatal.
    expect($result['output'])->not->toContain('ERREUR FATALE');
});

it('retry meurt immédiatement sur un compteur non entier, sans boucler', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        retry abc true
        echo "SUITE-NE-DOIT-PAS-TOURNER"
        BASH
        , [], 5);

    // Mesuré sur une dérivation précédente : ce cas BOUCLAIT jusqu'au timeout.
    expect($result['status'])->not->toBe(ShellProbe::TIMEOUT_STATUS);
    expect($result['status'])->not->toBe(0);
    expect($result['output'])->toContain("nombre d'essais invalide");
    expect($result['output'])->not->toContain('SUITE-NE-DOIT-PAS-TOURNER');
    expect($result['seconds'])->toBeLessThan(5.0);
});

it('retry sans commande meurt au lieu de rendre 0', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        retry 3
        echo "SUITE-NE-DOIT-PAS-TOURNER"
        BASH
        , [], 5);

    // Mesuré : ce cas rendait 0 — un succès sur une commande jamais exécutée.
    expect($result['status'])->not->toBe(0);
    expect($result['output'])->toContain('aucune commande');
    expect($result['output'])->not->toContain('SUITE-NE-DOIT-PAS-TOURNER');
});

it('retry refuse un compteur hors plage entière au lieu de boucler sans fin', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        retry 99999999999999999999 false
        echo "SUITE-NE-DOIT-PAS-TOURNER"
        BASH
        , [], 5);

    // 🔴 `^[0-9]+$` acceptait ce compteur ; `[ "$attempts" -lt 1 ]` sortait
    // ensuite de la plage 64 bits, `[` répondait « integer expression
    // expected », la garde ne se déclenchait pas et la boucle tournait SANS
    // FIN — mesuré le 2026-08-22, tué par timeout à 5 s (code 143). La matrice
    // gelée dit « jamais de boucle » : un entier hors plage meurt comme un
    // non-entier.
    expect($result['status'])->not->toBe(ShellProbe::TIMEOUT_STATUS);
    expect($result['status'])->not->toBe(0);
    expect($result['output'])->toContain("nombre d'essais invalide");
    expect($result['output'])->not->toContain('SUITE-NE-DOIT-PAS-TOURNER');
    expect($result['seconds'])->toBeLessThan(5.0);
});

it('retry attend 1 s par défaut, quand RETRY_BASE_DELAY n’est pas défini', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        # ShellProbe épingle RETRY_BASE_DELAY sur toutes les sondes. La valeur
        # PAR DÉFAUT est pourtant la seule que la production utilise : le pilote
        # ne définit jamais cette variable. On la retire donc ici, exprès.
        unset RETRY_BASE_DELAY

        essai() { return 7; }

        status=0
        retry 2 essai || status=$?
        echo "STATUS=$status"
        BASH
        , [], 15);

    expect($result['output'])->toContain('STATUS=7');

    // 1 × 2^0 = 1 seconde avant l'unique réessai — le défaut du code, pas celui
    // de la sonde.
    expect(ShellProbe::retryDelays($result['output']))->toBe(['1']);
    expect($result['seconds'])->toBeGreaterThanOrEqual(1.0);
});

// =============================================================================
// ensure_idempotent
// =============================================================================

it('ensure_idempotent exécute et pose la sentinelle au premier passage', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        dossier="$(mktemp -d)"
        compteur="$dossier/compteur"
        etape() { echo "x" >> "$compteur"; }

        status=0
        ensure_idempotent "$dossier/etape-done" etape || status=$?

        echo "STATUS=$status"
        echo "RUNS=$(wc -l < "$compteur" | tr -d ' ')"
        [ -f "$dossier/etape-done" ] && echo "SENTINELLE=PRESENTE" || echo "SENTINELLE=ABSENTE"
        rm -rf "$dossier"
        BASH);

    expect($result['status'])->toBe(0);
    expect($result['output'])->toContain('STATUS=0');
    expect($result['output'])->toContain('RUNS=1');
    expect($result['output'])->toContain('SENTINELLE=PRESENTE');
});

it('ensure_idempotent n’exécute pas la seconde fois', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        dossier="$(mktemp -d)"
        compteur="$dossier/compteur"
        touch "$compteur"
        etape() { echo "x" >> "$compteur"; }

        status=0
        ensure_idempotent "$dossier/etape-done" etape || status=$?
        ensure_idempotent "$dossier/etape-done" etape || status=$?

        echo "STATUS=$status"
        echo "RUNS=$(wc -l < "$compteur" | tr -d ' ')"
        rm -rf "$dossier"
        BASH);

    expect($result['status'])->toBe(0);
    expect($result['output'])->toContain('STATUS=0');
    expect($result['output'])->toContain('RUNS=1');
});

it('ensure_idempotent ne prétend pas avoir posé une sentinelle inécrivable', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        dossier="$(mktemp -d)"
        interdit="$dossier/interdit"
        mkdir -p "$interdit"
        chmod a-w "$interdit"

        status=0
        ensure_idempotent "$interdit/etape-done" true || status=$?

        echo "STATUS=$status"
        [ -f "$interdit/etape-done" ] && echo "SENTINELLE=PRESENTE" || echo "SENTINELLE=ABSENTE"
        chmod u+w "$interdit"
        rm -rf "$dossier"
        BASH
        , [
            'DEBUG' => 'true',
        ]);

    // Mesuré sur une dérivation précédente : rendait 0 en journalisant
    // « sentinelle posée », sentinelle absente — l'étape aurait été réputée
    // franchie pour toujours.
    expect($result['output'])->toContain('STATUS=1');
    expect($result['output'])->toContain('SENTINELLE=ABSENTE');
    expect($result['output'])->toContain('impossible à écrire');
    expect($result['output'])->not->toContain('sentinelle posée');
});

it('ensure_idempotent ne pose PAS la sentinelle quand la commande échoue — l’étape est rejouée', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        dossier="$(mktemp -d)"
        compteur="$dossier/compteur"
        : > "$compteur"

        echoue() { echo "x" >> "$compteur"; return 3; }
        reussit() { echo "x" >> "$compteur"; return 0; }

        status=0
        ensure_idempotent "$dossier/etape-done" echoue || status=$?
        echo "STATUS1=$status"
        [ -f "$dossier/etape-done" ] && echo "SENTINELLE1=PRESENTE" || echo "SENTINELLE1=ABSENTE"

        # Rejeu : une étape non franchie doit être retentée au passage suivant.
        status=0
        ensure_idempotent "$dossier/etape-done" reussit || status=$?
        echo "STATUS2=$status"
        [ -f "$dossier/etape-done" ] && echo "SENTINELLE2=PRESENTE" || echo "SENTINELLE2=ABSENTE"

        echo "RUNS=$(wc -l < "$compteur" | tr -d ' ')"
        rm -rf "$dossier"
        BASH);

    // C'est LE contrat central de la primitive, et il n'était testé nulle part :
    // une étape qui a échoué ne doit pas être réputée faite. La sentinelle est
    // la preuve du succès, pas de la tentative.
    expect($result['output'])->toContain('STATUS1=3');
    expect($result['output'])->toContain('SENTINELLE1=ABSENTE');
    expect($result['output'])->toContain('STATUS2=0');
    expect($result['output'])->toContain('SENTINELLE2=PRESENTE');
    expect($result['output'])->toContain('RUNS=2');
});

it('ensure_idempotent ne prend pas un RÉPERTOIRE pour une sentinelle', function (): void {
    $result = ShellProbe::runWithRuntime(<<<'BASH'
        dossier="$(mktemp -d)"
        compteur="$dossier/compteur"
        : > "$compteur"
        mkdir -p "$dossier/etape-done"   # la « sentinelle » est un RÉPERTOIRE

        etape() { echo "x" >> "$compteur"; }

        status=0
        ensure_idempotent "$dossier/etape-done" etape || status=$?

        echo "STATUS=$status"
        echo "RUNS=$(wc -l < "$compteur" | tr -d ' ')"
        rm -rf "$dossier"
        BASH);

    // La lecture se faisait avec `-e` et l'écriture avec `-f` : un répertoire
    // à ce chemin rendait l'étape « faite » pour toujours SANS l'avoir jouée
    // une seule fois, et sans qu'aucune écriture n'ait jamais pu réussir.
    expect($result['output'])->toContain('RUNS=1');
    expect($result['output'])->toContain('STATUS=1');
    expect($result['output'])->toContain('impossible à écrire');
});

// =============================================================================
// Garde d'inclusion
// =============================================================================

it('survit à un double source sous set -e', function (): void {
    $lib = ShellProbe::libDir();

    $result = ShellProbe::run(<<<BASH
        set -e
        source '{$lib}/logging.sh'
        source '{$lib}/runtime.sh'
        source '{$lib}/runtime.sh'
        echo "APPELANT-VIVANT"
        require_cmd bash
        echo "PRIMITIVES-INTACTES"
        BASH);

    // Sans garde, le second source échoue sur la re-déclaration `readonly` et
    // errexit TUE l'appelant — c'est ce qui arrive à logging.sh, mesuré.
    expect($result['status'])->toBe(0);
    expect($result['output'])->toContain('APPELANT-VIVANT');
    expect($result['output'])->toContain('PRIMITIVES-INTACTES');
});

// =============================================================================
// arm_err_trap — sur la fixture versionnée
// =============================================================================

it('le trap ERR nomme le fichier et la ligne de la commande nue en échec', function (): void {
    $line = ShellProbe::trapFailingLine();

    $result = ShellProbe::runFile(ShellProbe::trapSubject());

    expect($result['status'])->not->toBe(0);
    expect($result['output'])->toContain('TRAP-SUBJECT-AVANT');
    expect($result['output'])->not->toContain('TRAP-SUBJECT-APRES');
    expect($result['output'])->toContain('trap-subject.sh:' . $line);

    // `\b` en fin : sans lui, la ligne 5 « passerait » sur un rapport disant
    // 50 — un numéro juste est le préfixe d'un faux.
    expect($result['output'])->toMatch('/trap-subject\.sh:' . $line . '\b/');
});

it("aucun script d'installation n'arme le trap ERR", function (): void {
    $scripts = glob(ShellProbe::repoRoot() . '/scripts/install/*.sh') ?: [];

    expect($scripts)
        ->not->toBeEmpty();

    foreach ($scripts as $script) {
        // Ancré en début de ligne : le pilote EXPLIQUE en commentaire pourquoi
        // il n'arme pas le trap, et un grep textuel rougirait sur son propre
        // motif — piège déjà rencontré dans ce dépôt.
        expect(file_get_contents($script))
            ->not->toMatch('/^\s*arm_err_trap\b/m');
    }
});

// =============================================================================
// Le pilote — scripts/install/00-prerequisites.sh
// =============================================================================

it('le pilote rend 0 et exécute TOUTES ses étapes', function (): void {
    $result = ShellProbe::runFile(ShellProbe::pilotScript(), [], 120);

    expect($result['status'])->toBe(0);

    // La conversion aux primitives ne doit court-circuiter aucune vérification :
    // un pilote qui s'arrêterait après le premier outil en rendant 0 serait
    // indiscernable du succès sans cette liste.
    //
    // ⛔ `RÉCAPITULATIF DES PRÉREQUIS` a été RETIRÉ de cette liste : la chaîne
    // est émise par `show_prerequisites_summary()` en TÊTE de `main()`, avant
    // toute vérification. Elle était donc vraie y compris sur la version fatale
    // qui mourait au premier outil manquant — une assertion qui ne pouvait pas
    // rougir. Ce qui la remplace est un marqueur de FIN : `✅ PERMISSIONS
    // terminé`, écrit par `log_step_end` de la dernière étape.
    foreach ([
        'OUTILS SYSTÈME',
        'VERSIONS',
        'EXTENSIONS PHP',
        'ENVIRONNEMENT DOCKER',
        'CONNECTIVITÉ',
        'PERMISSIONS',
        '✅ PERMISSIONS terminé',
        'Tous les prérequis sont satisfaits',
    ] as $etape) {
        expect($result['output'])->toContain($etape);
    }
});

it('le pilote ne modifie ni le dépôt ni l’arbre applicatif', function (): void {
    // 🔴 CE QUE CE TEST NE MESURE PAS, ET POURQUOI. Il s'intitulait « n'écrit
    // aucun fichier hors /tmp » : `$HOME` n'étant pas inventorié, il promettait
    // strictement plus qu'il ne mesurait. Élargir l'inventaire à `$HOME` a été
    // écarté sur mesure — sur un runner CI, `composer --version` peut y créer
    // son cache, un mouvement NON attribuable au pilote qui rendrait ce
    // garde-fou instable, donc ignoré. Le nom dit désormais l'arbre réellement
    // inventorié : le dépôt et l'application.
    $roots = array_values(array_filter(
        [ShellProbe::repoRoot(), ShellProbe::srcDir()],
        static fn (string $path): bool => is_dir($path),
    ));

    $avant = ShellProbe::inventory($roots);

    // 🔴 LA GARDE QUI FAIT TOUT LE TRAVAIL. Une première version de cet
    // inventaire, construite avec `find -printf` (absent de BusyBox), rendait
    // DEUX LISTES VIDES : identiques, donc vertes, sur un script qui aurait pu
    // écrire n'importe où.
    expect($avant)
        ->not->toBeEmpty();
    expect(count($avant))
        ->toBeGreaterThan(100);

    $result = ShellProbe::runFile(ShellProbe::pilotScript(), [], 120);
    expect($result['status'])->toBe(0);

    $apres = ShellProbe::inventory($roots);

    $modifies = array_keys(array_merge(
        array_diff_assoc($avant, $apres),
        array_diff_assoc($apres, $avant),
    ));

    expect($modifies)
        ->toBe([]);
});

it('le pilote nomme le binaire absent, POURSUIT ses étapes, et rend 1', function (): void {
    $result = ShellProbe::run(<<<'BASH'
        # PATH restreint à un bac à sable qui contient TOUT sauf `git` :
        # on ne peut pas « masquer » un binaire, seulement reconstruire le PATH.
        bac="$(mktemp -d)"
        mkdir -p "$bac/bin"
        IFS=':' read -ra chemins <<< "$PATH"
        for repertoire in "${chemins[@]}"; do
            [ -d "$repertoire" ] || continue
            for binaire in "$repertoire"/*; do
                nom="$(basename "$binaire")"
                [ -e "$bac/bin/$nom" ] || ln -s "$binaire" "$bac/bin/$nom" 2>/dev/null || true
            done
        done
        rm -f "$bac/bin/git"

        status=0
        PATH="$bac/bin" bash "$PILOT" || status=$?
        echo "PILOT_EXIT=$status"
        rm -rf "$bac"
        BASH
        , [
            'PILOT' => ShellProbe::pilotScript(),
            'RETRY_BASE_DELAY' => '0',
        ], 120);

    expect($result['output'])->toContain('PILOT_EXIT=1');

    // 🔴 Ancré sur la PHRASE, pas sur `git` : `toContain('git')` passait sur
    // « github.com », que la sonde réseau imprime à chaque exécution. Un
    // garde-fou vert quel que soit le binaire retiré ne garde rien.
    expect($result['output'])->toContain('Outils système requis manquants: git');

    // Le cœur de l'AC : mourir au premier manque masquait TOUT le reste.
    // Mesuré sur la version précédente — seule l'étape OUTILS SYSTÈME était
    // atteinte et le récapitulatif n'était jamais émis.
    foreach (['VERSIONS', 'EXTENSIONS PHP', 'ENVIRONNEMENT DOCKER', 'CONNECTIVITÉ', 'PERMISSIONS'] as $etapeSuivante) {
        expect($result['output'])->toContain($etapeSuivante);
    }

    expect($result['output'])->toContain('Vérification des prérequis échouée');
    expect($result['output'])->toContain('erreur(s) détectée(s)');

    // Le processus n'a pas été tué : c'est un refus, pas une mort subite.
    expect($result['output'])->not->toContain('ERREUR FATALE');
});

it('le pilote refuse une version de Composer trop ancienne', function (): void {
    $result = ShellProbe::run(<<<'BASH'
        faux="$(mktemp -d)"
        cat > "$faux/composer" <<'STUB'
        #!/bin/bash
        echo "Composer version 1.9.0 2020-01-01 00:00:00"
        STUB
        chmod +x "$faux/composer"

        status=0
        PATH="$faux:$PATH" bash "$PILOT" || status=$?
        echo "PILOT_EXIT=$status"
        rm -rf "$faux"
        BASH
        , [
            'PILOT' => ShellProbe::pilotScript(),
        ], 120);

    expect($result['output'])->toContain('PILOT_EXIT=1');
    expect($result['output'])->toContain('Composer 1.9.0 < 2.0');
});

it('le pilote refuse une extension PHP requise absente', function (): void {
    $result = ShellProbe::run(<<<'BASH'
        faux="$(mktemp -d)"
        vrai_php="$(command -v php)"

        # `php` réel pour tout, sauf `php -m` d'où `redis` est retiré : on ne
        # peut pas désinstaller une extension dans le conteneur de test.
        {
            echo '#!/bin/bash'
            echo 'if [ "$1" = "-m" ]; then'
            echo "    \"$vrai_php\" -m | grep -v '^redis\$'"
            echo '    exit 0'
            echo 'fi'
            echo "exec \"$vrai_php\" \"\$@\""
        } > "$faux/php"
        chmod +x "$faux/php"

        status=0
        PATH="$faux:$PATH" bash "$PILOT" || status=$?
        echo "PILOT_EXIT=$status"
        rm -rf "$faux"
        BASH
        , [
            'PILOT' => ShellProbe::pilotScript(),
        ], 120);

    expect($result['output'])->toContain('PILOT_EXIT=1');
    expect($result['output'])->toContain('Extensions PHP requises manquantes: redis');
});

it('le pilote refuse un répertoire de travail non inscriptible', function (): void {
    $result = ShellProbe::run(<<<'BASH'
        set -e
        racine="$(mktemp -d)"
        export TRAVAIL="$racine/travail"
        mkdir -p "$TRAVAIL"
        chmod a-w "$TRAVAIL"

        # Le pilote ne s'auto-exécute pas quand il est sourcé (garde
        # BASH_SOURCE/$0). On remplace la SONDE d'environnement, pas le code
        # sous test : dans le conteneur, detect_working_directory rend toujours
        # /var/www/html, qui est inscriptible — et le rendre inécrivable
        # casserait l'application pour les autres tests.
        source "$PILOT"
        detect_working_directory() { echo "$TRAVAIL"; }

        status=0
        main || status=$?
        echo "PILOT_EXIT=$status"

        chmod u+w "$TRAVAIL"
        rm -rf "$racine"
        BASH
        , [
            'PILOT' => ShellProbe::pilotScript(),
        ], 120);

    expect($result['output'])->toContain('PILOT_EXIT=1');
    expect($result['output'])->toContain("Permissions d'écriture manquantes");
    expect($result['output'])->toContain('Vérification des prérequis échouée');
});

it('le pilote rend 0 HORS conteneur, depuis src/, comme la CI', function (): void {
    $result = ShellProbe::run(<<<'BASH'
        set -e
        source "$PILOT"

        # Le pilote ne s'auto-exécute pas quand il est sourcé (garde
        # BASH_SOURCE/$0). On neutralise la SEULE chose que la CI n'a pas :
        # Docker. `detect_working_directory` bascule alors sur ses branches
        # « hors conteneur », qui lisent `pwd` — et le cwd est fixé par
        # ShellProbe sur src/, exactement comme `working-directory: src` en CI.
        is_docker_environment() { return 1; }

        work_dir="$(detect_working_directory)"
        echo "WORKDIR=[$work_dir]"
        [ -d "$work_dir" ] && echo "WORKDIR_EXISTE" || echo "WORKDIR_ABSENT"

        status=0
        main || status=$?
        echo "PILOT_EXIT=$status"
        BASH
        , [
            'PILOT' => ShellProbe::pilotScript(),
            'RETRY_BASE_DELAY' => '0',
        ], 120);

    // 🔴 LA LIGNE QUI PORTE L'AC. `detect_working_directory` est capturée par
    // `$( )`. Tant que `log()` écrivait sur STDOUT, la valeur rendue était
    // « [WARN …] Structure non reconnue » suivie du chemin : un répertoire
    // inexistant, donc non inscriptible, donc pilote à 1 sur un runner sain.
    // Le motif exige une ligne UNIQUE, sans espace : une bannière ne peut pas
    // passer.
    expect($result['output'])->toMatch('/^WORKDIR=\[\/\S*\]$/m');
    expect($result['output'])->toContain('WORKDIR_EXISTE');

    // La branche non-Docker a bien été empruntée — sinon on n'aurait mesuré que
    // le chemin du conteneur, celui qui marchait déjà. La chaîne vient de
    // `check_docker_environment` (`00-prerequisites.sh:281`), PAS de
    // `detect_working_directory` : attribution corrigée le 2026-08-22.
    expect($result['output'])->toContain('Environnement non-Docker détecté');

    // 🔴 ET VOICI LA BRANCHE QUE LA CI EMPRUNTE VRAIMENT, nommée au lieu d'être
    // sous-entendue. Depuis `src/`, `detect_working_directory` ne reconnaît ni
    // un `src/` enfant ni un `docker-compose.yml` : elle tombe sur son DERNIER
    // recours, `log_warn "Structure de projet non reconnue"`, et rend `pwd`.
    // Le pilote passe donc en CI par un chemin de repli. C'est le comportement
    // réel ; l'assertion l'épingle pour qu'un changement de `common.sh` — hors
    // périmètre de cette story — ne puisse pas le déplacer en silence.
    expect($result['output'])->toContain('Structure de projet non reconnue');

    expect($result['output'])->toContain('PILOT_EXIT=0');
});

it('la sonde réseau du pilote RÉESSAIE — elle ne se contente pas d’un appel', function (): void {
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        export COMPTEUR="$bac/appels"
        : > "$COMPTEUR"

        # `curl` de substitution : échoue un appel sur deux, en commençant par
        # un échec. Sous `retry 2`, chaque dépôt est donc joignable au 2e essai ;
        # sans réessai, deux dépôts sur trois sont déclarés inaccessibles.
        export ARGV="$bac/argv"
        : > "$ARGV"
        cat > "$bac/curl" <<'STUB'
        #!/bin/bash
        # Enregistre l'appel COMPLET : sans cela, le stub validait n'importe
        # quel `curl`, y compris amputé de --max-time ou visant une autre URL.
        echo "$*" >> "$ARGV"
        n="$(wc -l < "$COMPTEUR" | tr -d ' ')"
        echo "x" >> "$COMPTEUR"
        [ $((n % 2)) -eq 0 ] && exit 7
        exit 0
        STUB
        chmod +x "$bac/curl"

        # Second site d'adoption de `retry` dans ce module : la résolution DNS.
        export NSCOMPTEUR="$bac/appels-dns"
        : > "$NSCOMPTEUR"
        cat > "$bac/nslookup" <<'STUB'
        #!/bin/bash
        n="$(wc -l < "$NSCOMPTEUR" | tr -d ' ')"
        echo "x" >> "$NSCOMPTEUR"
        [ "$n" -eq 0 ] && exit 7
        exit 0
        STUB
        chmod +x "$bac/nslookup"

        source "$PILOT"

        status=0
        PATH="$bac:$PATH" check_network_connectivity || status=$?
        echo "SONDE_EXIT=$status"
        echo "APPELS_CURL=$(wc -l < "$COMPTEUR" | tr -d ' ')"
        echo "APPELS_NSLOOKUP=$(wc -l < "$NSCOMPTEUR" | tr -d ' ')"
        echo "ARGV_PREMIER=[$(head -1 "$ARGV")]"
        echo "ARGV_AVEC_MAXTIME=$(grep -c -- '--max-time 10' "$ARGV")"
        echo "ARGV_AVEC_URL=$(grep -c 'https://packagist.org' "$ARGV")"
        rm -rf "$bac"
        BASH
        , [
            'PILOT' => ShellProbe::pilotScript(),
            'RETRY_BASE_DELAY' => '0',
        ], 60);

    // 🔴 `retry` n'avait AUCUNE assertion sur son unique site d'adoption en
    // production : revenir à un `curl` nu laissait la suite entièrement verte.
    // Ce test mesure le COMPORTEMENT (le dépôt est joignable au 2e essai), pas
    // la présence du mot `retry` dans le fichier.
    foreach (['packagist.org', 'github.com', 'raw.githubusercontent.com'] as $depot) {
        expect($result['output'])->toContain("✓ {$depot}: accessible");
    }

    expect($result['output'])->not->toContain('non accessible');
    expect($result['output'])->toContain('APPELS_CURL=6');

    // La sonde DNS est le SECOND site d'adoption : sans elle dans ce test, on
    // pourrait retirer `retry` de `nslookup` sans qu'aucune assertion bouge.
    expect($result['output'])->toContain('Résolution DNS: fonctionnelle');
    expect($result['output'])->toContain('APPELS_NSLOOKUP=2');

    // 🔴 CE QUE LE STUB LAISSAIT PASSER. Il ignorait `"$@"` : retirer
    // `--max-time 10` du pilote, ou viser un autre schéma, laissait ce test
    // vert. L'argv est désormais enregistré et asserté — un `curl` sans borne
    // de temps est un installeur qui pend indéfiniment sur un réseau filtrant.
    expect($result['output'])->toContain('ARGV_AVEC_MAXTIME=6');
    expect($result['output'])->toContain('ARGV_AVEC_URL=2');
    expect($result['output'])->toMatch('/ARGV_PREMIER=\[.*--head.*https:\/\/packagist\.org\]/');

    expect($result['output'])->toContain('SONDE_EXIT=0');
});

it('la sonde réseau signale un dépôt injoignable quand TOUS les essais échouent', function (): void {
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        export COMPTEUR="$bac/appels"
        : > "$COMPTEUR"

        # Panne franche : les deux essais échouent. La branche « non accessible »
        # n'était exercée par rien — un `retry` qui rendrait toujours 0 aurait
        # traversé la suite sans être vu.
        cat > "$bac/curl" <<'STUB'
        #!/bin/bash
        echo "x" >> "$COMPTEUR"
        exit 7
        STUB
        chmod +x "$bac/curl"

        source "$PILOT"

        status=0
        PATH="$bac:$PATH" check_network_connectivity || status=$?
        echo "SONDE_EXIT=$status"
        echo "APPELS_CURL=$(wc -l < "$COMPTEUR" | tr -d ' ')"
        rm -rf "$bac"
        BASH
        , [
            'PILOT' => ShellProbe::pilotScript(),
            'RETRY_BASE_DELAY' => '0',
        ], 60);

    // 2 essais × 3 dépôts, et AUCUN succès : les trois sont déclarés
    // inaccessibles, en avertissement — la sonde réseau reste non bloquante.
    expect($result['output'])->toContain('APPELS_CURL=6');
    expect($result['output'])->toContain('⚠ packagist.org: non accessible');
    expect($result['output'])->toContain('a échoué après 2 essai');

    // Aucun dépôt déclaré joignable. Ancré sur « ✓ <dépôt>: accessible » : le
    // texte de l'avertissement contient lui-même « accessible », un motif plus
    // lâche aurait rougi sur la phrase qu'il est censé accepter.
    foreach (['packagist.org', 'github.com', 'raw.githubusercontent.com'] as $depot) {
        expect($result['output'])->not->toContain("✓ {$depot}: accessible");
    }

    expect($result['output'])->toContain('SONDE_EXIT=0');
});

it('inventory exclut storage/logs mais PAS un répertoire logs quelconque', function (): void {
    $racine = sys_get_temp_dir() . '/' . uniqid('inventaire-', true);

    mkdir($racine . '/storage/logs', 0o755, true);
    mkdir($racine . '/app/logs', 0o755, true);
    mkdir($racine . '/src/vendor', 0o755, true);
    file_put_contents($racine . '/storage/logs/bruit.log', 'lanceur de tests');
    file_put_contents($racine . '/app/logs/metier.log', 'écrit par le sujet');
    file_put_contents($racine . '/src/vendor/paquet.php', 'dépendance');

    $chemins = array_keys(ShellProbe::inventory([$racine]));

    exec('rm -rf ' . escapeshellarg($racine));

    // Exclusions ancrées sur la racine : ce sont les chemins que le LANCEUR
    // écrit lui-même.
    expect($chemins)
        ->not->toContain($racine . '/storage/logs/bruit.log');
    expect($chemins)
        ->not->toContain($racine . '/src/vendor/paquet.php');

    // 🔴 CE QUE LE FILTRE PAR NOM DE BASE LAISSAIT ÉCHAPPER. `logs`, `vendor`,
    // `node_modules` et `debugbar` étaient exclus À TOUTE PROFONDEUR : un
    // script écrivant dans `app/logs/` sortait du champ de la garde sans que
    // rien ne le signale. Les exclusions sont désormais des CHEMINS.
    expect($chemins)
        ->toContain($racine . '/app/logs/metier.log');
});

it('inventory survit à un lien symbolique pendant', function (): void {
    $racine = sys_get_temp_dir() . '/' . uniqid('inventaire-lien-', true);

    mkdir($racine, 0o755, true);
    file_put_contents($racine . '/reel.txt', 'présent');
    symlink($racine . '/cible-inexistante', $racine . '/pendant');

    // `SplFileInfo::getMTime()` LÈVE sur un lien pendant : le test mourrait sur
    // une exception au lieu d'une assertion, en masquant ce qu'il mesure.
    // `src/public/storage` est précisément pendant sur l'hôte.
    $entrees = ShellProbe::inventory([$racine]);

    exec('rm -rf ' . escapeshellarg($racine));

    expect($entrees)
        ->toHaveKey($racine . '/pendant');
    expect($entrees[$racine . '/pendant'])->toBe('INACCESSIBLE:0');
    expect($entrees)
        ->toHaveKey($racine . '/reel.txt');
});

it('SCRIPTS-REFERENCE.md compte les scripts qui existent VRAIMENT', function (): void {
    $doc = RepoFile::read('docs/SCRIPTS-REFERENCE.md');

    $racine = ShellProbe::repoRoot() . '/scripts';
    $compte = static fn (string $motif): int => count(glob($motif) ?: []);

    $parRepertoire = [
        'racine' => $compte($racine . '/*.sh'),
        'install' => $compte($racine . '/install/*.sh'),
        'lib' => $compte($racine . '/lib/*.sh'),
        'ops' => $compte($racine . '/ops/*.sh'),
        'security' => $compte($racine . '/security/*.sh'),
        'setup' => $compte($racine . '/setup/*.sh'),
    ];

    // Anti-vacuité : sur un `glob()` qui échouerait, tout vaudrait 0 et les
    // assertions compareraient du vide à du vide.
    expect(array_sum($parRepertoire))
        ->toBeGreaterThan(20);

    // 🔴 Ces quatre nombres étaient TOUS faux le 2026-08-22 : « 26 scripts »
    // pour 33, « install/ (9) » pour 11, « racine (15) » pour 12, et `ops/`
    // absent de l'arbre alors qu'il porte toute la stratégie de sauvegarde
    // (ADR-0003). Un décompte dans une doc est un garde-fou silencieux né
    // vieux : personne ne le recompte, et il se dégrade à chaque script ajouté
    // — celui de cette story compris.
    expect($doc)
        ->toContain('**Total**: ' . array_sum($parRepertoire) . ' scripts shell');
    expect($doc)
        ->toContain('Scripts racine (' . $parRepertoire['racine'] . ' fichiers)');
    expect($doc)
        ->toContain('Installation modulaire (' . $parRepertoire['install'] . ' scripts)');
    expect($doc)
        ->toContain('Bibliothèques partagées (' . $parRepertoire['lib'] . ' scripts)');
    expect($doc)
        ->toContain('Exploitation — sauvegardes (' . $parRepertoire['ops'] . ' scripts)');
    expect($doc)
        ->toContain('Sécurité (' . $parRepertoire['security'] . ' script)');
    expect($doc)
        ->toContain('Configuration (' . $parRepertoire['setup'] . ' scripts)');

    // Chaque script de `lib/` est nommé dans le tableau des bibliothèques :
    // c'est ce qui a manqué à `runtime.sh`, livré sans une ligne de doc.
    foreach (glob($racine . '/lib/*.sh') ?: [] as $bibliotheque) {
        expect($doc)->toContain('`' . basename($bibliotheque) . '`');
    }
});

// =============================================================================
// CI
// =============================================================================

it('la CI se déclenche sur scripts/lib/** et scripts/install/**', function (): void {
    $workflow = RepoFile::yaml('.github/workflows/ci.yml');

    foreach (['push', 'pull_request'] as $evenement) {
        $paths = RepoFile::stringList($workflow, "on.{$evenement}.paths");

        // Sans ces entrées, le garde-fou de cette story existe mais rien ne le
        // rejoue : on peut casser `retry` sans qu'aucune CI ne démarre.
        expect($paths)
            ->toContain('scripts/lib/**');
        expect($paths)
            ->toContain('scripts/install/**');
    }
});
