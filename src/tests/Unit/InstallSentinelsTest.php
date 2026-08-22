<?php

declare(strict_types=1);

use Tests\Support\RepoFile;
use Tests\Support\ShellProbe;

/*
|--------------------------------------------------------------------------
| Install idempotente — sentinelles de module + lockfile (Story 2.2)
|--------------------------------------------------------------------------
|
| Suite Unit : aucun de ces tests ne boote Laravel. Ils lancent `bash` et
| lisent ce qu'il rend — seul véhicule capable de faire ROUGIR du shell tant
| que Bats n'est pas là (Story 2.4).
|
| ⛔ AUCUNE INSTALLATION RÉELLE N'EST JOUÉE ICI. Le job `tests` a
| `timeout-minutes: 20` pour la suite entière. Ce qui est sous test est
| l'ORCHESTRATEUR : `scripts/install.sh` est SOURCÉ (garde `BASH_SOURCE`) et
| seule la sonde `execute_module` est remplacée par un compteur. La boucle, le
| fail-fast, le calcul de sentinelle et `ensure_idempotent` sont exactement
| ceux qui partent en production. Même principe pour le lockfile : le binaire
| `docker` est un stub dans un PATH reconstruit, aucun conteneur réel.
|
| Aucun helper ne vit ici : ils sont tous sur `Tests\Support\ShellProbe`.
|
*/

/**
 * Prélude commun : un bac à sable jetable, une racine d'état INJECTÉE, et
 * l'orchestrateur sourcé avec `execute_module` remplacé par un journal.
 *
 * L'injection n'est pas un confort de test : `ShellProbe` fixe son cwd sur
 * l'arbre applicatif réel, et sans `INSTALL_STATE_DIR` l'installeur y sèmerait
 * ses sentinelles.
 */
function orchestrateurSousSonde(string $corps): string
{
    return <<<BASH
        set -e
        bac="\$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "\$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
        esac
        export INSTALL_STATE_DIR="\$bac/etat"
        export LOG_FILE="\$bac/install.log"
        journal="\$bac/journal"
        : > "\$journal"

        source "\$INSTALL_SH"

        execute_module() {
            echo "\$1" >> "\$journal"
            return 0
        }

        cible="\$bac/cible"
        mkdir -p "\$cible"
        TARGET_DIR="\$cible"

        joues() {
            echo "\$1=[\$(tr '\\n' ',' < "\$journal")]"
            : > "\$journal"
        }

        {$corps}

        rm -rf "\$bac"
        BASH;
}

// =============================================================================
// Le sujet VERSIONNÉ — matrice : 1re install, reprise, échec, rejeu, --force
// =============================================================================

it('le sujet versionné de l’idempotence reprend là où l’install a échoué', function (): void {
    $result = ShellProbe::runFile(ShellProbe::idempotenceSubject(), [], 60);

    $modules = ShellProbe::installModules();
    $total = count($modules);

    // Anti-vacuité : sur une lecture ratée du tableau INSTALL_MODULES, tout
    // ce qui suit comparerait du vide à du vide.
    expect($total)
        ->toBe(11);
    expect($result['output'])->toContain('TOTAL_MODULES=' . $total);

    // ── Passe 1 : le module 30 échoue ────────────────────────────────────
    // Fail-fast conservé : l'install s'arrête, et le code du module remonte.
    expect($result['output'])->toMatch('/^PASSE1_STATUS=7$/m');
    expect($result['output'])->toContain(
        'PASSE1_JOUES=[00-prerequisites,05-composer-setup,10-laravel-core,20-database,30-packages-prod,]',
    );
    // 4 sentinelles pour 5 modules joués : le module en ÉCHEC n'en pose pas.
    expect($result['output'])->toMatch('/^PASSE1_SENTINELLES=4$/m');

    // ── Passe 2 : relance NUE, sans --resume-from ────────────────────────
    // C'est l'AC de tête : l'opérateur ne tape rien, la reprise est portée par
    // l'état sur disque.
    expect($result['output'])->toMatch('/^PASSE2_STATUS=0$/m');
    expect($result['output'])->toContain(
        'PASSE2_JOUES=[30-packages-prod,35-configure-spatie-packages,40-packages-dev,'
        . '45-configure-pest,50-quality-tools,60-nightwatch,99-finalize,]',
    );
    expect($result['output'])->toMatch('/^PASSE2_SENTINELLES=' . $total . '$/m');

    // ── Passe 3 : tout est franchi ───────────────────────────────────────
    expect($result['output'])->toMatch('/^PASSE3_STATUS=0$/m');
    expect($result['output'])->toMatch('/^PASSE3_JOUES=\[\]$/m');

    // ── Passe 4 : --force rejoue les 11 ──────────────────────────────────
    expect($result['output'])->toMatch('/^PASSE4_STATUS=0$/m');
    expect($result['output'])->toContain('PASSE4_JOUES=[' . implode(',', $modules) . ',]');
    expect($result['output'])->toMatch('/^PASSE4_SENTINELLES=' . $total . '$/m');

    expect($result['status'])->toBe(0);
});

it('la sentinelle porte l’identifiant de module, jamais le libellé de l’étape', function (): void {
    $result = ShellProbe::run(orchestrateurSousSonde(<<<'BASH'
        run_installation > /dev/null 2>&1
        echo "SENTINELLES=[$(cd "$INSTALL_STATE_DIR" && ls *-done | sort | tr '\n' ',')]"
        echo "CHEMIN=$(sentinel_path_for_module 30-packages-prod)"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    $attendues = array_map(static fn (string $m): string => $m . '-done', ShellProbe::installModules());
    sort($attendues);

    // Le grain est l'identifiant du tableau INSTALL_MODULES — stable, unique,
    // validé, et déjà l'identité publique de --only/--resume-from. Les libellés
    // de `log_step_start` sont des phrases françaises accentuées : ils ne font
    // pas des noms de fichiers.
    expect($result['output'])->toContain('SENTINELLES=[' . implode(',', $attendues) . ',]');
    expect($result['output'])->toContain('CHEMIN=');
    expect($result['output'])->toMatch('#CHEMIN=\S+/30-packages-prod-done#');
});

it('la racine d’état par défaut se dérive du répertoire cible', function (): void {
    // Aucune injection ici : c'est le DÉFAUT qui est mesuré.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
        export LOG_FILE="$bac/install.log"
        unset INSTALL_STATE_DIR

        source "$INSTALL_SH"

        execute_module() { return 0; }

        cible="$bac/cible"
        mkdir -p "$cible"

        parse_arguments "$cible" > /dev/null 2>&1
        echo "RACINE=$INSTALL_STATE_DIR"

        run_installation > /dev/null 2>&1
        [ -f "$cible/.install-state/99-finalize-done" ] && echo "SENTINELLE=PRESENTE" || echo "SENTINELLE=ABSENTE"
        [ -f "$cible/.install-state/started-at" ] && echo "DEBUT=PRESENT" || echo "DEBUT=ABSENT"

        rm -rf "$bac"
        BASH
        , [
            'INSTALL_SH' => ShellProbe::installScript(),
        ], 60);

    expect($result['output'])->toMatch('#RACINE=\S+/cible/\.install-state$#m');
    expect($result['output'])->toContain('SENTINELLE=PRESENTE');
    expect($result['output'])->toContain('DEBUT=PRESENT');
});

it('--only respecte l’état, et --force le rejoue quand même', function (): void {
    $result = ShellProbe::run(orchestrateurSousSonde(<<<'BASH'
        # Sans positionnel : `TARGET_DIR` est déjà posé par le prélude, et
        # l'orchestrateur refuse un second argument positionnel.
        parse_arguments --only 30-packages-prod > /dev/null 2>&1

        run_installation > /dev/null 2>&1
        joues "ONLY_PREMIER"

        # L'état PRIME sur --only : le module a déjà été franchi.
        run_installation > /dev/null 2>&1
        joues "ONLY_SECOND"

        # --force ignore la sentinelle et la réécrit.
        FORCE=true
        run_installation > /dev/null 2>&1
        joues "ONLY_FORCE"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    expect($result['output'])->toContain('ONLY_PREMIER=[30-packages-prod,]');
    expect($result['output'])->toContain('ONLY_SECOND=[]');
    expect($result['output'])->toContain('ONLY_FORCE=[30-packages-prod,]');
});

it('une racine d’état inécrivable fait ÉCHOUER LA POSE DE SENTINELLE, en nommant le chemin', function (): void {
    // 🔴 CE TEST MESURAIT LE MAUVAIS CHEMIN DE CODE (D2, revue 2).
    // Mesuré avec `ensure_idempotent` INTÉGRALEMENT neutralisée : trois de ses
    // quatre assertions restaient satisfaites — `CHEMIN_NOMME=OUI`,
    // `DIAGNOSTIC=OUI`, `PRETEND_POSEE=NON`. Elles étaient portées par le
    // `log_warn` de `record_installation_start`, c'est-à-dire par le chemin que
    // la story déclare explicitement NON FATAL (l'horodatage est de la
    // métrologie). L'AC « l'échec nomme le chemin et rien ne prétend qu'une
    // sentinelle a été posée » était donc mesurée sur un avertissement.
    //
    // ⛔ La parade : `record_installation_start` est NEUTRALISÉE dans la sonde.
    // Le seul écrivain restant est `ensure_idempotent`, donc tout ce qui est
    // asserté ci-dessous vient du chemin réellement sous test.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
        interdit="$bac/lecture-seule"
        mkdir -p "$interdit"
        chmod a-w "$interdit"

        export INSTALL_STATE_DIR="$interdit/etat"
        export LOG_FILE="$bac/install.log"

        source "$INSTALL_SH"

        # ⛔ La métrologie est éteinte : elle journalise sur le même sujet
        # (« impossible à écrire », le chemin) sans être fatale, et c'est elle
        # qui satisfaisait les assertions à la place du sujet réel.
        record_installation_start() { return 0; }

        # Compteur : le module DOIT avoir tourné. Si la pose de sentinelle
        # échouait AVANT l'exécution, l'échec serait juste pour une mauvaise
        # raison — et l'étape ne serait pas rejouable comme la story le promet.
        journal="$bac/journal"
        : > "$journal"
        execute_module() { echo "$1" >> "$journal"; return 0; }

        cible="$bac/cible"
        mkdir -p "$cible"
        TARGET_DIR="$cible"

        status=0
        run_installation > "$bac/sortie" 2>&1 || status=$?

        echo "STATUS=$status"
        echo "MODULES_JOUES=$(wc -l < "$journal" | tr -d ' ')"
        echo "PREMIER_JOUE=$(head -1 "$journal")"

        # Le diagnostic vient-il d'`ensure_idempotent` ET nomme-t-il la
        # sentinelle du module, pas seulement la racine d'état ?
        grep -q "ensure_idempotent : sentinelle impossible à écrire" "$bac/sortie" \
            && echo "DIAGNOSTIC=SENTINELLE" || echo "DIAGNOSTIC=AUTRE"
        grep -q "$INSTALL_STATE_DIR/00-prerequisites-done" "$bac/sortie" \
            && echo "SENTINELLE_NOMMEE=OUI" || echo "SENTINELLE_NOMMEE=NON"
        grep -q "l'étape sera rejouée" "$bac/sortie" \
            && echo "REJEU_ANNONCE=OUI" || echo "REJEU_ANNONCE=NON"
        grep -q "sentinelle posée" "$bac/sortie" \
            && echo "PRETEND_POSEE=OUI" || echo "PRETEND_POSEE=NON"

        # Et sur le disque : rien n'a été posé.
        echo "SENTINELLES_SUR_DISQUE=$(find "$INSTALL_STATE_DIR" -name '*-done' 2>/dev/null | wc -l | tr -d ' ')"

        chmod u+w "$interdit"
        rm -rf "$bac"
        BASH
        , [
            'INSTALL_SH' => ShellProbe::installScript(),
        ], 60);

    expect($result['output'])->not->toContain('BAC_HORS_TMP');

    // ⚠️ `test -w` rend VRAI sur le montage ro de ce dépôt : ce qui tranche est
    // l'écriture RÉELLE, relue sur disque par `ensure_idempotent`.
    expect($result['output'])->toMatch('/^STATUS=1$/m');

    // Le module a bien tourné : l'échec est POSTÉRIEUR à son exécution, donc
    // c'est bien la pose de sentinelle qui a refusé.
    expect($result['output'])->toMatch('/^MODULES_JOUES=1$/m');
    expect($result['output'])->toContain('PREMIER_JOUE=00-prerequisites');

    // Le diagnostic vient d'`ensure_idempotent`, nomme LA SENTINELLE du module
    // (pas seulement le répertoire), et annonce le rejeu.
    expect($result['output'])->toContain('DIAGNOSTIC=SENTINELLE');
    expect($result['output'])->toContain('SENTINELLE_NOMMEE=OUI');
    expect($result['output'])->toContain('REJEU_ANNONCE=OUI');

    // Rien ne prétend qu'une sentinelle a été posée — et le disque le confirme.
    expect($result['output'])->toContain('PRETEND_POSEE=NON');
    expect($result['output'])->toMatch('/^SENTINELLES_SUR_DISQUE=0$/m');
});

it('l’orchestrateur dispose bien des primitives de runtime.sh', function (): void {
    // Formulation FONCTIONNELLE et non textuelle : un `grep "runtime.sh"` sur
    // le fichier resterait vert sur un `source` commenté ou mal chemin­né.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        export LOG_FILE="$(mktemp)"
        source "$INSTALL_SH"
        for primitive in ensure_idempotent die retry require_cmd; do
            if declare -F "$primitive" > /dev/null 2>&1; then
                echo "DISPONIBLE=$primitive"
            fi
        done
        rm -f "$LOG_FILE"
        BASH
        , [
            'INSTALL_SH' => ShellProbe::installScript(),
        ]);

    expect($result['output'])->toContain('DISPONIBLE=ensure_idempotent');
    expect($result['output'])->toContain('DISPONIBLE=die');
    expect($result['output'])->toContain('DISPONIBLE=retry');
    expect($result['output'])->toContain('DISPONIBLE=require_cmd');
});

it('--dry-run n’écrit NI sentinelle NI horodatage, et lit l’état sans le modifier', function (): void {
    // 🔴 RÉGRESSION ÉVITÉE, PAS HYPOTHÉTIQUE. Envelopper `execute_module` dans
    // `ensure_idempotent` sans exclure la simulation faisait ÉCRIRE la
    // sentinelle d'un module qui n'a jamais tourné — `execute_module` rend 0
    // sous `--dry-run`. L'install réelle suivante aurait alors sauté les 11
    // modules et déclaré succès. La contrainte d'epic est explicite :
    // « --dry-run sans AUCUN effet de bord, ni fichier, ni conteneur ».
    $result = ShellProbe::run(orchestrateurSousSonde(<<<'BASH'
        # 1) Simulation sur une racine d'état VIERGE.
        DRY_RUN=true
        run_installation > /dev/null 2>&1
        echo "APRES_DRYRUN=$(find "$INSTALL_STATE_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
        joues "SIMULES"

        # 2) L'install réelle qui suit doit jouer les 11 modules.
        DRY_RUN=false
        run_installation > /dev/null 2>&1
        joues "REEL_APRES_DRYRUN"

        # 3) Simulation sur une racine d'état PLEINE : elle LIT sans écrire,
        #    et n'efface rien même sous --force.
        empreinte_avant="$(find "$INSTALL_STATE_DIR" -type f | sort | md5sum)"
        DRY_RUN=true
        FORCE=true
        run_installation > "$bac/simulation" 2>&1
        empreinte_apres="$(find "$INSTALL_STATE_DIR" -type f | sort | md5sum)"
        [ "$empreinte_avant" = "$empreinte_apres" ] && echo "ETAT=INTACT" || echo "ETAT=MODIFIE"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    // Rien sur disque après une simulation à froid : ni sentinelle, ni `started-at`.
    expect($result['output'])->toContain('APRES_DRYRUN=0');
    // …alors que la simulation a bien PARCOURU les 11 modules : ce qui est
    // supprimé est l'effet de bord, pas la simulation elle-même.
    expect($result['output'])->toContain('SIMULES=[' . implode(',', ShellProbe::installModules()) . ',]');
    // …donc l'install réelle a encore les 11 modules à jouer.
    expect($result['output'])->toContain('REEL_APRES_DRYRUN=[' . implode(',', ShellProbe::installModules()) . ',]');
    // Et une simulation à chaud, --force compris, ne détruit aucune sentinelle.
    expect($result['output'])->toContain('ETAT=INTACT');
});

it('--force atteint les modules, qui tournent en SOUS-PROCESSUS', function (): void {
    // 🔴 GARDE-FOU MANQUANT, CONSTATÉ PAR EXÉCUTION (revue 1) : retirer
    // l'`export` laissait 19/19 VERT. Le module 10 lit `INSTALL_FORCE` pour
    // savoir si un nettoyage DESTRUCTEUR est autorisé ; sans export, il ne le
    // voit jamais et le message « relancez avec --force » est un cul-de-sac.
    //
    // ⚠️ CE QUE MESURE CE TEST EST CE QU'UN FILS VOIT, pas ce que le parent
    // croit. C'est la seule mesure qui vaille : une variable non exportée est
    // invisible d'un sous-processus, quoi qu'en dise le parent — et
    // `execute_module` lance réellement les modules en sous-processus.
    //
    // La première rédaction de ce garde interrogeait un fils lancé À CÔTÉ de
    // `parse_arguments`. Elle a démasqué mieux qu'elle ne visait : le drapeau
    // était dérivé dans DEUX endroits, et un appelant posant `FORCE=true` sans
    // parser d'arguments — la fixture versionnée, `install-laravel-prod` et ses
    // cinq processus — laissait le fils voir `<absent>`. La dérivation est
    // maintenant unique, dans `run_installation`, et c'est ce chemin-là qui est
    // éprouvé ici.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
        export LOG_FILE="$bac/install.log"
        export INSTALL_STATE_DIR="$bac/etat"

        source "$INSTALL_SH"

        # La sonde REMPLACE l'exécution du module, mais garde ce qui compte :
        # un vrai sous-processus, comme `execute_module` en lance un.
        execute_module() {
            bash -c 'echo "FILS_VOIT=[${INSTALL_FORCE:-<absent>}]"' >> "$bac/vu"
            return 0
        }

        passe() {
            : > "$bac/vu"
            TARGET_DIR="$bac/cible-$1"
            mkdir -p "$TARGET_DIR"
            INSTALL_STATE_DIR="$bac/etat-$1"
            run_installation > /dev/null 2>&1
            echo "$1=$(sort -u "$bac/vu" | tr -d '\n')"
        }

        FORCE=false
        passe "SANS"

        FORCE=true
        passe "AVEC"

        rm -rf "$bac"
        BASH
        , [
            'INSTALL_SH' => ShellProbe::installScript(),
        ], 60);

    // Les 11 modules voient la MÊME valeur : `sort -u` réduit à une ligne, donc
    // un seul module discordant ferait rougir.
    expect($result['output'])->toMatch('/^SANS=FILS_VOIT=\[false\]$/m');
    expect($result['output'])->toMatch('/^AVEC=FILS_VOIT=\[true\]$/m');
    // Jamais `<absent>` : c'est ce que voyait un fils quand la dérivation vivait
    // dans `parse_arguments` et que l'appelant ne parsait pas d'arguments.
    expect($result['output'])->not->toContain('<absent>');
});

it('un INSTALL_FORCE hérité de l’environnement n’autorise AUCUNE destruction', function (): void {
    // La seconde moitié du garde précédent : un `INSTALL_FORCE=true` qui traîne
    // dans l'environnement — un shell d'opérateur, un `docker exec -e`, une
    // variable posée par une autre story — ne doit pas suffire à faire effacer
    // une installation partielle. C'est la valeur DEMANDÉE sur la ligne de
    // commande qui décide, jamais l'ambiance.
    //
    // ⚖️ La revue demandait cette remise à plat en tête de `parse_arguments`.
    // Elle est tenue au SEUL endroit qui la rend indéformable : la dérivation
    // unique de `run_installation`. Mesuré — avec les deux, retirer celle de
    // `parse_arguments` laissait la suite VERTE : un second garde qu'aucune
    // mutation ne peut faire rougir. La propriété est la même, elle est ici
    // prouvée sur le chemin réel plutôt que sur l'emplacement du code.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
        export LOG_FILE="$bac/install.log"
        export INSTALL_STATE_DIR="$bac/etat"

        # Le poison : hérité, jamais demandé.
        export INSTALL_FORCE=true

        source "$INSTALL_SH"

        execute_module() {
            bash -c 'echo "FILS_VOIT=[${INSTALL_FORCE:-<absent>}]"' >> "$bac/vu"
            return 0
        }

        : > "$bac/vu"
        TARGET_DIR="$bac/cible"
        mkdir -p "$TARGET_DIR"
        # Aucun --force n'a été demandé sur la ligne de commande.
        FORCE=false
        run_installation > /dev/null 2>&1

        echo "HERITE=$(sort -u "$bac/vu" | tr -d '\n')"

        rm -rf "$bac"
        BASH
        , [
            'INSTALL_SH' => ShellProbe::installScript(),
        ], 60);

    // La valeur héritée est ÉCRASÉE par la dérivation depuis `FORCE`.
    expect($result['output'])->toMatch('/^HERITE=FILS_VOIT=\[false\]$/m');
    expect($result['output'])->not->toContain('FILS_VOIT=[true]');
});

it('started-at est WRITE-ONCE à la reprise, et réécrit sous --force', function (): void {
    // 🔴 GARDE-FOU MANQUANT, CONSTATÉ PAR EXÉCUTION (revue 1) : retirer la
    // garde write-once laissait 19/19 VERT. Sans elle, chaque reprise après
    // crash réécrit l'heure de départ, et la fenêtre `started_at`→`finished_at`
    // du lockfile ne mesure plus que le DERNIER passage. C'est précisément ce
    // que la story 2.4 relira contre la promesse « install < 15 min » : une
    // install de 40 minutes en trois reprises s'y annoncerait comme 4 minutes.
    $result = ShellProbe::run(orchestrateurSousSonde(<<<'BASH'
        marqueur="$INSTALL_STATE_DIR/started-at"

        # Passe 1 : échec au module 30, l'horodatage est posé.
        execute_module() {
            echo "$1" >> "$journal"
            [ "$1" = "30-packages-prod" ] && return 7
            return 0
        }
        run_installation > /dev/null 2>&1 || true
        premier="$(cat "$marqueur")"
        echo "PASSE1=[$premier]"

        # L'horloge du sujet a une seconde de résolution : sans cette attente,
        # « inchangé » serait indiscernable de « réécrit à l'identique », et le
        # test passerait même sans la garde. C'est la différence entre mesurer
        # et croire mesurer.
        sleep 2

        # Passe 2 : reprise nue. L'heure de DÉPART ne doit pas bouger.
        execute_module() { echo "$1" >> "$journal"; return 0; }
        run_installation > /dev/null 2>&1
        second="$(cat "$marqueur")"
        [ "$second" = "$premier" ] && echo "REPRISE=INCHANGE" || echo "REPRISE=REECRIT"

        sleep 2

        # Passe 3 : --force repart de zéro, donc une nouvelle fenêtre.
        FORCE=true
        run_installation > /dev/null 2>&1
        troisieme="$(cat "$marqueur")"
        [ "$troisieme" = "$premier" ] && echo "FORCE=INCHANGE" || echo "FORCE=REECRIT"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    expect($result['output'])->toMatch('/^PASSE1=\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\]$/m');
    expect($result['output'])->toContain('REPRISE=INCHANGE');
    // `--force` rejoue TOUT : conserver l'ancienne heure décrirait une fenêtre
    // qui n'a jamais existé.
    expect($result['output'])->toContain('FORCE=REECRIT');
});

it('--only --force NE REPART PAS la fenêtre d’installation', function (): void {
    // 🔴 RELEVÉ REVUE 2, prouvé par exécution : `record_installation_start`
    // réécrivait dès `FORCE=true`, sans égard à `ONLY_MODULE`. Un rejeu ciblé
    // d'un seul module — `install.sh --only 30-packages-prod --force` —
    // republiait donc un `started_at` postérieur à l'install complète, décrivant
    // la reprise d'UN module et non l'installation. C'est le mode de défaillance
    // que M13 avait fait garder, revenu par une autre porte : la story 2.4 lira
    // ce champ contre la promesse « install < 15 min ».
    //
    // Le garde de la revue 1 n'exerçait que des passes COMPLÈTES ; c'est ce qui
    // a laissé le trou.
    $result = ShellProbe::run(orchestrateurSousSonde(<<<'BASH'
        marqueur="$INSTALL_STATE_DIR/started-at"

        # Install complète, qui pose la fenêtre de référence.
        run_installation > /dev/null 2>&1
        reference="$(cat "$marqueur")"
        echo "REFERENCE=[$reference]"

        # L'horodatage a une résolution d'une seconde : sans attendre, « inchangé »
        # serait indiscernable de « réécrit à l'identique ».
        sleep 2

        # Rejeu CIBLÉ et forcé : X est rejoué, l'installation ne recommence pas.
        ONLY_MODULE="30-packages-prod"
        FORCE=true
        run_installation > /dev/null 2>&1
        apres_only="$(cat "$marqueur")"
        [ "$apres_only" = "$reference" ] && echo "ONLY_FORCE=INCHANGE" || echo "ONLY_FORCE=REECRIT"

        sleep 2

        # Rejeu COMPLET et forcé : là, une nouvelle fenêtre est légitime.
        ONLY_MODULE=""
        FORCE=true
        run_installation > /dev/null 2>&1
        apres_complet="$(cat "$marqueur")"
        [ "$apres_complet" = "$reference" ] && echo "FORCE_COMPLET=INCHANGE" || echo "FORCE_COMPLET=REECRIT"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    expect($result['output'])->toMatch('/^REFERENCE=\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\]$/m');
    // ⛔ Le cœur du correctif : un rejeu ciblé ne touche pas la fenêtre.
    expect($result['output'])->toContain('ONLY_FORCE=INCHANGE');
    // Et le rejeu complet la repart, sinon `--force` décrirait une install qui
    // n'a jamais eu lieu à cette heure-là.
    expect($result['output'])->toContain('FORCE_COMPLET=REECRIT');
});

it('le rapport final distingue une install RÉELLE d’une install entièrement sautée', function (): void {
    // 🔴 GARDE-FOU ABSENT (D1, revue 2) : le verdict `NO-OP`/`EXECUTED` ajouté
    // par le correctif 10 de la revue 1 n'était gardé par RIEN — `grep -rn
    // VERDICT` ne rendait que les deux lignes qui l'écrivent, et supprimer le
    // bloc laissait 34/34 vert. C'est un CONTRAT INTER-STORIES : la 2.4 doit
    // pouvoir distinguer une install réelle d'une install sautée, faute de quoi
    // un smoke nightly mesurerait « install < 15 min » sur une install où rien
    // n'a tourné. Livré sans garde, dans la story dont un AC dit « chaque
    // garde-fou rougit ».
    $result = ShellProbe::run(orchestrateurSousSonde(<<<'BASH'
        # 1er passage : les 11 modules tournent pour de vrai.
        run_installation > "$bac/premier" 2>&1
        grep -q "VERDICT: EXECUTED" "$bac/premier" && echo "PREMIER=EXECUTED" || echo "PREMIER=SANS"
        grep -q "VERDICT: NO-OP" "$bac/premier" && echo "PREMIER_NOOP=OUI" || echo "PREMIER_NOOP=NON"
        grep -oE "VERDICT: EXECUTED — [0-9]+ module" "$bac/premier" | head -1

        # 2e passage : tout est franchi, aucun module ne tourne.
        run_installation > "$bac/second" 2>&1
        grep -q "VERDICT: NO-OP" "$bac/second" && echo "SECOND=NOOP" || echo "SECOND=SANS"
        grep -q "VERDICT: EXECUTED" "$bac/second" && echo "SECOND_EXECUTED=OUI" || echo "SECOND_EXECUTED=NON"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    // Une install qui a réellement joué des modules le DIT, et compte lesquels.
    expect($result['output'])->toContain('PREMIER=EXECUTED');
    expect($result['output'])->toContain('PREMIER_NOOP=NON');
    expect($result['output'])->toContain('VERDICT: EXECUTED — 11 module');

    // Une install entièrement sautée rend 0 comme l'autre, mais ne se confond
    // pas avec elle.
    expect($result['output'])->toContain('SECOND=NOOP');
    expect($result['output'])->toContain('SECOND_EXECUTED=NON');
});

it('le rapport d’échec ne promet plus que --resume-from force un point de reprise', function (): void {
    // 🔴 GARDE-FOU ABSENT (D1, revue 2) : les trois lignes de `show_error_report`
    // réécrites par le correctif 10 n'étaient gardées par rien non plus.
    // L'ancienne rédaction disait « --resume-from <module> » comme si elle
    // forçait un point de reprise. L'état PRIME désormais : `--resume-from X`
    // ne fait que sauter ce qui PRÉCÈDE X ; un module situé après X et portant
    // déjà sa sentinelle reste sauté. Le seul drapeau qui force un rejeu est
    // `--force`. Un opérateur qui suit une consigne fausse perd son temps sur
    // le mode de défaillance le plus coûteux : celui où rien ne se passe.
    $result = ShellProbe::run(orchestrateurSousSonde(<<<'BASH'
        execute_module() {
            echo "$1" >> "$journal"
            [ "$1" = "30-packages-prod" ] && return 4
            return 0
        }

        status=0
        run_installation > "$bac/sortie" 2>&1 || status=$?
        echo "STATUS=$status"
        grep -q "il ne rejoue pas un module déjà franchi" "$bac/sortie" \
            && echo "NUANCE=PRESENTE" || echo "NUANCE=ABSENTE"
        grep -q "force rejoue tout" "$bac/sortie" \
            && echo "SORTIE_FORCE=NOMMEE" || echo "SORTIE_FORCE=ABSENTE"
        grep -q "la reprise est automatique" "$bac/sortie" \
            && echo "REPRISE_AUTO=DITE" || echo "REPRISE_AUTO=TUE"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=4$/m');
    // Les trois lignes du correctif 10, chacune assertée.
    expect($result['output'])->toContain('REPRISE_AUTO=DITE');
    expect($result['output'])->toContain('NUANCE=PRESENTE');
    expect($result['output'])->toContain('SORTIE_FORCE=NOMMEE');
});

it('les défauts de racine d’état de l’installeur et du lockfile DÉSIGNENT le même répertoire', function (): void {
    // 🔴 GARDE-FOU MANQUANT, CONSTATÉ PAR EXÉCUTION (revue 1) : détourner le
    // défaut d'`install-lockfile.sh` vers /tmp laissait 19/19 VERT. Les deux
    // scripts dérivent pourtant ce chemin SÉPARÉMENT — l'installeur depuis
    // `TARGET_DIR` (conteneur), le lockfile depuis `REPO_ROOT/src` (hôte).
    // Rien ne les accordait, et un désaccord ne se voit qu'à l'exécution
    // réelle : l'installeur écrit ici, le lockfile cherche là, et
    // `make install-dev-full` meurt en « horodatage introuvable » à sa
    // dernière étape, sur une install RÉUSSIE.
    //
    // ⚠️ CE QUI EST COMPARÉ EST L'IDENTITÉ DU RÉPERTOIRE, PAS LA CHAÎNE.
    // Mesuré : dans le conteneur, `src/` est monté DEUX FOIS — `/var/www/html`
    // (rw) et `/var/www/project/src` (ro) — et `realpath` ne résout pas un
    // point de montage. Les deux chaînes diffèrent donc légitimement tout en
    // désignant le même répertoire (device:inode identiques, vérifié). Comparer
    // les chaînes rendrait ce test rouge sur un code juste ; comparer les
    // inodes mesure ce qui compte vraiment : les deux scripts écrivent-ils et
    // lisent-ils au même endroit.
    //
    // Aucune injection : ce sont les DÉFAUTS qui sont mesurés.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
        export LOG_FILE="$bac/log"
        unset INSTALL_STATE_DIR

        # Côté installeur : la cible EST l'arbre applicatif — c'est ce que rend
        # `detect_working_directory`, donc ce que porte TARGET_DIR.
        installeur="$(
            unset INSTALL_STATE_DIR
            source "$INSTALL_SH" > /dev/null 2>&1
            TARGET_DIR="$SRC_DIR"
            init_install_state_dir
            echo "$INSTALL_STATE_DIR"
        )"

        # Côté lockfile : sourcé sans exécuter (garde BASH_SOURCE).
        lockfile="$(
            unset INSTALL_STATE_DIR
            export REPO_ROOT
            source "$LOCKFILE_SH" > /dev/null 2>&1
            echo "$INSTALL_STATE_DIR"
        )"

        echo "INSTALLEUR=$installeur"
        echo "LOCKFILE=$lockfile"
        echo "BASE_INSTALLEUR=$(basename "$installeur")"
        echo "BASE_LOCKFILE=$(basename "$lockfile")"

        # Identité du répertoire PARENT : device:inode, insensible aux montages.
        echo "INODE_INSTALLEUR=$(stat -c '%d:%i' "$(dirname "$installeur")")"
        echo "INODE_LOCKFILE=$(stat -c '%d:%i' "$(dirname "$lockfile")")"

        rm -rf "$bac"
        BASH
        , [
            'INSTALL_SH' => ShellProbe::installScript(),
            'LOCKFILE_SH' => ShellProbe::lockfileScript(),
            'SRC_DIR' => ShellProbe::srcDir(),
            'REPO_ROOT' => ShellProbe::repoRoot(),
        ], 60);

    $lire = static function (string $cle) use ($result): string {
        $trouve = [];

        // Anti-vacuité : un relevé manquant doit ROUGIR, pas produire une
        // chaîne vide qu'on comparerait à une autre chaîne vide.
        expect(preg_match('/^' . $cle . '=(.+)$/m', $result['output'], $trouve))
            ->toBe(1, "Relevé {$cle} absent de la sonde :\n" . $result['output']);

        return trim($trouve[1]);
    };

    // Même nom de répertoire d'état des deux côtés.
    expect($lire('BASE_INSTALLEUR'))
        ->toBe('.install-state');
    expect($lire('BASE_LOCKFILE'))
        ->toBe('.install-state');

    // Et surtout : le même répertoire parent, prouvé par device:inode.
    expect($lire('INODE_LOCKFILE'))
        ->toBe($lire('INODE_INSTALLEUR'));
});

it('--dry-run RAPPORTE un module injouable au lieu de le compter comme joué', function (): void {
    // 🔴 GESTION D'ERREUR PERDUE PAR LA BRANCHE DE SIMULATION (revue 1).
    // L'ancien code branchait le statut d'`execute_module` : un module absent
    // du disque produisait le rapport d'erreur et une sortie ≠ 0. La branche
    // `--dry-run` ajoutée par cette story appelait `execute_module` NU et
    // comptait le module comme joué quoi qu'il arrive — or `--dry-run` sert
    // exactement à découvrir qu'un module manque AVANT l'installation réelle.
    // Une simulation qui déclare succès sur une install impossible est pire
    // qu'inutile : elle donne une garantie fausse.
    $result = ShellProbe::run(orchestrateurSousSonde(<<<'BASH'
        DRY_RUN=true

        # Le 3e module est injouable — exactement ce qu'un module manquant ou
        # non exécutable produit dans `execute_module`.
        execute_module() {
            echo "$1" >> "$journal"
            [ "$1" = "10-laravel-core" ] && return 5
            return 0
        }

        status=0
        run_installation > "$bac/sortie" 2>&1 || status=$?
        echo "DRY_STATUS=$status"
        joues "DRY_JOUES"
        grep -q "Installation échouée au module: 10-laravel-core" "$bac/sortie" \
            && echo "RAPPORT=OUI" || echo "RAPPORT=NON"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    // Le code du module remonte, comme hors simulation.
    expect($result['output'])->toMatch('/^DRY_STATUS=5$/m');
    // Fail-fast : la simulation s'arrête au module fautif, elle ne parcourt pas
    // les huit suivants en prétendant que tout va bien.
    expect($result['output'])->toContain('DRY_JOUES=[00-prerequisites,05-composer-setup,10-laravel-core,]');
    // Et le rapport d'erreur est émis, ce qui nomme le module à réparer.
    expect($result['output'])->toContain('RAPPORT=OUI');
});

// =============================================================================
// Module 10 — le chemin destructeur devenu refus bruyant
// =============================================================================

/**
 * Prépare une cible portant les marqueurs demandés et joue
 * `clean_target_directory` dessus, module 10 SOURCÉ.
 */
function nettoyageSousSonde(string $preparation, string $environnement = ''): string
{
    return <<<BASH
        set -e
        bac="\$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "\$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
        esac
        cible="\$bac/cible"
        mkdir -p "\$cible"
        export LOG_FILE="\$bac/module.log"
        {$environnement}

        # 🔴 LA RACINE D'ÉTAT EST POSÉE DANS LA CIBLE, ET C'EST LE POINT.
        # Sans elle, ces fixtures décrivaient un état qui N'EXISTE JAMAIS après
        # le module 00 : dès que l'orchestrateur a franchi 00 et 05, la cible
        # porte `.install-state/`. C'est parce qu'aucune fixture ne la posait
        # que 25 mutations n'ont pas vu le `find -delete` emporter les
        # sentinelles et l'horodatage — sur le chemin NOMINAL d'un
        # fork-streamer, pas sur un cas tordu.
        mkdir -p "\$cible/.install-state"
        : > "\$cible/.install-state/00-prerequisites-done"
        : > "\$cible/.install-state/05-composer-setup-done"
        echo "2026-08-22T09:00:00Z" > "\$cible/.install-state/started-at"

        {$preparation}

        status=0
        (
            source "\$MODULE_10"
            clean_target_directory "\$cible"
        ) > "\$bac/sortie" 2>&1 || status=\$?

        echo "STATUS=\$status"
        # RESTANTS compte hors racine d'état : c'est ce que le nettoyage doit
        # emporter. ETAT compte la racine, qu'il ne doit JAMAIS toucher.
        echo "RESTANTS=\$(find "\$cible" -mindepth 1 -not -path "\$cible/.install-state" -not -path "\$cible/.install-state/*" 2>/dev/null | wc -l | tr -d ' ')"
        echo "ETAT=\$(find "\$cible/.install-state" -type f 2>/dev/null | wc -l | tr -d ' ')"
        [ -f "\$cible/.install-state/started-at" ] && echo "DEBUT=SURVIT" || echo "DEBUT=DETRUIT"
        cat "\$bac/sortie"

        rm -rf "\$bac"
        BASH;
}

it('le module 10 PRÉSERVE la racine d’état — le chemin nominal du fork-streamer', function (): void {
    // 🔴 CONSTAT DE TÊTE DE LA REVUE 1, PROUVÉ PAR EXÉCUTION AVANT CORRECTION :
    // une cible portant `.install-state/{00-…,05-…,started-at}` ressortait de
    // `clean_target_directory` avec **0** fichier d'état et un code retour
    // **0**. Ce n'est pas un cas limite : après les modules 00 et 05, la cible
    // n'est jamais « vraiment vide ». L'installeur rejouait donc 00 et 05 à
    // chaque reprise tout en affirmant reprendre où il s'était arrêté, et
    // `install-lockfile.sh` mourait ensuite en « horodatage introuvable » —
    // donc `make install-dev-full` rouge à sa dernière étape sur une install
    // RÉUSSIE.
    $result = ShellProbe::run(nettoyageSousSonde(<<<'BASH'
        # La cible ne porte QUE la racine d'état : c'est exactement ce que le
        # module 10 voit quand 00 et 05 viennent de passer.
        BASH), [
        'MODULE_10' => ShellProbe::installModuleScript('10-laravel-core'),
    ], 60);

    // Le nettoyage est autorisé (rien à sauver hors état) et rend 0…
    expect($result['output'])->toMatch('/^STATUS=0$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->not->toContain('Refus de nettoyer');
    // …et surtout le répertoire est reconnu VIDE : la suppression n'est même
    // pas tentée. C'est cette lecture qui rend vraie la ligne de matrice
    // « cible vraiment vide », dont « vraiment vide » se lit désormais « vide
    // HORS racine d'état ». Sans l'exclusion, l'installeur annoncerait un
    // nettoyage à chaque reprise là où il n'y a rien à nettoyer — et le
    // `find -delete` s'exécuterait sur le chemin nominal, à un filtre près.
    // ⚠️ La chaîne discrimine : `log_debug` émet « Nettoyage du répertoire: »
    // (avec deux-points) à CHAQUE appel ; seule la voie de suppression émet le
    // suffixe ci-dessous.
    expect($result['output'])->not->toContain("(racine d'état préservée)");
    // …mais les trois fichiers d'état sont TOUS là.
    expect($result['output'])->toMatch('/^ETAT=3$/m');
    expect($result['output'])->toMatch('/^DEBUT=SURVIT$/m');
});

it('le module 10 préserve la racine d’état même en nettoyant un résidu', function (): void {
    // La variante qui a démasqué une PARADE FAUSSE : le premier correctif
    // employait `-path … -prune -o`, or `-delete` implique `-depth` et `-prune`
    // est un no-op sous `-depth`. L'état était donc toujours détruit dès qu'un
    // résidu déclenchait réellement la suppression. Sans ce test, la correction
    // du défaut aurait reproduit le défaut.
    $result = ShellProbe::run(nettoyageSousSonde(<<<'BASH'
        echo "residu" > "$cible/note.txt"
        mkdir -p "$cible/sous/dossier"
        echo "profond" > "$cible/sous/dossier/fichier.txt"
        BASH), [
        'MODULE_10' => ShellProbe::installModuleScript('10-laravel-core'),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=0$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toMatch('/^RESTANTS=0$/m');
    expect($result['output'])->toMatch('/^ETAT=3$/m');
    expect($result['output'])->toMatch('/^DEBUT=SURVIT$/m');
});

it('le module 10 préserve la racine d’état même si le CHEMIN porte des métacaractères glob', function (): void {
    // 🔴 TROISIÈME ITÉRATION DU MÊME DÉFAUT, trouvée à la revue 2 et reproduite
    // par exécution : `-not -path "$cible/$etat"` prend un GLOB, pas une chaîne
    // littérale. Une cible nommée `pro[1]jet` ressortait à `etat=0`,
    // `started-at` DÉTRUIT, code retour 0 — les crochets font une classe de
    // caractères, le motif ne correspond plus à son propre chemin, plus rien
    // n'est exclu.
    //
    // Les trois parades successives ont toutes échoué par le MÊME mécanisme :
    // un moteur de motifs là où un littéral était voulu (`find -delete` nu,
    // puis `-prune` inopérant sous `-depth`, puis `-path` glob). Et c'est le
    // mécanisme exact du défaut corrigé en sens inverse dans le lockfile
    // (`grep` appliquant une regex à `projet[1]_node`).
    //
    // ⚠️ POURQUOI 42 MUTATIONS NE L'ONT PAS VU : les fixtures emploient
    // `mktemp -d`, donc `/tmp/tmp.XXXXXXXX` — un chemin sans le moindre
    // métacaractère. Le test ci-dessous crée délibérément des cibles qui en
    // portent, exactement comme le fait déjà la sonde du lockfile.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        racine="$(mktemp -d)"
        case "$racine" in /tmp/*) ;; *) echo "BAC_HORS_TMP=[$racine]"; exit 9 ;; esac
        export LOG_FILE="$racine/module.log"

        # Chaque nom est un piège différent pour un moteur de motifs.
        for base in 'normal' 'pro[1]jet' 'pro*jet' 'proj?et' 'mon projet' 'a[b-z]c'; do
            cible="$racine/$base"
            mkdir -p "$cible/.install-state"
            : > "$cible/.install-state/00-prerequisites-done"
            : > "$cible/.install-state/05-composer-setup-done"
            echo "2026-08-22T09:00:00Z" > "$cible/.install-state/started-at"
            # Un résidu, pour que la SUPPRESSION soit réellement déclenchée :
            # sans lui, le répertoire serait jugé vide et rien ne se passerait.
            echo "residu" > "$cible/note.txt"

            status=0
            (
                source "$MODULE_10"
                clean_target_directory "$cible"
            ) > /dev/null 2>&1 || status=$?

            etat="$(find "$cible/.install-state" -type f 2>/dev/null | wc -l | tr -d ' ')"
            reste="$(ls -A "$cible" 2>/dev/null | grep -cv '^\.install-state$' || true)"
            echo "CIBLE[$base] exit=$status etat=$etat reste=$reste"
        done

        rm -rf "$racine"
        BASH
        , [
            'MODULE_10' => ShellProbe::installModuleScript('10-laravel-core'),
        ], 60);

    expect($result['output'])->not->toContain('BAC_HORS_TMP');

    // Les six cibles doivent se comporter À L'IDENTIQUE : résidu supprimé,
    // trois fichiers d'état intacts, sortie 0. Un seul écart et le glob a mordu.
    foreach (['normal', 'pro[1]jet', 'pro*jet', 'proj?et', 'mon projet', 'a[b-z]c'] as $base) {
        expect($result['output'])
            ->toContain("CIBLE[{$base}] exit=0 etat=3 reste=0");
    }
});

it('le module 10 voit les liens symboliques CASSÉS au lieu de croire le répertoire vide', function (): void {
    // 🔴 `[ -e ]` SUIT LE LIEN : il est FAUX sur un lien pendant (revue 2).
    // Une cible n'en contenant qu'un était jugée VIDE, tout le nettoyage était
    // sauté, la fonction rendait 0 en journalisant « nettoyé avec succès », et
    // le `composer create-project` suivant échouait sur un répertoire non vide
    // — un échec à deux étapes de sa cause.
    $result = ShellProbe::run(nettoyageSousSonde(<<<'BASH'
        # Un lien pendant, et RIEN d'autre hors racine d'état.
        ln -s /destination-inexistante-2-2 "$cible/pendant"
        BASH), [
        'MODULE_10' => ShellProbe::installModuleScript('10-laravel-core'),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=0$/m');
    // Le lien a été VU, donc supprimé : la cible est réellement vide.
    expect($result['output'])->toMatch('/^RESTANTS=0$/m');
    // Et la racine d'état, elle, est toujours là.
    expect($result['output'])->toMatch('/^ETAT=3$/m');
    expect($result['output'])->toMatch('/^DEBUT=SURVIT$/m');
    // La preuve que le nettoyage a bien EU LIEU : le journal l'annonce. Sans
    // `-L`, la fonction sortait sans jamais l'écrire.
    expect($result['output'])->toContain('Nettoyage du répertoire');
});

it('le module 10 refuse de prendre un FICHIER ou un LIEN pour la racine d’état', function (): void {
    // 🔴 LA RACINE D'ÉTAT N'ÉTAIT JAMAIS TYPÉE (revue 2). Deux conséquences
    // mesurées, symétriques et toutes deux silencieuses :
    //   • un FICHIER nommé `.install-state` était exclu de la mesure de vacuité
    //     ET de la suppression — répertoire réputé vide, fichier resté, install
    //     bloquée à l'étape suivante ;
    //   • un SYMLINK `.install-state` vers un dossier interne faisait supprimer
    //     le dossier RÉEL pendant que le journal annonçait « préservée ».
    // `ensure_idempotent` refuse explicitement une sentinelle-répertoire
    // (`runtime.sh:231`) ; la racine mérite la même discipline.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        racine="$(mktemp -d)"
        case "$racine" in /tmp/*) ;; *) echo "BAC_HORS_TMP=[$racine]"; exit 9 ;; esac
        export LOG_FILE="$racine/module.log"

        # --- cas 1 : un FICHIER nommé .install-state
        c1="$racine/c1"; mkdir -p "$c1"
        echo "je-ne-suis-pas-un-repertoire" > "$c1/.install-state"
        s1=0
        ( source "$MODULE_10"; clean_target_directory "$c1" ) > "$racine/o1" 2>&1 || s1=$?
        echo "FICHIER exit=$s1 reste=$(ls -A "$c1" | wc -l | tr -d ' ')"
        grep -q "n'est pas un répertoire" "$racine/o1" && echo "FICHIER_NOMME=OUI" || echo "FICHIER_NOMME=NON"

        # --- cas 2 : un SYMLINK .install-state vers un dossier EXTERNE précieux
        c2="$racine/c2"; ext="$racine/precieux"
        mkdir -p "$c2" "$ext"
        echo "DONNEES" > "$ext/data"
        ln -s "$ext" "$c2/.install-state"
        echo "residu" > "$c2/note.txt"
        s2=0
        ( source "$MODULE_10"; clean_target_directory "$c2" ) > "$racine/o2" 2>&1 || s2=$?
        echo "LIEN exit=$s2 reste=$(ls -A "$c2" | wc -l | tr -d ' ')"
        [ -f "$ext/data" ] && echo "CIBLE_DU_LIEN=INTACTE" || echo "CIBLE_DU_LIEN=DETRUITE"
        grep -q "lien symbolique" "$racine/o2" && echo "LIEN_NOMME=OUI" || echo "LIEN_NOMME=NON"
        grep -q "préservée" "$racine/o2" && echo "PRETEND_PRESERVEE=OUI" || echo "PRETEND_PRESERVEE=NON"

        rm -rf "$racine"
        BASH
        , [
            'MODULE_10' => ShellProbe::installModuleScript('10-laravel-core'),
        ], 60);

    expect($result['output'])->not->toContain('BAC_HORS_TMP');

    // Cas 1 : le fichier est traité comme une entrée ordinaire — donc compté,
    // donc supprimé, donc la cible est réellement vide pour composer.
    expect($result['output'])->toContain('FICHIER exit=0 reste=0');
    expect($result['output'])->toContain('FICHIER_NOMME=OUI');

    // Cas 2 : seul le LIEN part ; ce qu'il désignait est intact.
    expect($result['output'])->toContain('LIEN exit=0 reste=0');
    expect($result['output'])->toContain('CIBLE_DU_LIEN=INTACTE');
    expect($result['output'])->toContain('LIEN_NOMME=OUI');
    // ⛔ Et le journal ne prétend PAS avoir préservé une racine d'état qui
    // n'existe pas : une phrase fausse à côté d'un code juste reste une faute.
    expect($result['output'])->toContain('PRETEND_PRESERVEE=NON');
});

it('le module 10 refuse d’effacer les secrets d’un opérateur', function (): void {
    // ⚖️ Élargissement délibéré des marqueurs au-delà de composer.json/vendor/.
    // Un `vendor/` se réinstalle ; un `.env` — clé d'application, identifiants
    // de base, secrets d'API — ne se retrouve pas.
    $result = ShellProbe::run(nettoyageSousSonde(<<<'BASH'
        printf 'APP_KEY=base64:secret-de-loperateur\nDB_PASSWORD=hunter2\n' > "$cible/.env"
        BASH), [
        'MODULE_10' => ShellProbe::installModuleScript('10-laravel-core'),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=1$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toContain('Refus de nettoyer');
    expect($result['output'])->toContain('.env');
    // Rien n'a été supprimé : le fichier de secrets est toujours là.
    expect($result['output'])->toMatch('/^RESTANTS=1$/m');
    expect($result['output'])->toMatch('/^ETAT=3$/m');
});

it('le module 10 REFUSE bruyamment de nettoyer une installation partielle', function (): void {
    $result = ShellProbe::run(nettoyageSousSonde(<<<'BASH'
        # L'état EXACT d'un `composer create-project` interrompu : composer.json
        # écrit, vendor/ à moitié rempli, mais pas les 4 fichiers que
        # `is_laravel_installed` exige. C'est précisément là que le `find -delete`
        # inconditionnel frappait.
        echo '{"name":"laravel/laravel"}' > "$cible/composer.json"
        mkdir -p "$cible/vendor/composer"
        echo "travail-en-cours" > "$cible/vendor/temoin.txt"
        BASH), [
        'MODULE_10' => ShellProbe::installModuleScript('10-laravel-core'),
    ], 60);

    // ⛔ Rouge à observer : rétablir le nettoyage inconditionnel fait passer
    // STATUS à 0 et RESTANTS à 0 — les deux assertions rougissent.
    expect($result['output'])->toMatch('/^STATUS=1$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    // 4 entrées : composer.json, vendor/, vendor/composer/, vendor/temoin.txt.
    // Le décompte est RÉCURSIF depuis la revue 1 — un `ls -A` nu ne voyait pas
    // qu'un sous-arbre avait été vidé de l'intérieur.
    expect($result['output'])->toMatch('/^RESTANTS=4$/m');
    // La racine d'état n'est jamais un marqueur d'install partielle, et elle
    // survit au refus comme au nettoyage.
    expect($result['output'])->toMatch('/^ETAT=3$/m');
    expect($result['output'])->toContain('Refus de nettoyer');
    // Le refus NOMME ce qui a été trouvé, sinon l'opérateur ne sait pas quoi
    // regarder avant d'employer --force.
    expect($result['output'])->toContain('composer.json');
    expect($result['output'])->toContain('vendor/');
    // ⚠️ Le refus nomme LES DEUX sorties. La rédaction précédente ne citait que
    // `--force` — faux quand le module est lancé seul, puisqu'il n'a pas ce
    // drapeau : l'opérateur suivait alors une consigne inapplicable.
    expect($result['output'])->toContain('--force');
    expect($result['output'])->toContain('INSTALL_FORCE=true');
    expect($result['output'])->toContain('vider le répertoire à la main');
});

it('le module 10 nettoie encore un répertoire qui n’est PAS une install partielle', function (): void {
    $result = ShellProbe::run(nettoyageSousSonde(<<<'BASH'
        # Ni composer.json ni vendor/ : rien à sauver, le comportement d'origine
        # est conservé. Un refus ici bloquerait toute première installation sur
        # un répertoire simplement encombré.
        echo "residu" > "$cible/note.txt"
        BASH), [
        'MODULE_10' => ShellProbe::installModuleScript('10-laravel-core'),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=0$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toMatch('/^RESTANTS=0$/m');
    expect($result['output'])->not->toContain('Refus de nettoyer');
});

it('le module 10 accepte de nettoyer une install partielle sous --force', function (): void {
    $result = ShellProbe::run(nettoyageSousSonde(<<<'BASH'
        echo '{"name":"laravel/laravel"}' > "$cible/composer.json"
        mkdir -p "$cible/vendor"
        BASH
        , 'export INSTALL_FORCE=true'), [
            'MODULE_10' => ShellProbe::installModuleScript('10-laravel-core'),
        ], 60);

    // La sortie que le refus annonce doit exister : un message qui nomme
    // `--force` sans que `--force` ne débloque rien serait un cul-de-sac.
    expect($result['output'])->toMatch('/^STATUS=0$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toMatch('/^RESTANTS=0$/m');
    // ⚖️ La sortie s'annonce par son NOM RÉEL. Ce module s'exécute aussi seul
    // (`install.sh --only 10-laravel-core` le lance en sous-processus, et un
    // opérateur peut l'appeler à la main) : il n'a alors aucun drapeau
    // `--force` à offrir, seulement la variable d'environnement. Le journal
    // nomme donc `INSTALL_FORCE`, pas un drapeau que ce module ne lit pas.
    expect($result['output'])->toContain('INSTALL_FORCE : nettoyage autorisé');
    expect($result['output'])->not->toContain('Refus de nettoyer');
});

it('un répertoire cible vraiment vide reste le cas nominal', function (): void {
    $result = ShellProbe::run(nettoyageSousSonde('# rien à préparer : la cible est vide'), [
        'MODULE_10' => ShellProbe::installModuleScript('10-laravel-core'),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=0$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toMatch('/^RESTANTS=0$/m');
});

// =============================================================================
// Lockfile — script HÔTE, docker STUBBÉ
// =============================================================================

/**
 * Bac à sable du lockfile : une fausse arborescence applicative et un `docker`
 * de substitution dans un PATH reconstruit.
 *
 * `$phpStub` / `$nodeStub` sont les corps de branche du stub : c'est en les
 * changeant qu'on éprouve « conteneur absent » sans arrêter un vrai conteneur.
 */
function lockfileSousSonde(string $phpStub, string $nodeStub): string
{
    return <<<BASH
        set -e
        bac="\$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "\$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
        esac
        mkdir -p "\$bac/bin" "\$bac/app/.install-state"

        echo "2026-08-22T09:00:00Z" > "\$bac/app/.install-state/started-at"
        printf 'CONTENU-DE-COMPOSER-LOCK\\n' > "\$bac/app/composer.lock"
        # Pendant Node de composer.lock : le lockfile l'empreinte depuis la
        # revue 1 — il argumentait tout entier sur Node sans jamais empreinter
        # ce que Node avait installé.
        printf 'CONTENU-DE-PACKAGE-LOCK\\n' > "\$bac/app/package-lock.json"

        cat > "\$bac/bin/docker" <<'STUB'
        #!/bin/bash
        # argv attendu : exec <conteneur> <commande…>
        sous_commande="\$1"
        conteneur="\$2"
        shift 2 || true

        if [ "\$sous_commande" != "exec" ]; then
            echo "stub docker : sous-commande inattendue « \$sous_commande »" >&2
            exit 125
        fi

        case "\$conteneur" in
            *_php)
                {$phpStub}
                ;;
            *_node)
                {$nodeStub}
                ;;
        esac

        echo "Error: No such container: \$conteneur" >&2
        exit 1
        STUB
        chmod +x "\$bac/bin/docker"

        export APP_DIR="\$bac/app"
        export INSTALL_STATE_DIR="\$bac/app/.install-state"
        export LOG_FILE="\$bac/lockfile.log"

        status=0
        PATH="\$bac/bin:\$PATH" bash "\$LOCKFILE_SH" > "\$bac/sortie" 2>&1 || status=\$?

        echo "STATUS=\$status"
        echo "SHA_ATTENDU=\$(sha256sum "\$bac/app/composer.lock" | cut -d' ' -f1)"
        echo "SHA_NPM_ATTENDU=\$(sha256sum "\$bac/app/package-lock.json" | cut -d' ' -f1)"

        if [ -f "\$bac/app/.install-state/lock.yml" ]; then
            echo "LOCK=PRESENT"
            echo "MODE=\$(stat -c '%a' "\$bac/app/.install-state/lock.yml")"
            sed 's/^/LOCK> /' "\$bac/app/.install-state/lock.yml"
        else
            echo "LOCK=ABSENT"
        fi

        sed 's/^/SORTIE> /' "\$bac/sortie"

        rm -rf "\$bac"
        BASH;
}

it('le lockfile enregistre l’empreinte, les deux versions et la fenêtre d’install', function (): void {
    $result = ShellProbe::run(lockfileSousSonde(
        // Le conteneur php répond pour PHP…
        'if [ "$1" = "php" ]; then echo -n "8.5.7"; exit 0; fi',
        // …et le conteneur NODE pour node. Volontairement DIFFÉRENT du node
        // qu'un conteneur php porterait : c'est tout l'enjeu de l'arbitrage.
        'if [ "$1" = "node" ]; then echo "v24.19.0"; exit 0; fi',
    ), [
        'LOCKFILE_SH' => ShellProbe::lockfileScript(),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=0$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toContain('LOCK=PRESENT');

    // sha256 de `src/composer.lock`, comparé à un calcul INDÉPENDANT — écrire
    // le hash en dur ferait passer un script qui recopierait n'importe quoi.
    $sha = [];

    if (preg_match('/SHA_ATTENDU=([0-9a-f]{64})/', $result['output'], $sha) !== 1) {
        // Levée plutôt qu'assertion : sans empreinte de référence, la
        // comparaison ci-dessous n'aurait plus rien à comparer et passerait
        // sur une chaîne vide.
        throw new RuntimeException("Empreinte de référence absente de la sonde :\n" . $result['output']);
    }

    expect($result['output'])->toContain('LOCK> composer_lock_sha256: "' . $sha[1] . '"');

    $shaNpm = [];

    if (preg_match('/SHA_NPM_ATTENDU=([0-9a-f]{64})/', $result['output'], $shaNpm) !== 1) {
        throw new RuntimeException("Empreinte npm de référence absente :\n" . $result['output']);
    }

    // ⚖️ Le pendant Node de `composer.lock` : sans lui, le lockfile argumentait
    // tout entier sur Node sans empreinter ce que Node avait installé.
    expect($result['output'])->toContain('LOCK> package_lock_sha256: "' . $shaNpm[1] . '"');

    expect($result['output'])->toContain('LOCK> php_version: "8.5.7"');
    // ⚖️ La version du conteneur NODE, celui qui produit node_modules/.
    expect($result['output'])->toContain('LOCK> node_version: "24.19.0"');
    expect($result['output'])->toContain('LOCK> node_source_container: "laravel-app_node"');

    // La fenêtre : `started_at` vient du marqueur posé par l'installeur,
    // `finished_at` de l'exécution du lockfile.
    expect($result['output'])->toContain('LOCK> started_at: "2026-08-22T09:00:00Z"');
    expect($result['output'])->toMatch('/LOCK> finished_at: "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"/');
});

it('le refus du lockfile TUE le processus, malgré la substitution de commande', function (): void {
    // 🔴 UN COMMENTAIRE DE CE FICHIER DISAIT UNE CHOSE FAUSSE (corrigé, revue 1).
    // Il affirmait que `die` y « est appelé en dehors de toute substitution ».
    // C'est l'inverse : `container_output` n'est JAMAIS appelée autrement qu'en
    // substitution, donc `die` n'y tue que le sous-shell.
    //
    // CE QUI SAUVE LE CAS EST FRAGILE, et ce test le rend explicite :
    //   1. l'idiome en DEUX lignes — `local x` puis `x="$(…)"` — car une
    //      affectation simple propage le code de retour de la substitution,
    //      là où `local x="$(…)"` le MASQUE (le code devient celui de `local`) ;
    //   2. `set -e`, qui transforme ce code non nul en arrêt du script.
    //
    // La mutation qui le prouve : condenser en `local x="$(container_output …)"`
    // fait poursuivre l'exécution avec la BANNIÈRE FATALE comme valeur — et un
    // lock.yml portant « php_version: "…ERREUR FATALE…" » serait publié.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        depot="$(dirname "$LOCKFILE_SH")"

        # On éprouve les DEUX idiomes sur la vraie fonction, sans toucher au
        # script : c'est le mécanisme qui est sous test, pas une copie.
        sonde() {
            local forme="$1"
            local bac
            bac="$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
            printf '#!/bin/bash\nexit 1\n' > "$bac/docker"
            chmod +x "$bac/docker"

            {
                echo 'set -e'
                echo "source '$depot/lib/logging.sh'"
                echo "source '$depot/lib/runtime.sh'"
                echo 'DOCKER_BIN=docker'
                # La fonction, recopiée depuis le script sous test.
                sed -n '/^container_output() {/,/^}/p' "$LOCKFILE_SH"
                if [ "$forme" = "deux-lignes" ]; then
                    echo 'local_v=""; local_v="$(container_output absent-2-2 node -v)"'
                else
                    # L'idiome condamné, dans une fonction pour que `local`
                    # soit légal — c'est exactement la forme qui masque.
                    echo 'f() { local v="$(container_output absent-2-2 node -v)"; echo "POURSUIT=[$v]"; }'
                    echo 'f'
                fi
                echo 'echo "APRES=ATTEINT"'
            } > "$bac/sonde.sh"

            local status=0
            PATH="$bac:$PATH" LOG_FILE="$bac/log" bash "$bac/sonde.sh" > "$bac/out" 2>&1 || status=$?
            echo "${forme}_STATUS=$status"
            grep -q "APRES=ATTEINT" "$bac/out" && echo "${forme}_APRES=ATTEINT" || echo "${forme}_APRES=COUPE"
            rm -rf "$bac"
        }

        sonde "deux-lignes"
        sonde "condense"
        BASH
        , [
            'LOCKFILE_SH' => ShellProbe::lockfileScript(),
        ], 60);

    // L'idiome employé par le script : le refus coupe l'exécution.
    expect($result['output'])->toMatch('/^deux-lignes_STATUS=1$/m');
    expect($result['output'])->toContain('deux-lignes_APRES=COUPE');

    // ⛔ Et la démonstration que l'idiome est PORTEUR, pas décoratif : condensé,
    // le même code POURSUIT après un refus fatal. C'est ce que le commentaire
    // faux laissait croire impossible.
    expect($result['output'])->toContain('condense_APRES=ATTEINT');
});

it('le lockfile REFUSE une version qui n’en est pas une', function (): void {
    // 🔴 `container_output` FUSIONNE stderr DANS LA VALEUR (`2>&1`) — délibéré,
    // c'est ce qui permet de citer le message de docker dans le refus. Non vu
    // au premier jet : un conteneur qui émet un avertissement sur la même
    // sortie, tout en rendant 0, fait entrer cette phrase dans le lockfile
    // COMME VERSION. Le fichier est relu comme une MESURE par la story 2.4 ;
    // « Warning: something » y serait une version de Node.
    $result = ShellProbe::run(lockfileSousSonde(
        'if [ "$1" = "php" ]; then echo -n "8.5.7"; exit 0; fi',
        // Un avertissement précède la version, et la commande réussit.
        'if [ "$1" = "node" ]; then echo "Warning: locale non configurée"; echo "v24.19.0"; exit 0; fi',
    ), [
        'LOCKFILE_SH' => ShellProbe::lockfileScript(),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=1$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    // ⛔ RIEN n'est écrit : ni la version douteuse, ni un repli.
    expect($result['output'])->toContain('LOCK=ABSENT');
    expect($result['output'])->toContain('version inattendue');
});

/**
 * Bac à sable du lockfile avec un `sha256sum` de substitution.
 *
 * `$stub` est le corps du faux binaire : c'est en le changeant qu'on éprouve
 * les deux moitiés indépendantes de `file_sha256` — le STATUT (l'outil échoue)
 * et le FORMAT (l'outil réussit mais rend autre chose qu'une empreinte).
 * Séparées, parce qu'ensemble elles se masquent : chacune rattrape l'autre.
 */
function sha256SousSonde(string $stub): string
{
    return <<<BASH
        set -e
        bac="\$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "\$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
        esac
        mkdir -p "\$bac/app/.install-state" "\$bac/bin"
        echo "2026-08-22T09:00:00Z" > "\$bac/app/.install-state/started-at"
        printf 'C\\n' > "\$bac/app/composer.lock"
        printf 'N\\n' > "\$bac/app/package-lock.json"

        printf '#!/bin/bash\\nif [ "\$3" = "php" ]; then printf 8.5.7; else echo v24.19.0; fi\\n' > "\$bac/bin/docker"
        chmod +x "\$bac/bin/docker"

        cat > "\$bac/bin/sha256sum" <<'STUB'
        #!/bin/bash
        {$stub}
        STUB
        chmod +x "\$bac/bin/sha256sum"

        export APP_DIR="\$bac/app"
        export INSTALL_STATE_DIR="\$bac/app/.install-state"
        export LOG_FILE="\$bac/lockfile.log"

        status=0
        PATH="\$bac/bin:\$PATH" bash "\$LOCKFILE_SH" > "\$bac/sortie" 2>&1 || status=\$?

        echo "STATUS=\$status"
        [ -f "\$bac/app/.install-state/lock.yml" ] && echo "LOCK=PRESENT" || echo "LOCK=ABSENT"
        if [ -f "\$bac/app/.install-state/lock.yml" ]; then
            sed 's/^/LOCK> /' "\$bac/app/.install-state/lock.yml"
        fi
        sed 's/^/SORTIE> /' "\$bac/sortie"

        rm -rf "\$bac"
        BASH;
}

it('le lockfile ÉCHOUE quand sha256sum échoue, même s’il imprime une empreinte', function (): void {
    // 🔴 LE STATUT ÉTAIT MASQUÉ PAR `cut` : `sha256sum X | cut -d' ' -f1` rend
    // le code de `cut`, soit 0 quoi qu'il arrive. Un outil qui échoue en
    // imprimant quand même quelque chose de plausible — droits, FS en défaut,
    // implémentation exotique — faisait entrer une empreinte FAUSSE dans le
    // lockfile, sous un exit 0.
    //
    // Le stub imprime une empreinte PARFAITEMENT bien formée : seul le statut
    // le trahit. C'est ce qui rend ce test indépendant du contrôle de format
    // ci-dessous — sans quoi les deux gardes se masqueraient l'un l'autre.
    $result = ShellProbe::run(sha256SousSonde(
        'echo "' . str_repeat('a', 64) . '  $1"' . "\n" . 'exit 3',
    ), [
        'LOCKFILE_SH' => ShellProbe::lockfileScript(),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=1$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toContain('LOCK=ABSENT');
    expect($result['output'])->toContain('illisible');
    // ⛔ Et surtout : l'empreinte plausible du stub n'est écrite NULLE PART.
    expect($result['output'])->not->toContain(str_repeat('a', 64));
});

it('le lockfile ÉCHOUE quand sha256sum réussit mais ne rend pas une empreinte', function (): void {
    // L'autre moitié, indépendante : l'outil rend 0 et imprime autre chose
    // qu'une empreinte — un avertissement en tête, un format BusyBox, une
    // locale bavarde. Sans validation, cette phrase devient
    // `composer_lock_sha256:` dans un fichier relu comme une MESURE.
    $result = ShellProbe::run(sha256SousSonde(
        'echo "sha256sum: attention, entree lue depuis stdin"' . "\n" . 'exit 0',
    ), [
        'LOCKFILE_SH' => ShellProbe::lockfileScript(),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=1$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toContain('LOCK=ABSENT');
    expect($result['output'])->toContain('empreinte sha256 inattendue');
});

it('le lockfile publie un fichier COMPLET, même si le nom du conteneur porte des métacaractères', function (): void {
    // 🔴 DÉFAUT LATENT TROUVÉ EN ÉPROUVANT L'ÉCRITURE ATOMIQUE (revue 1).
    // La post-condition employait `grep` — donc un moteur d'EXPRESSIONS
    // RÉGULIÈRES — sur un nom de conteneur dérivé de `COMPOSE_PROJECT_NAME`.
    // Mesuré : `projet[1]_node` suffisait à ce que le motif ne corresponde plus
    // à sa propre sortie ; le script refusait alors un fichier PARFAITEMENT
    // écrit en annonçant une « écriture partielle » qui n'avait pas eu lieu.
    // Un diagnostic faux coûte plus cher qu'aucun diagnostic.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
        mkdir -p "$bac/app/.install-state" "$bac/bin"
        echo "2026-08-22T09:00:00Z" > "$bac/app/.install-state/started-at"
        printf 'C\n' > "$bac/app/composer.lock"
        printf 'N\n' > "$bac/app/package-lock.json"
        printf '#!/bin/bash\nif [ "$3" = "php" ]; then printf 8.5.7; else echo v24.19.0; fi\n' > "$bac/bin/docker"
        chmod +x "$bac/bin/docker"

        export APP_DIR="$bac/app"
        export INSTALL_STATE_DIR="$bac/app/.install-state"
        export LOG_FILE="$bac/lockfile.log"
        # Un nom de projet parfaitement légal côté Docker, et un champ de mines
        # pour un motif regex.
        export NODE_CONTAINER_NAME='projet[1].node'

        status=0
        PATH="$bac/bin:$PATH" bash "$LOCKFILE_SH" > "$bac/sortie" 2>&1 || status=$?
        echo "STATUS=$status"
        [ -f "$bac/app/.install-state/lock.yml" ] && echo "LOCK=PRESENT" || echo "LOCK=ABSENT"
        echo "DERNIERE=[$(tail -n 1 "$bac/app/.install-state/lock.yml" 2>/dev/null)]"
        # Aucun temporaire abandonné après un succès.
        echo "TEMPORAIRES=$(find "$bac/app/.install-state" -name '.lock.yml.*' 2>/dev/null | wc -l | tr -d ' ')"
        sed 's/^/SORTIE> /' "$bac/sortie"

        rm -rf "$bac"
        BASH
        , [
            'LOCKFILE_SH' => ShellProbe::lockfileScript(),
        ], 60);

    expect($result['output'])->toMatch('/^STATUS=0$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toContain('LOCK=PRESENT');
    // Le fichier est complet : sa dernière ligne est bien la dernière attendue.
    expect($result['output'])->toContain('DERNIERE=[node_source_container: "projet[1].node"]');
    expect($result['output'])->toContain('TEMPORAIRES=0');
    expect($result['output'])->not->toContain('écrit partiellement');
});

it('le lockfile ÉCHOUE quand package-lock.json manque', function (): void {
    // Le pendant Node de `composer.lock`. Ce script argumente tout entier sur
    // Node — quel conteneur, quelle version, pourquoi celle-là — et
    // n'empreintait pourtant que les dépendances PHP : il était incapable de
    // dire si `node_modules/` correspond à ce que le dépôt déclare.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
        mkdir -p "$bac/app/.install-state" "$bac/bin"
        echo "2026-08-22T09:00:00Z" > "$bac/app/.install-state/started-at"
        printf 'CONTENU-DE-COMPOSER-LOCK\n' > "$bac/app/composer.lock"
        # Pas de package-lock.json.

        printf '#!/bin/bash\necho 1.2.3\n' > "$bac/bin/docker"
        chmod +x "$bac/bin/docker"

        export APP_DIR="$bac/app"
        export INSTALL_STATE_DIR="$bac/app/.install-state"
        export LOG_FILE="$bac/lockfile.log"

        status=0
        PATH="$bac/bin:$PATH" bash "$LOCKFILE_SH" > "$bac/sortie" 2>&1 || status=$?
        echo "STATUS=$status"
        [ -f "$bac/app/.install-state/lock.yml" ] && echo "LOCK=PRESENT" || echo "LOCK=ABSENT"
        sed 's/^/SORTIE> /' "$bac/sortie"

        rm -rf "$bac"
        BASH
        , [
            'LOCKFILE_SH' => ShellProbe::lockfileScript(),
        ], 60);

    expect($result['output'])->toMatch('/^STATUS=1$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toContain('LOCK=ABSENT');
    expect($result['output'])->toContain('package-lock.json introuvable');
});

it('le lockfile MEURT EN NOMMANT la racine d’état qu’il ne peut pas créer', function (): void {
    // 🔴 L'en-tête du script promet qu'il « MEURT en nommant ce qui manque »
    // (E4, revue 2). Le `mkdir -p` de la racine d'état échouait pourtant sous
    // `set -e` NU : mort silencieuse, sans `die`, sans nommer le chemin. Le
    // script sortait bien ≠ 0 — donc aucun test ne le voyait — mais l'opérateur
    // n'avait aucune idée de ce qu'il devait réparer.
    //
    // ⚠️ Le test précédent rend la racine d'état INÉCRIVABLE ; celui-ci la rend
    // INCRÉABLE (un sous-répertoire sous un parent en lecture seule). Ce sont
    // deux chemins de code distincts, et seul le second passe par `mkdir`.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in /tmp/*) ;; *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;; esac
        mkdir -p "$bac/app" "$bac/bin" "$bac/verrou"
        printf 'C\n' > "$bac/app/composer.lock"
        printf 'N\n' > "$bac/app/package-lock.json"

        # Le marqueur vit ailleurs, dans un endroit lisible : ce test doit
        # mesurer l'échec du `mkdir`, pas l'absence d'horodatage.
        mkdir -p "$bac/marqueur"
        echo "2026-08-22T09:00:00Z" > "$bac/marqueur/started-at"

        printf '#!/bin/bash\nif [ "$3" = "php" ]; then printf 8.5.7; else echo v24.19.0; fi\n' > "$bac/bin/docker"
        chmod +x "$bac/bin/docker"

        chmod a-w "$bac/verrou"

        export APP_DIR="$bac/app"
        export STARTED_AT_MARKER="$bac/marqueur/started-at"
        # Racine d'état INCRÉABLE : un sous-répertoire d'un parent en lecture seule.
        export INSTALL_STATE_DIR="$bac/verrou/impossible"
        export LOCKFILE="$bac/verrou/impossible/lock.yml"
        export LOG_FILE="$bac/lockfile.log"

        status=0
        PATH="$bac/bin:$PATH" bash "$LOCKFILE_SH" > "$bac/sortie" 2>&1 || status=$?

        echo "STATUS=$status"
        [ -f "$LOCKFILE" ] && echo "LOCK=PRESENT" || echo "LOCK=ABSENT"
        grep -q "Racine d'état impossible à créer" "$bac/sortie" \
            && echo "DIAGNOSTIC=OUI" || echo "DIAGNOSTIC=NON"
        grep -q "$bac/verrou/impossible" "$bac/sortie" \
            && echo "CHEMIN_NOMME=OUI" || echo "CHEMIN_NOMME=NON"

        chmod u+w "$bac/verrou"
        rm -rf "$bac"
        BASH
        , [
            'LOCKFILE_SH' => ShellProbe::lockfileScript(),
        ], 60);

    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toMatch('/^STATUS=1$/m');
    expect($result['output'])->toContain('LOCK=ABSENT');
    // ⛔ Ce que la prose promettait et que le code ne faisait pas : nommer.
    expect($result['output'])->toContain('DIAGNOSTIC=OUI');
    expect($result['output'])->toContain('CHEMIN_NOMME=OUI');
});

it('le lockfile REFUSE un horodatage de début qui n’est pas une date', function (): void {
    // `started_at` était le SEUL champ du lockfile écrit sans validation de
    // format (revue 2), alors que les versions et les empreintes en ont une.
    // Ce fichier est relu comme une MESURE par la story 2.4 : un marqueur
    // corrompu — édité à la main, tronqué, écrit par une autre version de
    // l'installeur — y deviendrait une fenêtre d'installation, sous exit 0.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in /tmp/*) ;; *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;; esac
        mkdir -p "$bac/app/.install-state" "$bac/bin"
        printf 'C\n' > "$bac/app/composer.lock"
        printf 'N\n' > "$bac/app/package-lock.json"
        printf '#!/bin/bash\nif [ "$3" = "php" ]; then printf 8.5.7; else echo v24.19.0; fi\n' > "$bac/bin/docker"
        chmod +x "$bac/bin/docker"

        # Non vide — donc la garde « vide » ne peut pas l'attraper — mais pas
        # une date pour autant.
        echo "hier-vers-midi" > "$bac/app/.install-state/started-at"

        export APP_DIR="$bac/app"
        export INSTALL_STATE_DIR="$bac/app/.install-state"
        export LOG_FILE="$bac/lockfile.log"

        status=0
        PATH="$bac/bin:$PATH" bash "$LOCKFILE_SH" > "$bac/sortie" 2>&1 || status=$?
        echo "STATUS=$status"
        [ -f "$bac/app/.install-state/lock.yml" ] && echo "LOCK=PRESENT" || echo "LOCK=ABSENT"
        grep -q "Horodatage de début invalide" "$bac/sortie" \
            && echo "DIAGNOSTIC=OUI" || echo "DIAGNOSTIC=NON"

        rm -rf "$bac"
        BASH
        , [
            'LOCKFILE_SH' => ShellProbe::lockfileScript(),
        ], 60);

    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toMatch('/^STATUS=1$/m');
    expect($result['output'])->toContain('LOCK=ABSENT');
    expect($result['output'])->toContain('DIAGNOSTIC=OUI');
});

it('le lockfile est publié LISIBLE (0644), pas en 0600 par accident de mktemp', function (): void {
    // ⚖️ EFFET DE BORD TRANCHÉ ET ÉCRIT (revue 2). `mktemp` crée en 0600 et
    // `mv` conserve le mode : le lockfile était publié illisible par tout autre
    // uid — or il vit dans `src/`, relu depuis les conteneurs php et node, sous
    // des uid qui ne sont pas nécessairement celui qui a lancé `make`.
    // Décision : 0644. Le fichier ne porte AUCUN secret (deux empreintes
    // publiques, deux versions, deux horodatages) et sa raison d'être est
    // d'être relu.
    $result = ShellProbe::run(lockfileSousSonde(
        'if [ "$1" = "php" ]; then echo -n "8.5.7"; exit 0; fi',
        'if [ "$1" = "node" ]; then echo "v24.19.0"; exit 0; fi',
    ), [
        'LOCKFILE_SH' => ShellProbe::lockfileScript(),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=0$/m');
    expect($result['output'])->toContain('LOCK=PRESENT');
    expect($result['output'])->toMatch('/^MODE=644$/m');
});

it('le lockfile ne publie RIEN quand l’écriture est impossible', function (): void {
    // ⛔ L'écriture est ATOMIQUE (temporaire + `mv`). Le contrôle `[ -f ]` qui
    // tenait lieu de post-condition est VRAI sur un fichier tronqué : un disque
    // plein laissait un lock.yml à moitié écrit que le script déclarait
    // « écrit ». Ici la racine d'état est en lecture seule — le temporaire ne
    // peut pas naître, donc aucun lock.yml ne peut apparaître, même partiel.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
        mkdir -p "$bac/app/.install-state" "$bac/bin"
        echo "2026-08-22T09:00:00Z" > "$bac/app/.install-state/started-at"
        printf 'C\n' > "$bac/app/composer.lock"
        printf 'N\n' > "$bac/app/package-lock.json"

        printf '#!/bin/bash\nif [ "$3" = "php" ]; then printf 8.5.7; else echo v24.19.0; fi\n' > "$bac/bin/docker"
        chmod +x "$bac/bin/docker"

        chmod a-w "$bac/app/.install-state"

        export APP_DIR="$bac/app"
        export INSTALL_STATE_DIR="$bac/app/.install-state"
        export LOG_FILE="$bac/lockfile.log"

        status=0
        PATH="$bac/bin:$PATH" bash "$LOCKFILE_SH" > "$bac/sortie" 2>&1 || status=$?
        echo "STATUS=$status"
        [ -f "$bac/app/.install-state/lock.yml" ] && echo "LOCK=PRESENT" || echo "LOCK=ABSENT"
        # Aucun temporaire abandonné : le trap nettoie.
        echo "TEMPORAIRES=$(find "$bac/app/.install-state" -name '.lock.yml.*' 2>/dev/null | wc -l | tr -d ' ')"
        sed 's/^/SORTIE> /' "$bac/sortie"

        chmod u+w "$bac/app/.install-state"
        rm -rf "$bac"
        BASH
        , [
            'LOCKFILE_SH' => ShellProbe::lockfileScript(),
        ], 60);

    expect($result['output'])->toMatch('/^STATUS=1$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toContain('LOCK=ABSENT');
    expect($result['output'])->toContain('TEMPORAIRES=0');
});

it('le lockfile ÉCHOUE en nommant le conteneur node absent, sans valeur de repli', function (): void {
    $result = ShellProbe::run(lockfileSousSonde(
        'if [ "$1" = "php" ]; then echo -n "8.5.7"; exit 0; fi',
        // Le conteneur node ne répond pas : `docker exec` tombe dans le cas
        // par défaut du stub, exactement comme un conteneur arrêté.
        ':',
    ), [
        'LOCKFILE_SH' => ShellProbe::lockfileScript(),
    ], 60);

    expect($result['output'])->toMatch('/^STATUS=1$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    // ⛔ Le point le plus important : RIEN n'est écrit. Un lock.yml portant
    // « node_version: unknown » serait relu comme une mesure par la story 2.4.
    expect($result['output'])->toContain('LOCK=ABSENT');
    expect($result['output'])->toContain('laravel-app_node');
    expect($result['output'])->toContain('injoignable');
});

it('le lockfile ÉCHOUE quand l’horodatage de début manque', function (): void {
    // 🔴 TROUVAILLE DE LA CAMPAGNE DE MUTATION (M13, 2026-08-22) : cette branche
    // n'était gardée par RIEN. Rendre `started_at` un « 1970-01-01T00:00:00Z »
    // de repli laissait les 17 tests verts — et écrivait dans lock.yml une
    // fenêtre d'installation entièrement fausse, que la story 2.4 relirait
    // comme une mesure contre la promesse « install < 15 min ».
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
        mkdir -p "$bac/app/.install-state" "$bac/bin"
        printf 'CONTENU-DE-COMPOSER-LOCK\n' > "$bac/app/composer.lock"
        printf 'CONTENU-DE-PACKAGE-LOCK\n' > "$bac/app/package-lock.json"
        # Aucun marqueur `started-at` : l'installeur n'a jamais tourné ici.

        # `docker` répond à tout : ce test doit mesurer l'absence d'horodatage,
        # pas l'absence de docker.
        printf '#!/bin/bash\necho 0.0.0\n' > "$bac/bin/docker"
        chmod +x "$bac/bin/docker"

        export APP_DIR="$bac/app"
        export INSTALL_STATE_DIR="$bac/app/.install-state"
        export LOG_FILE="$bac/lockfile.log"

        status=0
        PATH="$bac/bin:$PATH" bash "$LOCKFILE_SH" > "$bac/sortie" 2>&1 || status=$?
        echo "STATUS=$status"
        [ -f "$bac/app/.install-state/lock.yml" ] && echo "LOCK=PRESENT" || echo "LOCK=ABSENT"
        sed 's/^/SORTIE> /' "$bac/sortie"

        rm -rf "$bac"
        BASH
        , [
            'LOCKFILE_SH' => ShellProbe::lockfileScript(),
        ], 60);

    expect($result['output'])->toMatch('/^STATUS=1$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toContain('LOCK=ABSENT');
    expect($result['output'])->toContain('Horodatage de début introuvable');
    // Le refus nomme le fichier ET la commande qui répare.
    expect($result['output'])->toContain('started-at');
    expect($result['output'])->toContain('make install-laravel');
});

it('le lockfile ÉCHOUE quand composer.lock manque', function (): void {
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ.
        # Constaté le 2026-08-22 : une interpolation ratée dans un helper a fait
        # collapser le chemin du bac, et la sonde a créé son arborescence DANS l'arbre
        # applicatif (`src/\\`) — le cwd que `ShellProbe` fixe. Un test qui
        # échoue est un incident ; un test qui salit le dépôt en échouant en est
        # deux. La garde coûte une ligne et rend le mode de défaillance bruyant.
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
        mkdir -p "$bac/app/.install-state" "$bac/bin"
        echo "2026-08-22T09:00:00Z" > "$bac/app/.install-state/started-at"
        printf 'CONTENU-DE-PACKAGE-LOCK\n' > "$bac/app/package-lock.json"

        # `docker` doit EXISTER, sinon `require_cmd` meurt en amont et ce test
        # mesurerait l'absence de docker au lieu de l'absence de composer.lock.
        printf '#!/bin/bash\nexit 0\n' > "$bac/bin/docker"
        chmod +x "$bac/bin/docker"

        export APP_DIR="$bac/app"
        export INSTALL_STATE_DIR="$bac/app/.install-state"
        export LOG_FILE="$bac/lockfile.log"

        status=0
        PATH="$bac/bin:$PATH" bash "$LOCKFILE_SH" > "$bac/sortie" 2>&1 || status=$?
        echo "STATUS=$status"
        [ -f "$bac/app/.install-state/lock.yml" ] && echo "LOCK=PRESENT" || echo "LOCK=ABSENT"
        sed 's/^/SORTIE> /' "$bac/sortie"

        rm -rf "$bac"
        BASH
        , [
            'LOCKFILE_SH' => ShellProbe::lockfileScript(),
        ], 60);

    expect($result['output'])->toMatch('/^STATUS=1$/m');
    // La sonde n'a pas quitté /tmp : sans cette assertion, un bac à sable
    // dont le chemin collapse écrit dans l'arbre applicatif sans le dire.
    expect($result['output'])->not->toContain('BAC_HORS_TMP');
    expect($result['output'])->toContain('LOCK=ABSENT');
    expect($result['output'])->toContain('composer.lock introuvable');
});

// =============================================================================
// Périphérie — ce qui doit être vrai pour que le reste serve à quelque chose
// =============================================================================

it('src/.gitignore ignore /.install-state, ANCRÉ', function (): void {
    $lignes = array_map(
        static fn (string $ligne): string => trim($ligne),
        explode("\n", RepoFile::read('src/.gitignore')),
    );

    // Ancré : `.install-state` sans `/` avalerait n'importe quel répertoire de
    // ce nom, à n'importe quelle profondeur. Ce fichier documente trois fois
    // cette faute ; c'est la quatrième occasion de ne pas la commettre.
    expect($lignes)
        ->toContain('/.install-state');
    expect($lignes)
        ->not->toContain('.install-state');
    expect($lignes)
        ->not->toContain('**/.install-state');
});

it('une install ne laisse RIEN de suivi derrière elle', function (): void {
    // Le delta de `git status --short` est vide parce que la règle est ancrée
    // ET que le chemin réellement écrit tombe dessous. Vérifié avec git, pas
    // par lecture du motif : c'est git qui arbitre, pas nous.
    $result = ShellProbe::run(<<<'BASH'
        # Le dépôt git vit à la RACINE, jamais dans `src/` : dans le conteneur,
        # `src/` est un montage séparé et `git` n'y trouve aucun `.git`.
        cd "$REPO_ROOT"
        for chemin in "src/.install-state/00-prerequisites-done" "src/.install-state/lock.yml" "src/.install-state/started-at"; do
            if git check-ignore -q "$chemin"; then
                echo "IGNORE=$chemin"
            else
                echo "SUIVI=$chemin"
            fi
        done
        BASH
        , [
            'REPO_ROOT' => ShellProbe::repoRoot(),
        ]);

    expect($result['output'])->toContain('IGNORE=src/.install-state/00-prerequisites-done');
    expect($result['output'])->toContain('IGNORE=src/.install-state/lock.yml');
    expect($result['output'])->toContain('IGNORE=src/.install-state/started-at');
    expect($result['output'])->not->toContain('SUIVI=');
});

it('SCRIPTS-REFERENCE.md nomme CHAQUE script présent sur disque', function (): void {
    // 🔴 L'ARITHMÉTIQUE ÉTAIT JUSTE, L'INVENTAIRE ÉTAIT FAUX (revue 2).
    // La revue 1 avait corrigé un total (27 → 28) et posé un encadré
    // « corrigé », ce qui augmente la confiance qu'on accorde au bloc. Mais
    // celui-ci prescrivait toujours d'archiver ou de supprimer SIX scripts qui
    // n'existent pas — avec fiche détaillée, taille au B près et
    // recommandation — et OMETTAIT trois scripts bien présents, dont
    // `assert-tracked-files.sh` et `quality-ratchet.sh`, les deux que le bloc
    // gelé de cette story inscrit en `Never: toucher` parce qu'ils sont
    // bloquants en CI.
    //
    // `ShellRuntimeLibTest` compte les scripts par répertoire ; il ne vérifie
    // pas qu'ils sont NOMMÉS. Un décompte juste sur une liste fausse se relit
    // comme vérifié — c'est le pire des deux mondes.
    $doc = RepoFile::read('docs/SCRIPTS-REFERENCE.md');
    $racine = ShellProbe::repoRoot() . '/scripts';

    $surDisque = [];

    foreach (['', 'install', 'lib', 'ops', 'security', 'setup'] as $sous) {
        $motif = $racine . ($sous === '' ? '' : '/' . $sous) . '/*.sh';

        foreach (glob($motif) ?: [] as $chemin) {
            $surDisque[] = basename($chemin);
        }
    }

    // Anti-vacuité : sur un `glob()` en échec, la boucle ci-dessous ne
    // comparerait rien et le test serait vert sur une doc vide.
    expect(count($surDisque))
        ->toBeGreaterThan(30);

    $absents = [];

    foreach ($surDisque as $script) {
        // Le fichier nomme certains scripts avec leur répertoire
        // (`ops/backup-local.sh`) : la recherche porte sur le nom de base, en
        // exigeant qu'il soit en évidence — entre accents graves ou en gras.
        if (! str_contains($doc, '`' . $script . '`')
            && ! str_contains($doc, '**' . $script . '**')
            && ! preg_match('/`[a-z0-9._-]*\/' . preg_quote($script, '/') . '`/i', $doc)) {
            $absents[] = $script;
        }
    }

    expect($absents)
        ->toBe([], 'Scripts présents sur disque mais absents de la doc : ' . implode(', ', $absents));

    // ⛔ Et le contre-sens : les six fiches fantômes ne doivent pas revenir.
    // Elles ne sont tolérées que dans l'encadré qui EXPLIQUE leur suppression,
    // jamais comme titre de section.
    foreach ([
        'backup-before-cleanup.sh',
        'validate-all-fixes.sh',
        'test-installation-complete.sh',
        'setup-auto-update.sh',
        'test-watchtower.sh',
        'create-gitkeep.sh',
    ] as $fantome) {
        expect(file_exists($racine . '/' . $fantome))->toBeFalse();
        expect($doc)
            ->not->toMatch('/^#+ .*' . preg_quote($fantome, '/') . '/mi');
    }
});

it('la CI se déclenche sur scripts/install.sh et scripts/install-lockfile.sh', function (): void {
    $workflow = RepoFile::yaml('.github/workflows/ci.yml');

    foreach (['push', 'pull_request'] as $evenement) {
        $paths = RepoFile::stringList($workflow, "on.{$evenement}.paths");

        // `scripts/install/**` NE COUVRE PAS `scripts/install.sh` : le premier
        // est un répertoire. Sans ces deux entrées, on peut casser
        // l'idempotence de l'installeur sans qu'aucun run ne démarre.
        expect($paths)
            ->toContain('scripts/install.sh');
        expect($paths)
            ->toContain('scripts/install-lockfile.sh');
        // Le Makefile est SUJET DE TEST depuis cette story : un test vérifie
        // l'ordre `npm-install` → `install-lockfile` et l'exclusion des chaînes
        // prod. Sans cette entrée, on casse la chaîne d'installation sans
        // qu'aucun run ne démarre — le défaut même que cette story corrige pour
        // `scripts/install.sh`, reconduit un cran plus loin.
        expect($paths)
            ->toContain('Makefile');
    }
});

it('le Makefile appelle install-lockfile après npm-install, et jamais en prod', function (): void {
    $makefile = RepoFile::read('Makefile');

    /** Ligne de prérequis d'une cible, sans son commentaire d'aide. */
    $prerequis = static function (string $cible) use ($makefile): string {
        $trouve = [];
        $motif = '/^' . preg_quote($cible, '/') . ':([^\n#]*)/m';

        expect(preg_match($motif, $makefile, $trouve))
            ->toBe(1, "Cible {$cible} absente du Makefile");

        return $trouve[1];
    };

    /** Position d'un prérequis dans la ligne — l'ordre est le sujet du test. */
    $position = static function (string $ligne, string $prerequisite): int {
        $offset = strpos($ligne, $prerequisite);

        expect($offset)
            ->not->toBeFalse("Prérequis {$prerequisite} absent de « {$ligne} »");

        return (int) $offset;
    };

    foreach (['install-dev', 'install-dev-full'] as $cible) {
        $ligne = $prerequis($cible);

        expect($ligne)
            ->toContain('install-lockfile');

        // L'ORDRE compte : `npm-install` produit le node_modules/ dont le
        // lockfile enregistre la version de node. Make honore les prérequis de
        // gauche à droite hors mode parallèle.
        expect($position($ligne, 'npm-install'))
            ->toBeLessThan($position($ligne, 'install-lockfile'));
    }

    $rapide = $prerequis('install-dev-fast');

    expect($rapide)
        ->toContain('install-lockfile');
    expect($position($rapide, 'npm-install-fast'))
        ->toBeLessThan($position($rapide, 'install-lockfile'));

    // ⛔ Exclusion ÉCRITE, pas subie : les chaînes prod ne jouent pas
    // `npm-install`, donc le conteneur node n'y tourne pas et le script
    // refuserait — correctement, mais en cassant une install prod valide.
    foreach (['install-prod', 'install-prod-fast'] as $cible) {
        expect($prerequis($cible))
            ->not->toContain('install-lockfile');
    }

    expect($makefile)
        ->toMatch('/^install-lockfile:.*##/m');
});
