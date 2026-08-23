<?php

declare(strict_types=1);

use Tests\Support\RepoFile;
use Tests\Support\ShellProbe;

/*
|--------------------------------------------------------------------------
| Simulation (--dry-run) et reprise (--resume-from) — Story 2.3
|--------------------------------------------------------------------------
|
| Suite Unit : aucun de ces tests ne boote Laravel. Ils lancent `bash` et
| lisent ce qu'il rend — seul véhicule capable de faire ROUGIR du shell tant
| que Bats n'est pas là (Story 2.4).
|
| ⛔ RÈGLE DE LA REVUE 1, ET ELLE COMMANDE TOUT CE FICHIER :
| **un AC de cette story se mesure sur un EFFET, jamais sur une propagation de
| drapeau.** `make -n` n'exécute rien — c'est précisément ce qui avait laissé
| passer, tous gardes au vert, une porte d'entrée `make` qui `chown -R` et
| `chmod -R` l'application de l'opérateur sous un drapeau nommé « dry-run ».
| Les sondes `make` de ce fichier LANCENT donc make pour de vrai, avec un `docker`
| et un `$(MAKE)` remplacés par des témoins, et mesurent la cible au `stat`.
| Les rares assertions sur des lignes de recette sont explicitement étiquetées
| comme telles et jamais seules.
|
| ⛔ AUCUNE INSTALLATION RÉELLE N'EST JOUÉE ICI. Chaque sonde travaille sur une
| COPIE de `scripts/` dans un bac à sable — la seule façon d'altérer un module
| sans toucher au dépôt, `SCRIPT_DIR` étant `readonly` et dérivé de
| l'emplacement du script — ou sur une cible jetable sous `/tmp`.
|
| ⚠️ LES EMPREINTES DE CIBLE INCLUENT LES MODES ET LE PROPRIÉTAIRE. Un
| `find | md5sum` ou un `mtime:size` ne voit PAS un `chmod` (qui ne touche que
| le ctime) : le test qui s'appelait « ne chmode pas la cible » n'inspectait
| aucun mode.
|
*/

/**
 * Prélude : bac à sable jetable, racine d'état INJECTÉE, orchestrateur SOURCÉ
 * avec `execute_module` remplacé par un journal.
 *
 * ⚠️ LE NOM NE PARLE PAS DE SIMULATION, ET C'EST VOULU. Une rédaction
 * précédente l'appelait `orchestrateurEnSimulation` alors qu'elle ne pose
 * jamais `DRY_RUN=true` — le nom promettait ce que le corps ne faisait pas.
 * Ce prélude sert à observer la BOUCLE (ordre, `--only`, `--resume-from`,
 * sentinelles) avec un `execute_module` neutralisé ; les tests bout-en-bout,
 * eux, lancent le vrai binaire avec de vrais modules témoins.
 */
function orchestrateurAvecJournal(string $corps): string
{
    return <<<BASH
        set -e
        bac="\$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ (voir le même
        # garde dans InstallSentinelsTest : une interpolation ratée a déjà fait
        # semer une arborescence de sonde DANS l'arbre applicatif).
        case "\$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
        esac
        export INSTALL_STATE_DIR="\$bac/etat"
        export LOG_FILE="\$bac/install.log"
        mkdir -p "\$INSTALL_STATE_DIR"
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
// Le routage : *aware* → lancé pour de vrai ; sinon → annoncé puis sauté
// =============================================================================

it('un module NON aware n’est JAMAIS lancé sous --dry-run', function (): void {
    // Ligne « Module non *aware* simulé » de la matrice. La preuve n'est pas la
    // ligne « NON lancé » — c'est le TÉMOIN que le module aurait écrit s'il
    // avait tourné. La seconde passe, hors simulation, est l'anti-vacuité :
    // sans elle, un témoin cassé rendrait ce test vert quoi qu'il arrive.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        cp -a "$SCRIPTS_DIR" "$bac/scripts"
        cible="$bac/cible"
        mkdir -p "$cible"
        export INSTALL_STATE_DIR="$bac/etat"

        temoin="$bac/temoin"

        # `printf` et non un document en-place : le heredoc PHP qui porte ce
        # fragment retire l'indentation du marqueur fermant, donc un heredoc
        # bash imbriqué doit être indenté d'autant — plus fragile que ceci.
        printf '#!/bin/bash\necho "LANCE" >> "%s"\nexit 0\n' "$temoin" \
            > "$bac/scripts/install/30-packages-prod.sh"
        chmod +x "$bac/scripts/install/30-packages-prod.sh"

        statut=0
        "$bac/scripts/install.sh" --dry-run --only 30-packages-prod "$cible" > "$bac/simulation" 2>&1 || statut=$?
        echo "SIM_STATUS=$statut"
        echo "SIM_TEMOIN=[$(cat "$temoin" 2>/dev/null)]"
        grep -q "NON lancé" "$bac/simulation" && echo "SIM_ANNONCE=oui" || echo "SIM_ANNONCE=non"

        # Anti-vacuité : hors simulation, le MÊME témoin est bien écrit.
        statut=0
        "$bac/scripts/install.sh" --only 30-packages-prod "$cible" > "$bac/reel" 2>&1 || statut=$?
        echo "REEL_STATUS=$statut"
        echo "REEL_TEMOIN=[$(cat "$temoin" 2>/dev/null)]"

        rm -rf "$bac"
        BASH
        , [
            'SCRIPTS_DIR' => ShellProbe::scriptsDir(),
        ], 120);

    expect($result['output'])->toContain('SIM_STATUS=0');
    expect($result['output'])->toContain('SIM_TEMOIN=[]');
    expect($result['output'])->toContain('SIM_ANNONCE=oui');

    expect($result['output'])->toContain('REEL_STATUS=0');
    expect($result['output'])->toContain('REEL_TEMOIN=[LANCE]');
});

it('un module AWARE est lancé POUR DE VRAI sous --dry-run, et voit INSTALL_DRY_RUN', function (): void {
    // Ligne « Module *aware* simulé » de la matrice, et le cœur du mécanisme :
    // le module tourne en SOUS-PROCESSUS, donc ce qu'il voit de la simulation
    // ne peut venir que d'une variable EXPORTÉE. `DRY_RUN` ne l'est pas — un
    // fils lit `<absent>` ; `INSTALL_DRY_RUN` est dérivée une fois dans
    // `run_installation`. Retirer cet export laisserait le module s'exécuter
    // POUR DE VRAI sous un drapeau qui promet l'inverse.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        cp -a "$SCRIPTS_DIR" "$bac/scripts"
        cible="$bac/cible"
        mkdir -p "$cible"
        export INSTALL_STATE_DIR="$bac/etat"
        # 🔴 LA RACINE D'ÉTAT EST CRÉÉE, ET C'EST CE QUI REND LA MESURE VIVANTE.
        # Mesuré : sans ce `mkdir`, une mutation qui ÉCRIT la sentinelle sous
        # simulation restait VERTE — l'écriture échouait faute de répertoire, et
        # le compteur retombait à 0 pour une raison étrangère au sujet. Un
        # compteur qui vaut 0 parce que rien ne POUVAIT s'écrire ne mesure rien.
        mkdir -p "$INSTALL_STATE_DIR"

        temoin="$bac/temoin"

        printf '#!/bin/bash\necho "LANCE:${INSTALL_DRY_RUN:-<absent>}" >> "%s"\nexit 0\n' "$temoin" \
            > "$bac/scripts/install/10-laravel-core.sh"
        chmod +x "$bac/scripts/install/10-laravel-core.sh"

        statut=0
        "$bac/scripts/install.sh" --dry-run --only 10-laravel-core "$cible" > "$bac/simulation" 2>&1 || statut=$?
        echo "STATUS=$statut"
        echo "TEMOIN=[$(cat "$temoin" 2>/dev/null)]"
        grep -q "DRY-RUN AWARE" "$bac/simulation" && echo "ANNONCE=oui" || echo "ANNONCE=non"
        echo "ETAT_FICHIERS=$(find "$INSTALL_STATE_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"

        rm -rf "$bac"
        BASH
        , [
            'SCRIPTS_DIR' => ShellProbe::scriptsDir(),
        ], 120);

    expect($result['output'])->toContain('STATUS=0');
    // Le module a RÉELLEMENT tourné…
    expect($result['output'])->toContain('TEMOIN=[LANCE:true]');
    // …et surtout il n'a pas vu `<absent>` : sans export, il aurait installé.
    expect($result['output'])->not->toContain('<absent>');
    expect($result['output'])->toContain('ANNONCE=oui');
    // ⛔ L'invariant de la 2.2 ne recule pas là où il compte le plus : un module
    // *aware* mené à son terme ne pose PAS sa sentinelle.
    expect($result['output'])->toContain('ETAT_FICHIERS=0');
});

// =============================================================================
// Le module 10 simulé — ce qu'il EFFACERAIT, et ce qu'il laisse intact
// =============================================================================

it('10-laravel-core simulé NOMME chaque suppression et ne touche à rien', function (): void {
    // 🔴 LE DÉFAUT QUE CETTE STORY EXISTE POUR CORRIGER. La simulation
    // s'arrêtait au grain module — « je simulerais 10-laravel-core » — sans
    // jamais dire CE QU'ELLE EFFACERAIT. Or ce module est le seul dont l'échec
    // est une perte de données irréversible (`rm -rf -- "$target_dir/…"`).
    //
    // L'empreinte compare NOMS, CONTENUS, MODES ET PROPRIÉTAIRE : un
    // `find | md5sum` seul resterait vert sur un fichier vidé, et aucun des
    // trois ne voit un `chmod`.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        cible="$bac/cible"
        mkdir -p "$cible/vendor" "$cible/app"
        echo '{"require":{}}' > "$cible/composer.json"
        echo 'APP_KEY=secret-de-l-operateur' > "$cible/.env"
        chmod 600 "$cible/.env"

        export INSTALL_STATE_DIR="$bac/etat"
        mkdir -p "$INSTALL_STATE_DIR"
        : > "$INSTALL_STATE_DIR/00-prerequisites-done"

        empreinte() {
            {
                find "$cible" | sort
                find "$cible" -type f -exec cat {} +
                find "$cible" -exec stat -c '%n %a %U:%G' {} + | sort
            } | md5sum
        }

        avant="$(empreinte)"

        # `--force` : sans lui, le module REFUSE de nettoyer une installation
        # partielle (garde de la story 2.2) et la simulation s'arrête avant la
        # boucle de suppression — celle-là même qu'on veut voir annoncée.
        statut=0
        "$INSTALL_SH" --dry-run --force --only 10-laravel-core "$cible" > "$bac/sortie" 2>&1 || statut=$?

        apres="$(empreinte)"

        echo "STATUS=$statut"
        [ "$avant" = "$apres" ] && echo "CIBLE=INTACTE" || echo "CIBLE=MODIFIEE"
        echo "ETAT_FICHIERS=$(find "$INSTALL_STATE_DIR" -type f | wc -l | tr -d ' ')"
        echo "NB_DRY=$(grep -c '\[DRY\]' "$bac/sortie" | tr -d ' ')"

        for entree in vendor app composer.json .env; do
            if grep -qF "[DRY] rm -rf -- $cible/$entree" "$bac/sortie"; then
                echo "ANNONCE=$entree"
            fi
        done

        rm -rf "$bac"
        BASH
        , [
            'INSTALL_SH' => ShellProbe::installScript(),
        ], 180);

    expect($result['output'])->toContain('STATUS=0');
    // La cible est bit-pour-bit ET mode-pour-mode celle d'avant.
    expect($result['output'])->toContain('CIBLE=INTACTE');
    // Ni sentinelle neuve, ni `started-at` : seule la sentinelle semée subsiste.
    expect($result['output'])->toContain('ETAT_FICHIERS=1');

    // Chaque entrée condamnée est NOMMÉE, une par une — c'est la promesse.
    expect($result['output'])->toContain('ANNONCE=vendor');
    expect($result['output'])->toContain('ANNONCE=app');
    expect($result['output'])->toContain('ANNONCE=composer.json');
    expect($result['output'])->toContain('ANNONCE=.env');

    // Anti-vacuité : la simulation descend bien au grain de la COMMANDE.
    expect((int) (preg_match('/NB_DRY=(\d+)/', $result['output'], $m) === 1 ? $m[1] : 0))
        ->toBeGreaterThan(10);
});

it('sur une cible LARAVEL-SHAPED, la simulation atteint les commandes profondes sans rien muter', function (): void {
    // 🔴 GARDE-FOU RENDU VIVANT (relevé revue 1). La fixture précédente était un
    // répertoire de bric-à-brac : ni `artisan`, ni `routes/web.php`, ni
    // `phpunit.xml`. Les trois `run_cmd sed -i … phpunit.xml` et le
    // `run_cmd append_healthcheck_route` n'étaient donc JAMAIS ATTEINTS — on
    // pouvait leur retirer `run_cmd` sans rien faire rougir, pendant qu'une
    // simulation réécrivait le `phpunit.xml` et les routes de l'opérateur.
    $result = ShellProbe::run(cibleLaravelShaped(<<<'BASH'
        avant="$(empreinte)"
        modes_avant="$(modes)"

        statut=0
        "$INSTALL_SH" --dry-run --only 10-laravel-core "$cible" > "$bac/sortie" 2>&1 || statut=$?

        apres="$(empreinte)"
        modes_apres="$(modes)"

        echo "STATUS=$statut"
        [ "$avant" = "$apres" ] && echo "CIBLE=INTACTE" || echo "CIBLE=MODIFIEE"
        [ "$modes_avant" = "$modes_apres" ] && echo "MODES=INTACTS" || echo "MODES=MODIFIES"

        # Les commandes profondes ont-elles été ATTEINTES ?
        echo "SED_PHPUNIT=$(grep -c '\[DRY\] sed -i' "$bac/sortie" | tr -d ' ')"
        grep -q '\[DRY\] append_healthcheck_route' "$bac/sortie" && echo "ROUTE=annoncee" || echo "ROUTE=absente"
        grep -q '\[DRY\] composer remove' "$bac/sortie" && echo "REMOVE=annonce" || echo "REMOVE=absent"
        grep -q '\[DRY\] chmod -R 775 storage' "$bac/sortie" && echo "PERMS=annoncees" || echo "PERMS=absentes"

        # …et la simulation ne SUR-déclare pas : `cache:clear` n'est joué en réel
        # que si la sonde `tinker` répond « exists », sonde qu'on ne lance pas.
        grep -q '\[DRY\] php artisan cache:clear' "$bac/sortie" && echo "CACHE=surdeclare" || echo "CACHE=non_surdeclare"
        # …ni `config:cache`, dont la branche dépend d'un APP_ENV lu dans un .env
        # que la simulation n'a pas écrit.
        grep -q '\[DRY\] php artisan config:cache' "$bac/sortie" && echo "CONFIGCACHE=surdeclare" || echo "CONFIGCACHE=non_surdeclare"
        grep -q "Optimisation finale dépendante d'APP_ENV" "$bac/sortie" && echo "OPTIM_DIT=oui" || echo "OPTIM_DIT=non"

        # Et aucune phrase de SUCCÈS pour une action non jouée. La forme
        # affirmative porte le « ✅ » ; la forme honnête porte « NON joué — ».
        grep -q '✅ phpunit.xml patché' "$bac/sortie" && echo "MENSONGE=oui" || echo "MENSONGE=non"
        grep -q 'NON joué — phpunit.xml patché' "$bac/sortie" && echo "HONNETE=oui" || echo "HONNETE=non"
        grep -q '✅ Clé d.application générée' "$bac/sortie" && echo "MENSONGE_CLE=oui" || echo "MENSONGE_CLE=non"
        grep -q 'NON joué — Clé d.application générée' "$bac/sortie" && echo "HONNETE_CLE=oui" || echo "HONNETE_CLE=non"

        # Le journal ne DOUBLE pas les lignes du plan (run_cmd_logged + tee).
        # Le chemin est LU DANS LA SORTIE, jamais deviné par un glob : deux
        # sondes concurrentes partagent /tmp.
        journal="$(sed 's/\x1b\[[0-9;]*m//g' "$bac/sortie" | sed -n 's/.*📄 Plan complet: //p' | tail -1)"
        if [ -n "$journal" ] && [ -f "$journal" ]; then
            echo "DOUBLONS=$(grep -ac 'DRY\] composer remove' "$journal" | tr -d ' ')"
        else
            echo "DOUBLONS=journal-introuvable[$journal]"
        fi
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 180);

    expect($result['output'])->toContain('STATUS=0');
    expect($result['output'])->toContain('CIBLE=INTACTE');
    expect($result['output'])->toContain('MODES=INTACTS');

    // Les trois `sed -i` sur phpunit.xml sont ATTEINTS — c'est ce qui rend leur
    // routage vérifiable.
    expect($result['output'])->toContain('SED_PHPUNIT=3');
    expect($result['output'])->toContain('ROUTE=annoncee');
    expect($result['output'])->toContain('REMOVE=annonce');
    expect($result['output'])->toContain('PERMS=annoncees');

    // Ni sous-déclaration, ni SUR-déclaration : les deux branches qui dépendent
    // d'un état que la simulation n'a pas écrit s'annoncent comme indécidables.
    expect($result['output'])->toContain('CACHE=non_surdeclare');
    expect($result['output'])->toContain('CONFIGCACHE=non_surdeclare');
    expect($result['output'])->toContain('OPTIM_DIT=oui');

    // ⚖️ Chaque « pas de mensonge » est appairé à la présence de la forme
    // honnête : sinon, supprimer la ligne entièrement suffirait à passer.
    expect($result['output'])->toContain('MENSONGE=non');
    expect($result['output'])->toContain('HONNETE=oui');
    expect($result['output'])->toContain('MENSONGE_CLE=non');
    expect($result['output'])->toContain('HONNETE_CLE=oui');

    // 🔴 `run_cmd_logged` sous simulation passait la ligne `[DRY]` dans `tee`
    // ALORS QUE `log_info` l'avait déjà écrite dans `$LOG_FILE` : une TROISIÈME
    // copie, avec ses échappements ANSI.
    //
    // ⚖️ POURQUOI 2 ET NON 1, ÉCRIT PLUTÔT QUE SUBI : le journal reçoit chaque
    // ligne de module deux fois par construction — une par `log()` lui-même,
    // une par le `… 2>&1 | tee -a "$LOG_FILE"` de `execute_module`. Ce doublage
    // est ANTÉRIEUR à cette story et concerne TOUTE la sortie des modules ; le
    // corriger changerait le journal de l'installation réelle. Ce qui est
    // corrigé ici, et mesuré ici, c'est la copie SUPPLÉMENTAIRE que le routage
    // avait ajoutée. Rétablir le `tee` sous simulation fait passer ce compteur
    // à 3 (mutation rejouée, rouge observé).
    expect($result['output'])->toContain('DOUBLONS=2');
});

// =============================================================================
// Les deux effets de bord que la simulation posait AVANT toute branche dry-run
// =============================================================================

it('--dry-run ne crée ni ne chmode le répertoire cible', function (): void {
    // Ligne « Cible absente + simulation » de la matrice. `validate_arguments`
    // faisait `mkdir -p`, `chown -R` et jusqu'à `chmod -R 777` sur la cible
    // AVANT toute branche `--dry-run`.
    //
    // 🔴 DEUX MESURES, PARCE QU'UNE SEULE NE VOYAIT PAS LE `chmod` (revue 1) :
    // sur une cible ABSENTE, un `chmod` réintroduit serait un no-op. La seconde
    // cible EXISTE et porte des modes distinctifs, relevés au `stat`.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        export LOG_FILE="$bac/install.log"
        export INSTALL_STATE_DIR="$bac/etat"

        source "$INSTALL_SH"

        # Le chemin proactif de `validate_arguments` est CONDITIONNÉ à Docker.
        # La CI tourne sur un runner nu : sans cette forçe, la sonde mesurerait
        # une branche qui ne s'exécute pas, donc rien du tout.
        is_docker_environment() { return 0; }

        modes() { find "$1" -exec stat -c '%n %a %U:%G' {} + | sort | md5sum; }

        # ── 1) Cible ABSENTE ────────────────────────────────────────────────
        TARGET_DIR="$bac/absente-simulation"
        DRY_RUN=true
        validate_arguments > "$bac/sim" 2>&1
        [ -d "$TARGET_DIR" ] && echo "SIM_ABSENTE=CREE" || echo "SIM_ABSENTE=NON_CREE"
        grep -qF "$TARGET_DIR" "$bac/sim" && echo "SIM_NOMME=oui" || echo "SIM_NOMME=non"

        # ── 2) Cible EXISTANTE, aux modes distinctifs ───────────────────────
        TARGET_DIR="$bac/peuplee"
        mkdir -p "$TARGET_DIR/sous"
        printf 'contenu\n' > "$TARGET_DIR/fichier"
        chmod 700 "$TARGET_DIR/sous"
        chmod 600 "$TARGET_DIR/fichier"
        chmod 750 "$TARGET_DIR"

        avant="$(modes "$TARGET_DIR")"
        DRY_RUN=true
        validate_arguments > "$bac/sim2" 2>&1
        apres="$(modes "$TARGET_DIR")"
        [ "$avant" = "$apres" ] && echo "SIM_MODES=INTACTS" || echo "SIM_MODES=MODIFIES"

        # ── 3) Anti-vacuité : hors simulation, ça crée ET ça chmode ─────────
        TARGET_DIR="$bac/absente-reelle"
        DRY_RUN=false
        validate_arguments > "$bac/reel" 2>&1
        [ -d "$TARGET_DIR" ] && echo "REEL_ABSENTE=CREE" || echo "REEL_ABSENTE=NON_CREE"

        TARGET_DIR="$bac/peuplee-reelle"
        mkdir -p "$TARGET_DIR/sous"
        printf 'contenu\n' > "$TARGET_DIR/fichier"
        chmod 700 "$TARGET_DIR/sous"
        chmod 600 "$TARGET_DIR/fichier"
        chmod 750 "$TARGET_DIR"

        avant="$(modes "$TARGET_DIR")"
        DRY_RUN=false
        validate_arguments > "$bac/reel2" 2>&1
        apres="$(modes "$TARGET_DIR")"
        [ "$avant" = "$apres" ] && echo "REEL_MODES=INTACTS" || echo "REEL_MODES=MODIFIES"

        rm -rf "$bac"
        BASH
        , [
            'INSTALL_SH' => ShellProbe::installScript(),
        ], 60);

    expect($result['output'])->toContain('SIM_ABSENTE=NON_CREE');
    // Diagnostiqué ET signalé : le message nomme le chemin.
    expect($result['output'])->toContain('SIM_NOMME=oui');
    expect($result['output'])->toContain('SIM_MODES=INTACTS');

    // Anti-vacuité : les deux effets existent bel et bien hors simulation.
    expect($result['output'])->toContain('REEL_ABSENTE=CREE');
    expect($result['output'])->toContain('REEL_MODES=MODIFIES');
});

it('--dry-run REFUSE un module non exécutable au lieu de chmoder un fichier versionné', function (): void {
    // Ligne « Module non exécutable + simulation » de la matrice. Le `chmod +x`
    // s'exécutait avant toute branche dry-run, sur un fichier SUIVI PAR GIT :
    // `git status --porcelain` ne sortait donc plus vide après une simulation.
    // Et le mode d'un module est une vraie condition d'installation — la
    // simulation existe pour la découvrir, pas pour la réparer en douce.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        cp -a "$SCRIPTS_DIR" "$bac/scripts"
        cible="$bac/cible"
        mkdir -p "$cible"
        export INSTALL_STATE_DIR="$bac/etat"

        # Les deux modules sont réduits à un no-op : ce test porte sur le MODE
        # du fichier, pas sur ce qu'il installe.
        for module in 30-packages-prod 40-packages-dev; do
            printf '#!/bin/bash\nexit 0\n' > "$bac/scripts/install/$module.sh"
            chmod -x "$bac/scripts/install/$module.sh"
        done

        statut=0
        "$bac/scripts/install.sh" --dry-run --only 30-packages-prod "$cible" > "$bac/simulation" 2>&1 || statut=$?
        echo "SIM_STATUS=$statut"
        [ -x "$bac/scripts/install/30-packages-prod.sh" ] && echo "SIM_MODE=CHMODE" || echo "SIM_MODE=INTACT"
        grep -q "Module non exécutable" "$bac/simulation" && echo "SIM_SIGNALE=oui" || echo "SIM_SIGNALE=non"

        # Anti-vacuité : hors simulation, l'orchestrateur corrige bien le mode.
        statut=0
        "$bac/scripts/install.sh" --only 40-packages-dev "$cible" > "$bac/reel" 2>&1 || statut=$?
        echo "REEL_STATUS=$statut"
        [ -x "$bac/scripts/install/40-packages-dev.sh" ] && echo "REEL_MODE=CHMODE" || echo "REEL_MODE=INTACT"

        rm -rf "$bac"
        BASH
        , [
            'SCRIPTS_DIR' => ShellProbe::scriptsDir(),
        ], 120);

    // Échec EXPLICITE en simulation, et le fichier n'a pas bougé.
    expect($result['output'])->toContain('SIM_STATUS=1');
    expect($result['output'])->toContain('SIM_MODE=INTACT');
    expect($result['output'])->toContain('SIM_SIGNALE=oui');

    expect($result['output'])->toContain('REEL_STATUS=0');
    expect($result['output'])->toContain('REEL_MODE=CHMODE');
});

// =============================================================================
// Le rapport final ne déclare AUCUNE installation faite
// =============================================================================

it('une simulation complète ne modifie rien ET ne déclare aucune installation', function (): void {
    // 🔴 CONSTAT STRUCTURANT DE LA REVUE 1. Sous `--dry-run`, l'orchestrateur
    // clôturait par « 🎉 Installation Laravel terminée », « 🆕 VERDICT:
    // EXECUTED — 11 module(s) joué(s) », listait les onze modules sous
    // « Modules installés », puis entrait dans `cd "$TARGET_DIR"` +
    // `get_laravel_version` — c'est-à-dire `php artisan --version`, qui BOOTE
    // l'application et écrit dans `storage/logs/`. Un rapport mensonger ET un
    // effet de bord, dans la fonction de clôture du drapeau.
    //
    // L'inventaire couvre le dépôt ET l'application, ce que `git status` ne fait
    // pas pour les fichiers ignorés.
    $roots = array_values(array_filter(
        [ShellProbe::repoRoot(), ShellProbe::srcDir()],
        static fn (string $path): bool => is_dir($path),
    ));

    $avant = ShellProbe::inventory($roots);

    // La garde qui fait tout le travail : deux inventaires vides seraient
    // identiques, donc verts, sur une simulation qui aurait tout réécrit.
    expect($avant)
        ->not->toBeEmpty();
    expect(count($avant))
        ->toBeGreaterThan(100);

    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        cible="$bac/cible"
        mkdir -p "$cible"
        export INSTALL_STATE_DIR="$bac/etat"
        # Créée pour la même raison qu'ailleurs : un « 0 fichier d'état » obtenu
        # parce que l'écriture était IMPOSSIBLE ne prouve pas qu'elle n'a pas
        # été tentée.
        mkdir -p "$INSTALL_STATE_DIR"

        statut=0
        "$INSTALL_SH" --dry-run "$cible" > "$bac/sortie" 2>&1 || statut=$?

        echo "STATUS=$statut"
        echo "CIBLE_ENTREES=$(find "$cible" | wc -l | tr -d ' ')"
        echo "ETAT=$(find "$INSTALL_STATE_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"

        grep -q 'VERDICT: DRY-RUN' "$bac/sortie" && echo "VERDICT=DRY-RUN" || echo "VERDICT=absent"
        grep -q 'VERDICT: EXECUTED' "$bac/sortie" && echo "MENSONGE_EXECUTED=oui" || echo "MENSONGE_EXECUTED=non"
        grep -q 'Modules installés' "$bac/sortie" && echo "MENSONGE_INSTALLES=oui" || echo "MENSONGE_INSTALLES=non"
        grep -q 'Installation Laravel terminée' "$bac/sortie" && echo "MENSONGE_TERMINEE=oui" || echo "MENSONGE_TERMINEE=non"
        grep -q 'Versions installées' "$bac/sortie" && echo "SONDE_VERSION=oui" || echo "SONDE_VERSION=non"

        # Les trois compteurs sont DISTINCTS : 1 module réellement simulé
        # (10-laravel-core), 10 annoncés sans exécution, 0 déjà franchi.
        grep -q 'Modules réellement simulés: 1' "$bac/sortie" && echo "SIMULES=1" || echo "SIMULES=autre"
        grep -q 'Modules annoncés sans exécution: 10' "$bac/sortie" && echo "ANNONCES=10" || echo "ANNONCES=autre"

        rm -rf "$bac"
        BASH
        , [
            'INSTALL_SH' => ShellProbe::installScript(),
        ], 180);

    $apres = ShellProbe::inventory($roots);

    $modifies = array_keys(array_merge(
        array_diff_assoc($avant, $apres),
        array_diff_assoc($apres, $avant),
    ));

    expect($modifies)
        ->toBe([]);
    expect($result['output'])->toContain('STATUS=0');
    // La cible reste le seul répertoire qu'on lui a donné : rien dedans.
    expect($result['output'])->toContain('CIBLE_ENTREES=1');
    // Ni sentinelle, ni `started-at`.
    expect($result['output'])->toContain('ETAT=0');

    // ⚖️ CHAQUE `not->toContain` EST APPAIRÉ À UNE PRÉSENCE : une sortie
    // entièrement vide (sonde cassée, chemin faux) satisferait sinon les cinq
    // absences d'un coup.
    expect($result['output'])->toContain('VERDICT=DRY-RUN');
    expect($result['output'])->toContain('MENSONGE_EXECUTED=non');
    expect($result['output'])->toContain('MENSONGE_INSTALLES=non');
    expect($result['output'])->toContain('MENSONGE_TERMINEE=non');
    expect($result['output'])->toContain('SONDE_VERSION=non');

    // Les trois populations ne sont plus confondues dans `executed_modules`.
    expect($result['output'])->toContain('SIMULES=1');
    expect($result['output'])->toContain('ANNONCES=10');
});

// =============================================================================
// --resume-from : il saute l'amont, il ne FORCE rien
// =============================================================================

it('--resume-from saute l’amont, et l’ÉTAT prime toujours en aval', function (): void {
    // Ligne « --resume-from + sentinelle en aval » de la matrice, et le refus
    // explicite du bloc gelé : `--resume-from X` ne rejoue PAS un module situé
    // après X qui porte déjà sa sentinelle. Seul `--force` rejoue.
    $result = ShellProbe::run(orchestrateurAvecJournal(<<<'BASH'
        # Un module d'AVAL est déjà franchi.
        : > "$INSTALL_STATE_DIR/50-quality-tools-done"

        RESUME_FROM="20-database"
        run_installation > "$bac/sortie" 2>&1
        joues "REPRISE"

        grep -q "Ignoré (--resume-from)" "$bac/sortie" && echo "AMONT_ANNONCE=oui" || echo "AMONT_ANNONCE=non"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    $modules = ShellProbe::installModules();

    // Anti-vacuité : la liste lue sur disque doit vraiment contenir les deux
    // modules dont ce test parle, ET l'index doit être trouvé — un
    // `array_search` qui rend `false` retombait silencieusement sur `0`, donc
    // sur la liste ENTIÈRE, et l'attendu devenait faux sans le dire.
    expect($modules)
        ->toContain('20-database');
    expect($modules)
        ->toContain('50-quality-tools');

    $depart = array_search('20-database', $modules, true);
    expect($depart)
        ->not->toBeFalse();

    $attendus = array_values(array_filter(
        array_slice($modules, (int) $depart),
        static fn (string $module): bool => $module !== '50-quality-tools',
    ));

    expect($result['output'])->toContain('REPRISE=[' . implode(',', $attendus) . ',]');
    expect($result['output'])->toContain('AMONT_ANNONCE=oui');
});

it('--resume-from bout-en-bout, avec le VRAI execute_module et de vrais modules', function (): void {
    // 🔴 LE PRÉLUDE JOURNALISÉ NE MESURE PAS `execute_module` — il le REMPLACE.
    // `--resume-from` n'avait donc jamais été éprouvé de bout en bout : ni
    // combiné à `--dry-run`, ni avec un module inconnu, ni avec `--force`.
    // Ici l'orchestrateur lance de VRAIS sous-processus (des modules témoins),
    // et la preuve est ce qu'ils ont écrit sur disque.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        cp -a "$SCRIPTS_DIR" "$bac/scripts"
        cible="$bac/cible"
        mkdir -p "$cible"
        temoin="$bac/temoin"

        # CHAQUE module devient un témoin : la trace est donc exhaustive, et
        # aucun module réel ne tourne.
        for fichier in "$bac"/scripts/install/*.sh; do
            nom="$(basename "$fichier" .sh)"
            printf '#!/bin/bash\necho "%s" >> "%s"\nexit 0\n' "$nom" "$temoin" > "$fichier"
            chmod +x "$fichier"
        done

        passe() {
            local etiquette="$1"; shift
            : > "$temoin"
            rm -rf "$bac/etat"
            mkdir -p "$bac/etat"
            [ -n "$SEMER" ] && : > "$bac/etat/$SEMER-done"
            local statut=0
            INSTALL_STATE_DIR="$bac/etat" "$bac/scripts/install.sh" "$@" "$cible" > "$bac/sortie-$etiquette" 2>&1 || statut=$?
            echo "${etiquette}_STATUS=$statut"
            echo "${etiquette}_JOUES=[$(tr '\n' ',' < "$temoin")]"
        }

        SEMER=""
        passe "NU" --resume-from 30-packages-prod

        # Combiné à --dry-run : aucun témoin ne doit être écrit pour les modules
        # NON aware, et 10-laravel-core (aware) est EN AMONT donc jamais lancé.
        SEMER=""
        passe "DRY" --dry-run --resume-from 30-packages-prod

        # Un module d'aval déjà franchi reste sauté : l'état prime.
        SEMER="50-quality-tools"
        passe "ETAT" --resume-from 30-packages-prod

        # `--force` est le SEUL drapeau qui rejoue un module déjà franchi.
        SEMER="50-quality-tools"
        passe "FORCE" --resume-from 30-packages-prod --force

        # Un module inconnu est refusé, bruyamment, avant toute exécution.
        SEMER=""
        passe "INCONNU" --resume-from module-qui-nexiste-pas
        grep -q "Module invalide pour --resume-from" "$bac/sortie-INCONNU" && echo "INCONNU_SIGNALE=oui" || echo "INCONNU_SIGNALE=non"

        rm -rf "$bac"
        BASH
        , [
            'SCRIPTS_DIR' => ShellProbe::scriptsDir(),
        ], 180);

    $modules = ShellProbe::installModules();
    $depart = array_search('30-packages-prod', $modules, true);
    expect($depart)
        ->not->toBeFalse();

    $aval = array_slice($modules, (int) $depart);
    expect(count($aval))
        ->toBe(7);

    // 1) Reprise nue : l'amont est sauté, l'aval joué en entier.
    expect($result['output'])->toContain('NU_STATUS=0');
    expect($result['output'])->toContain('NU_JOUES=[' . implode(',', $aval) . ',]');

    // 2) Combiné à --dry-run : AUCUN module ne tourne (aucun de l'aval n'est
    //    *aware*, et le seul qui l'est se trouve en amont du point de reprise).
    expect($result['output'])->toContain('DRY_STATUS=0');
    expect($result['output'])->toContain('DRY_JOUES=[]');

    // 3) L'état prime en aval : 50-quality-tools reste sauté.
    $sansCinquante = array_values(array_filter(
        $aval,
        static fn (string $module): bool => $module !== '50-quality-tools',
    ));
    expect($result['output'])->toContain('ETAT_STATUS=0');
    expect($result['output'])->toContain('ETAT_JOUES=[' . implode(',', $sansCinquante) . ',]');

    // 4) …sauf sous --force, le SEUL drapeau qui rejoue.
    expect($result['output'])->toContain('FORCE_STATUS=0');
    expect($result['output'])->toContain('FORCE_JOUES=[' . implode(',', $aval) . ',]');

    // 5) Module inconnu : refus bruyant, et rien n'a tourné.
    expect($result['output'])->not->toContain('INCONNU_STATUS=0');
    expect($result['output'])->toContain('INCONNU_JOUES=[]');
    expect($result['output'])->toContain('INCONNU_SIGNALE=oui');
});

// =============================================================================
// Sur QUEL FLUX part le plan — mesuré, pas affirmé
// =============================================================================

it('le plan est réparti sur STDOUT et STDERR, et seule une capture 2>&1 est complète', function (): void {
    // 🔴 LA CORRECTION DU CONSTAT « dis sur quel flux part le plan » A PRODUIT
    // UNE PHRASE FAUSSE À CÔTÉ D'UN CODE JUSTE, dans sa propre correction, en
    // CINQ endroits — dont `CLAUDE.md` et l'aide de `--help`, les deux que
    // l'opérateur lit. Elle affirmait « STDERR ; `> plan.txt` rend un fichier
    // vide ». Mesuré : la MAJORITÉ des lignes `[DRY]` sort sur **STDOUT**.
    //
    // Cause : `log_info` écrit bien sur stderr, mais `execute_module` lance le
    // module en `"$module_file" … 2>&1 | tee -a "$LOG_FILE"` — ce `2>&1` replie
    // le stderr du MODULE dans le stdout de l'orchestrateur.
    //
    // ⚠️ AUCUN AUTRE TEST NE PEUT ATTRAPER ÇA : `ShellProbe::run()` construit
    // `bash … 2>&1`, donc toutes les autres assertions lisent un flux fusionné.
    $result = ShellProbe::runSeparated(<<<'BASH'
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        cible="$bac/cible"
        mkdir -p "$cible"
        export INSTALL_STATE_DIR="$bac/etat"
        mkdir -p "$INSTALL_STATE_DIR"

        "$INSTALL_SH" --dry-run --only 10-laravel-core "$cible"

        rm -rf "$bac"
        BASH
        , [
            'INSTALL_SH' => ShellProbe::installScript(),
        ], 120);

    // `preg_match_all` rend `int|false` : le cast est explicite plutôt que
    // laissé à PHPStan, un `false` silencieux valant 0 masquerait un flux vide.
    $compte = static function (string $flux): int {
        $n = preg_match_all('/\[DRY\] /', $flux);

        if ($n === false) {
            throw new RuntimeException('Comptage impossible sur le flux capturé.');
        }

        return $n;
    };

    $surOut = $compte($result['stdout']);
    $surErr = $compte($result['stderr']);

    // Anti-vacuité : la simulation a bien produit un plan.
    expect($surOut + $surErr)
        ->toBeGreaterThan(10);

    // ⛔ LES DEUX FLUX EN PORTENT, donc AUCUNE capture d'un seul n'est complète.
    // C'est cela, et rien d'autre, que la prose doit dire.
    expect($surOut)
        ->toBeGreaterThan(0);
    expect($surErr)
        ->toBeGreaterThan(0);

    // …et la majorité est sur stdout, à l'exact inverse de ce qui était écrit.
    expect($surOut)
        ->toBeGreaterThan($surErr);

    $surfaces = [
        'CLAUDE.md',
        'scripts/install.sh',
        'scripts/lib/runtime.sh',
        'Makefile',
        'docs/ETAT.md',
    ];

    foreach ($surfaces as $fichier) {
        $source = RepoFile::read($fichier);

        // La recommandation qui MARCHE est présente…
        expect($source)
            ->toContain('2>&1');
        // …et aucune des formulations fausses ne revient. Les cinq surfaces
        // sont vérifiées ensemble : c'est d'en corriger trois sur cinq que
        // l'opérateur aurait pâti.
        expect($source)
            ->not->toContain('plan.txt VIDE');
        expect($source)
            ->not->toContain('partent sur STDERR');
        expect($source)
            ->not->toContain('LA TRACE PART SUR STDERR');
    }
});

// =============================================================================
// Invariant GLOBAL : une simulation n'affirme AUCUN succès de travail
// =============================================================================

it('aucune ligne de SUCCÈS ne survit à une simulation, hors constats de disque', function (): void {
    // 🔴 DEUX CHAÎNES CHOISIES À LA MAIN NE GARDENT PAS ONZE SITES (revue 2).
    // Neuf des onze conversions `log_applied` n'étaient assertées par rien :
    // reverter « ✅ Packages skeleton supprimés » en `log_success` laissait les
    // 20 tests verts, alors que le site est PROUVÉ atteint (le `[DRY] composer
    // remove` de la ligne juste au-dessus est asserté).
    //
    // L'invariant est donc GLOBAL : dans une simulation, toute ligne `[SUCCESS]`
    // portant un « ✅ » est un mensonge, SAUF trois familles de constats — et
    // ces trois-là sont énumérées ici, pas déduites.
    $result = ShellProbe::run(cibleLaravelShaped(<<<'BASH'
        "$INSTALL_SH" --dry-run --only 10-laravel-core "$cible" > "$bac/peuplee" 2>&1 || true

        # Et la même chose sur une cible VIDE : les deux formes de simulation
        # traversent des chemins différents (installation vs patch).
        vide="$bac/vide"
        mkdir -p "$vide"
        "$INSTALL_SH" --dry-run --only 10-laravel-core "$vide" > "$bac/vide-sortie" 2>&1 || true

        echo "=== LIGNES_SUCCESS ==="
        cat "$bac/peuplee" "$bac/vide-sortie" \
            | sed 's/\x1b\[[0-9;]*m//g' \
            | grep -a '\[SUCCESS' \
            | sed 's/^\[SUCCESS [^]]*\] //' \
            | sort -u
        echo "=== FIN ==="
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 240);

    preg_match('/=== LIGNES_SUCCESS ===\n(.*)=== FIN ===/s', $result['output'], $bloc);

    $lignes = array_values(array_filter(
        array_map('trim', explode("\n", $bloc[1] ?? '')),
        static fn (string $ligne): bool => $ligne !== '',
    ));

    // Anti-vacuité : la simulation a bien parlé. Un bloc vide (grep raté,
    // sortie fusionnée ailleurs) satisferait sinon l'invariant sans rien voir.
    expect(count($lignes))
        ->toBeGreaterThan(3);

    // Les trois familles TOLÉRÉES, et pourquoi :
    //  • « <ÉTAPE> terminé en <durée> » — borne d'étape émise par `logging.sh`
    //    (`log_step_end`), partagée par tout le dépôt : elle dit qu'un bloc
    //    s'achève, pas qu'un travail a eu lieu ;
    //  • « Projet Laravel existant détecté » / « Fichier source trouvé » — des
    //    CONSTATS sur le disque, vrais en simulation comme en réel.
    $tolerees = [
        '/^✅ .+ terminé en \d+/u',
        '/^✅ Projet Laravel existant détecté dans /u',
        '/^✅ Fichier source trouvé: /u',
    ];

    $mensonges = array_values(array_filter($lignes, static function (string $ligne) use ($tolerees): bool {
        if (! str_contains($ligne, '✅')) {
            return false;
        }

        foreach ($tolerees as $motif) {
            if (preg_match($motif, $ligne) === 1) {
                return false;
            }
        }

        return true;
    }));

    expect($mensonges)
        ->toBe([]);
});

// =============================================================================
// Chemin RÉEL — les branches d'échec que le routage avait rendues muettes
// =============================================================================
//
// ⛔ CES TESTS NE PARLENT PAS DE SIMULATION. Ils gardent le chemin
// d'installation RÉEL contre des régressions introduites — ou révélées — par le
// routage de cette story. Ils vivent ici parce que c'est ce diff qui les a
// créées.

/**
 * Harnais d'exécution RÉELLE d'`install_laravel_via_composer`.
 *
 * ⛔ POURQUOI IL FAUT EXÉCUTER, ET NON SCANNER. Le garde textuel `run_cmd`
 * saute toute ligne contenant `run_cmd` : réécrire `if ! run_cmd composer
 * install … 2>&1 | tee -a "$LOG_FILE"` — le défaut EXACT de la passe 1 —
 * laissait les 20 tests VERTS, la ligne étant comptée comme routée. Seule une
 * sonde qui LANCE la fonction, avec un `composer` et un `cp` stubés, distingue
 * un code propagé d'un code avalé par `tee`.
 */
function harnaisComposer(string $corps): string
{
    return <<<BASH
        bac="\$(mktemp -d)"
        case "\$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
        esac

        mkdir -p "\$bac/bin" "\$bac/cible"
        export LOG_FILE="\$bac/log"
        export JOURNAL="\$bac/journal"
        : > "\$JOURNAL"

        cat > "\$bac/bin/composer" <<'STUB'
        #!/bin/bash
        printf 'COMPOSER %s\\n' "\$*" >> "\$JOURNAL"
        case "\$1" in
            create-project)
                statut="\${COMPOSER_CREATE_STATUS:-0}"
                [ "\$statut" -ne 0 ] && exit "\$statut"
                for a in "\$@"; do
                    case "\$a" in /tmp/laravel-install-*) tmp="\$a" ;; esac
                done
                mkdir -p "\$tmp/bootstrap" "\$tmp/config"
                printf '{"require":{"laravel/framework":"^12.0"},"require-dev":{}}\\n' > "\$tmp/composer.json"
                printf '#!/usr/bin/env php\\n' > "\$tmp/artisan"
                printf '<?php return [];\\n' > "\$tmp/bootstrap/app.php"
                printf '<?php return [];\\n' > "\$tmp/config/app.php"
                exit 0
                ;;
            install) exit "\${COMPOSER_INSTALL_STATUS:-0}" ;;
        esac
        exit 0
        STUB
        chmod +x "\$bac/bin/composer"

        # Installeur Laravel de repli : la majeure qu'il produit est PILOTÉE.
        cat > "\$bac/bin/laravel-installer" <<'STUB'
        #!/bin/bash
        printf 'INSTALLER %s\\n' "\$*" >> "\$JOURNAL"
        for a in "\$@"; do
            case "\$a" in /tmp/laravel-install-*) tmp="\$a" ;; esac
        done
        mkdir -p "\$tmp/bootstrap" "\$tmp/config"
        printf '{"require":{"laravel/framework":"%s"},"require-dev":{}}\\n' "\${FALLBACK_MAJEURE:-^12.0}" > "\$tmp/composer.json"
        printf '#!/usr/bin/env php\\n' > "\$tmp/artisan"
        printf '<?php return [];\\n' > "\$tmp/bootstrap/app.php"
        printf '<?php return [];\\n' > "\$tmp/config/app.php"
        exit 0
        STUB
        chmod +x "\$bac/bin/laravel-installer"
        export LARAVEL_INSTALLER_BIN="\$bac/bin/laravel-installer"

        export PATH="\$bac/bin:\$PATH"

        source "\$MODULE_SH"

        {$corps}

        rm -rf "\$bac"
        BASH;
}

it('un échec de composer install est un ÉCHEC, pas un succès avalé par tee', function (): void {
    // Constat 15 : six des sept sites `tee` ressuscités n'avaient aucune sonde
    // d'exécution. Celui-ci (`composer install`) et celui de `cp -a` sont les
    // deux dont l'échec avalé fait passer une installation ratée pour réussie.
    $result = ShellProbe::run(harnaisComposer(<<<'BASH'
        export COMPOSER_INSTALL_STATUS=4
        statut=0
        install_laravel_via_composer "$bac/cible" "^12.0" > "$bac/ko" 2>&1 || statut=$?
        echo "KO_STATUS=$statut"
        grep -q "Échec de composer install" "$bac/ko" && echo "KO_SIGNALE=oui" || echo "KO_SIGNALE=non"
        [ -f "$bac/cible/artisan" ] && echo "KO_COPIE=oui" || echo "KO_COPIE=non"

        # Anti-vacuité : avec un `composer install` qui réussit, la même
        # fonction va jusqu'au bout et la cible reçoit l'application.
        export COMPOSER_INSTALL_STATUS=0
        rm -rf "$bac/cible"; mkdir -p "$bac/cible"
        statut=0
        install_laravel_via_composer "$bac/cible" "^12.0" > "$bac/ok" 2>&1 || statut=$?
        echo "OK_STATUS=$statut"
        [ -f "$bac/cible/artisan" ] && echo "OK_COPIE=oui" || echo "OK_COPIE=non"
        BASH), [
        'MODULE_SH' => ShellProbe::installModuleScript('10-laravel-core'),
    ], 120);

    expect($result['output'])->not->toContain('KO_STATUS=0');
    expect($result['output'])->toContain('KO_SIGNALE=oui');
    expect($result['output'])->toContain('KO_COPIE=non');

    expect($result['output'])->toContain('OK_STATUS=0');
    expect($result['output'])->toContain('OK_COPIE=oui');
});

it('cp -a est jugé sur son EFFET, pas sur son code de retour', function (): void {
    // 🔴 RÉGRESSION INTRODUITE PAR LE CORRECTIF DE LA PASSE 1 (relevé passe 2).
    // La branche d'échec de `cp -a`, rendue atteignable par `${PIPESTATUS[0]}`,
    // se déclenche quand `-a` (donc `-p`) ne peut pas préserver le PROPRIÉTAIRE
    // — uid 1000 vers un arbre www-data — alors que tous les octets sont
    // arrivés. Elle avortait donc une installation RÉUSSIE et effaçait
    // `temp_dir`. C'est l'effet qui tranche.
    $result = ShellProbe::run(harnaisComposer(<<<'BASH'
        # 1) `cp` rend un code non nul MAIS copie : l'installation continue.
        cat > "$bac/bin/cp" <<'STUB'
        #!/bin/bash
        /bin/cp "$@"
        exit 7
        STUB
        chmod +x "$bac/bin/cp"

        statut=0
        install_laravel_via_composer "$bac/cible" "^12.0" > "$bac/bruyant" 2>&1 || statut=$?
        echo "BRUYANT_STATUS=$statut"
        [ -f "$bac/cible/artisan" ] && echo "BRUYANT_COPIE=oui" || echo "BRUYANT_COPIE=non"
        grep -q "cp -a a rendu 7" "$bac/bruyant" && echo "BRUYANT_SIGNALE=oui" || echo "BRUYANT_SIGNALE=non"

        # 2) `cp` rend un code non nul ET ne copie rien : c'est un vrai échec.
        cat > "$bac/bin/cp" <<'STUB'
        #!/bin/bash
        exit 7
        STUB
        chmod +x "$bac/bin/cp"

        rm -rf "$bac/cible"; mkdir -p "$bac/cible"
        statut=0
        install_laravel_via_composer "$bac/cible" "^12.0" > "$bac/vrai" 2>&1 || statut=$?
        echo "VRAI_STATUS=$statut"
        grep -q "artisan absent de" "$bac/vrai" && echo "VRAI_SIGNALE=oui" || echo "VRAI_SIGNALE=non"
        BASH), [
        'MODULE_SH' => ShellProbe::installModuleScript('10-laravel-core'),
    ], 120);

    // Copie réussie malgré un code non nul ⇒ l'installation N'EST PAS avortée.
    expect($result['output'])->toContain('BRUYANT_STATUS=0');
    expect($result['output'])->toContain('BRUYANT_COPIE=oui');
    expect($result['output'])->toContain('BRUYANT_SIGNALE=oui');

    // Rien de copié ⇒ échec, et le message nomme l'effet manquant.
    expect($result['output'])->not->toContain('VRAI_STATUS=0');
    expect($result['output'])->toContain('VRAI_SIGNALE=oui');
});

it('le repli « laravel new », désormais vivant, REFUSE une majeure non conforme', function (): void {
    // 🔴 LA BRANCHE ÉTAIT MORTE (`tee`), ELLE REVIT — donc ses défauts aussi.
    // Le chemin principal épingle « ^12.0 » ; `laravel new` n'épingle rien et
    // suit la dernière version publiée. Le repli pouvait installer une majeure
    // que rien dans ce dépôt n'a éprouvée, en silence. Son chemin de binaire
    // était figé sur le COMPOSER_HOME de ce conteneur, en prime.
    $result = ShellProbe::run(harnaisComposer(<<<'BASH'
        # `composer create-project` échoue ⇒ le repli est emprunté.
        export COMPOSER_CREATE_STATUS=4

        # 1) Le repli produit une majeure NON conforme : refus.
        export FALLBACK_MAJEURE='^11.0'
        statut=0
        install_laravel_via_composer "$bac/cible" "^12.0" > "$bac/onze" 2>&1 || statut=$?
        echo "ONZE_STATUS=$statut"
        grep -q "majeure non conforme" "$bac/onze" && echo "ONZE_SIGNALE=oui" || echo "ONZE_SIGNALE=non"
        grep -q "INSTALLER" "$JOURNAL" && echo "REPLI_EMPRUNTE=oui" || echo "REPLI_EMPRUNTE=non"

        # 2) Anti-vacuité : conforme ⇒ le repli aboutit.
        export FALLBACK_MAJEURE='^12.0'
        rm -rf "$bac/cible"; mkdir -p "$bac/cible"
        statut=0
        install_laravel_via_composer "$bac/cible" "^12.0" > "$bac/douze" 2>&1 || statut=$?
        echo "DOUZE_STATUS=$statut"
        [ -f "$bac/cible/artisan" ] && echo "DOUZE_COPIE=oui" || echo "DOUZE_COPIE=non"
        BASH), [
        'MODULE_SH' => ShellProbe::installModuleScript('10-laravel-core'),
    ], 120);

    // Le repli EST emprunté — sans ça, les deux passes mesureraient le chemin
    // principal et le test serait vert sans jamais toucher au sujet.
    expect($result['output'])->toContain('REPLI_EMPRUNTE=oui');

    expect($result['output'])->not->toContain('ONZE_STATUS=0');
    expect($result['output'])->toContain('ONZE_SIGNALE=oui');

    expect($result['output'])->toContain('DOUZE_STATUS=0');
    expect($result['output'])->toContain('DOUZE_COPIE=oui');
});

it('un échec de key:generate est un ÉCHEC, pas un succès avalé par tee', function (): void {
    // 🔴 `if run_cmd php artisan key:generate --force 2>&1 | tee -a "$LOG_FILE"`
    // testait le code de `tee`, JAMAIS celui d'artisan. La branche d'échec était
    // morte, et `configure_laravel_environment` traite pourtant cet échec comme
    // FATAL : une clé d'application jamais générée passait pour un succès.
    $result = ShellProbe::run(<<<'BASH'
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        mkdir -p "$bac/bin" "$bac/cible"
        export LOG_FILE="$bac/log"

        printf '#!/bin/bash\nexit 3\n' > "$bac/bin/php"
        chmod +x "$bac/bin/php"
        export PATH="$bac/bin:$PATH"

        printf 'APP_ENV=local\n' > "$bac/cible/.env"
        cd "$bac/cible"

        source "$MODULE_SH"

        # La primitive elle-même : elle rend le code RÉEL de la commande, pas
        # celui de `tee`. C'est la propriété dont dépendent les sept sites.
        sortie3() { return 3; }
        statut=0
        run_cmd_logged sortie3 > /dev/null 2>&1 || statut=$?
        echo "RUN_CMD_LOGGED=$statut"

        statut=0
        generate_application_key > "$bac/sortie" 2>&1 || statut=$?
        echo "KEYGEN=$statut"
        grep -q "Échec de la génération" "$bac/sortie" && echo "SIGNALE=oui" || echo "SIGNALE=non"
        grep -q "Clé d.application générée" "$bac/sortie" && echo "MENSONGE=oui" || echo "MENSONGE=non"

        # Anti-vacuité : avec un `php` qui RÉUSSIT, la même fonction rend 0.
        printf '#!/bin/bash\nexit 0\n' > "$bac/bin/php"
        statut=0
        generate_application_key > "$bac/sortie-ok" 2>&1 || statut=$?
        echo "KEYGEN_OK=$statut"

        rm -rf "$bac"
        BASH
        , [
            'MODULE_SH' => ShellProbe::installModuleScript('10-laravel-core'),
        ], 60);

    // La branche d'échec est VIVANTE : elle rendait 0 tant que le statut testé
    // était celui de `tee`. (`generate_application_key` normalise à 1 ; la
    // propagation du code RÉEL est mesurée sur la primitive.)
    expect($result['output'])->toContain('KEYGEN=1');
    expect($result['output'])->toContain('RUN_CMD_LOGGED=3');
    expect($result['output'])->toContain('SIGNALE=oui');
    expect($result['output'])->toContain('MENSONGE=non');
    expect($result['output'])->toContain('KEYGEN_OK=0');
});

it('un .env absent ne TUE PAS l’installation à la génération de clé', function (): void {
    // 🔴 RÉGRESSION INTRODUITE PAR LE CORRECTIF DE LA PASSE 1 (relevé passe 2).
    // `copy_environment_configuration` est explicitement NON fatale ; sans
    // `.env`, `grep` fuyait un « grep: .env: No such file » BRUT sur stderr —
    // hors format de log — puis `key:generate` échouait et l'appelant en
    // faisait un `log_fatal`. Un chemin conçu pour dégrader proprement tuait
    // l'installation entière.
    $result = ShellProbe::run(<<<'BASH'
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        export LOG_FILE="$bac/log"
        mkdir -p "$bac/sans-env"
        cd "$bac/sans-env"

        source "$MODULE_SH"

        statut=0
        generate_application_key > "$bac/sortie" 2>&1 || statut=$?
        echo "SANS_ENV_STATUS=$statut"
        grep -q "clé d'application NON générée" "$bac/sortie" && echo "SIGNALE=oui" || echo "SIGNALE=non"
        # Aucune fuite BRUTE de grep, hors format de log.
        grep -q "No such file" "$bac/sortie" && echo "FUITE=oui" || echo "FUITE=non"

        rm -rf "$bac"
        BASH
        , [
            'MODULE_SH' => ShellProbe::installModuleScript('10-laravel-core'),
        ], 60);

    // Dégradation propre : l'étape est ignorée, bruyamment, sans tuer l'install.
    expect($result['output'])->toContain('SANS_ENV_STATUS=0');
    expect($result['output'])->toContain('SIGNALE=oui');
    expect($result['output'])->toContain('FUITE=non');
});

it('un .env existant n’est JAMAIS écrasé quand sa sauvegarde échoue', function (): void {
    // 🔴 RÉGRESSION INTRODUITE PAR CETTE STORY (relevé revue 1). Un `cp` NU sous
    // `set -e` arrêtait tout ; enveloppé en `run_cmd … || log_warn`, il était
    // devenu facultatif — et la copie suivante écrasait le `.env` de l'opérateur
    // (clé d'application, identifiants de base, secrets d'API) SANS FILET.
    //
    // ⚠️ REPORT OUVERT (`deferred-work.md`) : la MUTATION de ce garde ne rougit
    // pas dans le conteneur, dont le `cp` BusyBox refuse l'écrasement de
    // lui-même — `.env` y survit pour une raison étrangère au garde. Elle rougit
    // sur GNU coreutils, donc en CI. La sonde reste donc dépendante de
    // l'implémentation de `cp`, et c'est écrit plutôt que tu.
    $result = ShellProbe::run(<<<'BASH'
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        export LOG_FILE="$bac/log"

        # Racine de projet INJECTÉE : sans elle, la branche gardée n'est
        # atteignable que si /var/www/project/.env.local existe — donc jamais
        # sur un runner CI, où les .env ne sont pas versionnés.
        mkdir -p "$bac/projet"
        printf 'APP_ENV=local\nAPP_KEY=venu-de-la-racine\n' > "$bac/projet/.env.local"
        export INSTALL_PROJECT_ROOT="$bac/projet"

        # 🔴 `APP_ENV` EST HÉRITÉ DE PHP, ET IL CHANGE LE SUJET.
        # Mesuré : sous `php artisan test`, `APP_ENV=testing` (phpunit.xml). La
        # fonction cherchait alors `.env.testing`, ne le trouvait pas, sortait
        # par « Aucun fichier .env trouvé » — et le test passait VERT sans
        # jamais atteindre la sauvegarde qu'il prétend garder.
        export APP_ENV=local

        mkdir -p "$bac/cible"
        printf 'APP_KEY=secret-de-l-operateur\n' > "$bac/cible/.env"

        source "$MODULE_SH"

        # ── 1) Sauvegarde IMPOSSIBLE : répertoire non inscriptible ──────────
        cd "$bac/cible"
        chmod 500 "$bac/cible"
        statut=0
        ( copy_environment_configuration ) > "$bac/sortie" 2>&1 || statut=$?
        chmod 755 "$bac/cible"

        echo "REFUS_STATUS=$statut"
        echo "ENV=[$(cat "$bac/cible/.env")]"
        grep -q "Sauvegarde impossible" "$bac/sortie" && echo "REFUS_SIGNALE=oui" || echo "REFUS_SIGNALE=non"

        # ── 2) Anti-vacuité : sauvegarde POSSIBLE ⇒ copie faite ET sauvegardée
        statut=0
        ( copy_environment_configuration ) > "$bac/sortie-ok" 2>&1 || statut=$?
        echo "OK_STATUS=$statut"
        echo "ENV_APRES=[$(cat "$bac/cible/.env")]"
        echo "SAUVEGARDES=$(ls "$bac/cible"/.env.laravel.backup.* 2>/dev/null | wc -l | tr -d ' ')"

        rm -rf "$bac"
        BASH
        , [
            'MODULE_SH' => ShellProbe::installModuleScript('10-laravel-core'),
        ], 60);

    // Refus bruyant, et le secret de l'opérateur est TOUJOURS là.
    expect($result['output'])->not->toContain('REFUS_STATUS=0');
    expect($result['output'])->toContain('ENV=[APP_KEY=secret-de-l-operateur]');
    expect($result['output'])->toContain('REFUS_SIGNALE=oui');

    // Anti-vacuité : la fonction fait bien son travail quand elle le peut —
    // sinon « le .env n'a pas changé » serait vrai pour la mauvaise raison.
    expect($result['output'])->toContain('OK_STATUS=0');
    expect($result['output'])->toContain('ENV_APRES=[APP_ENV=local');
    expect($result['output'])->toContain('SAUVEGARDES=1');
});

it('une route /health impossible à créer FAIT ÉCHOUER l’installation', function (): void {
    // 🔴 RÉGRESSION INTRODUITE PAR CETTE STORY (relevé revue 1) : l'absence de
    // `routes/web.php` était devenue un `log_warn` + `return 0`. Sans cette
    // route, le HEALTHCHECK DOCKER du conteneur php ne répond jamais — le
    // service démarre et n'est jamais déclaré sain, pour un avertissement dans
    // un journal de /tmp que personne ne lit.
    $result = ShellProbe::run(<<<'BASH'
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        export LOG_FILE="$bac/log"
        mkdir -p "$bac/sans-routes" "$bac/avec-routes/routes"
        printf "<?php\n" > "$bac/avec-routes/routes/web.php"

        source "$MODULE_SH"

        # ── 1) routes/web.php absent : l'installation DOIT échouer ──────────
        cd "$bac/sans-routes"
        statut=0
        ( create_healthcheck_route ) > "$bac/sortie" 2>&1 || statut=$?
        echo "ABSENT_STATUS=$statut"
        grep -q "healthcheck Docker" "$bac/sortie" && echo "ABSENT_SIGNALE=oui" || echo "ABSENT_SIGNALE=non"
        # …et surtout, il ne FABRIQUE pas un routes/web.php ne contenant que
        # la route de santé (comportement d'origine, pire encore).
        [ -e "$bac/sans-routes/routes" ] && echo "FABRIQUE=oui" || echo "FABRIQUE=non"

        # ── 2) Anti-vacuité : présent ⇒ la route est ajoutée, une seule fois ─
        cd "$bac/avec-routes"
        statut=0
        ( create_healthcheck_route ) > "$bac/sortie-ok" 2>&1 || statut=$?
        echo "PRESENT_STATUS=$statut"
        echo "OCCURRENCES=$(grep -c "'/health'" routes/web.php | tr -d ' ')"

        statut=0
        ( create_healthcheck_route ) > "$bac/sortie-idem" 2>&1 || statut=$?
        echo "IDEM_STATUS=$statut"
        echo "OCCURRENCES_IDEM=$(grep -c "'/health'" routes/web.php | tr -d ' ')"

        rm -rf "$bac"
        BASH
        , [
            'MODULE_SH' => ShellProbe::installModuleScript('10-laravel-core'),
        ], 60);

    expect($result['output'])->not->toContain('ABSENT_STATUS=0');
    expect($result['output'])->toContain('ABSENT_SIGNALE=oui');
    expect($result['output'])->toContain('FABRIQUE=non');

    expect($result['output'])->toContain('PRESENT_STATUS=0');
    expect($result['output'])->toContain('OCCURRENCES=1');
    // Idempotent : un second passage n'ajoute pas une seconde route.
    expect($result['output'])->toContain('IDEM_STATUS=0');
    expect($result['output'])->toContain('OCCURRENCES_IDEM=1');
});

it('le rapport d’échec en simulation compte TOUS les modules franchis', function (): void {
    // 🔴 RÉGRESSION DU DÉCOUPAGE EN TROIS COMPTEURS (relevé passe 2) :
    // `show_error_report` ne recevait que `simulated_modules`. Un seul module
    // étant *aware*, un échec au 11ᵉ annonçait « aucun module réussi avant
    // l'échec » alors que dix avaient été franchis — l'opérateur croyait devoir
    // tout reprendre.
    $result = ShellProbe::run(orchestrateurAvecJournal(<<<'BASH'
        DRY_RUN=true

        execute_module() {
            echo "$1" >> "$journal"
            [ "$1" = "99-finalize" ] && return 5
            return 0
        }

        statut=0
        run_installation > "$bac/sortie" 2>&1 || statut=$?
        echo "STATUS=$statut"
        # Ancré en FIN de ligne : `show_installation_config` imprime elle aussi
        # des « ✅ <module>: <description> ». Seul le rapport d'échec liste des
        # identifiants NUS.
        echo "AVANT_ECHEC=$(sed 's/\x1b\[[0-9;]*m//g' "$bac/sortie" | grep -acE '✅ [0-9]{2}-[a-z0-9-]+[[:space:]]*$' | tr -d ' ')"
        grep -q "Installation échouée au module: 99-finalize" "$bac/sortie" \
            && echo "NOMME=oui" || echo "NOMME=non"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    // Le code du module remonte…
    expect($result['output'])->toContain('STATUS=5');
    expect($result['output'])->toContain('NOMME=oui');
    // …et les DIX modules franchis avant lui sont listés, pas le seul *aware*.
    expect($result['output'])->toContain('AVANT_ECHEC=10');
});

it('--dry-run --force ANNONCE les suppressions de sentinelles qu’il ne fait pas', function (): void {
    // 🔴 LE PLAN OMETTAIT LES `rm -f "$sentinel"` (relevé passe 2) : il décrivait
    // donc une exécution qui n'était pas celle qu'`install.sh --force` aurait
    // menée. Un plan incomplet sur les SUPPRESSIONS, dans une story dont c'est
    // l'objet même.
    $result = ShellProbe::run(orchestrateurAvecJournal(<<<'BASH'
        for module in 00-prerequisites 05-composer-setup 10-laravel-core; do
            : > "$INSTALL_STATE_DIR/$module-done"
        done

        avant="$(find "$INSTALL_STATE_DIR" -type f | sort | md5sum)"

        DRY_RUN=true
        FORCE=true
        run_installation > "$bac/sortie" 2>&1 || true

        apres="$(find "$INSTALL_STATE_DIR" -type f | sort | md5sum)"
        [ "$avant" = "$apres" ] && echo "ETAT=INTACT" || echo "ETAT=MODIFIE"
        echo "ANNONCES=$(grep -ac '\[DRY\] rm -f ' "$bac/sortie" | tr -d ' ')"

        # Anti-vacuité : hors simulation, les mêmes sentinelles sont EFFACÉES
        # (puis réécrites par ensure_idempotent — c'est le rejeu forcé).
        DRY_RUN=false
        FORCE=true
        run_installation > /dev/null 2>&1 || true
        # 11 sentinelles + l'horodatage `started-at` que le rejeu complet
        # réécrit : c'est l'état d'une installation réelle menée à son terme.
        echo "REEL_SENTINELLES=$(find "$INSTALL_STATE_DIR" -type f -name '*-done' | wc -l | tr -d ' ')"
        [ -f "$INSTALL_STATE_DIR/started-at" ] && echo "REEL_HORODATAGE=oui" || echo "REEL_HORODATAGE=non"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    // Les trois sentinelles présentes sont ANNONCÉES condamnées…
    expect($result['output'])->toContain('ANNONCES=3');
    // …et aucune n'a bougé.
    expect($result['output'])->toContain('ETAT=INTACT');
    // Anti-vacuité : le rejeu réel repose bien les 11 sentinelles ET
    // l'horodatage — donc les `rm -f` annoncés plus haut correspondent à un
    // effet qui existe vraiment hors simulation.
    expect($result['output'])->toContain('REEL_SENTINELLES=' . count(ShellProbe::installModules()));
    expect($result['output'])->toContain('REEL_HORODATAGE=oui');
});

it('--skip-prereq entre dans un compteur, au lieu de disparaître du rapport', function (): void {
    // 🔴 QUATRIÈME POPULATION OUBLIÉE (relevé passe 2) : un module écarté par
    // `--skip-prereq` n'entrait dans AUCUN des trois compteurs. Le rapport
    // cessait donc de rendre compte de toute la liste — un module disparaissait
    // sans trace, dans le rapport même qui existe pour dire ce qui serait fait.
    $result = ShellProbe::run(orchestrateurAvecJournal(<<<'BASH'
        DRY_RUN=true
        SKIP_PREREQUISITES=true
        run_installation > "$bac/sortie" 2>&1 || true

        sed 's/\x1b\[[0-9;]*m//g' "$bac/sortie" | grep -a 'Modules ' | sed 's/^.*] //'
        grep -q '🚫 00-prerequisites' "$bac/sortie" && echo "LISTE=oui" || echo "LISTE=non"
        BASH), [
        'INSTALL_SH' => ShellProbe::installScript(),
    ], 60);

    $total = count(ShellProbe::installModules());

    // 1 simulé (10-laravel-core) + 9 annoncés + 0 déjà franchi + 1 écarté = 11.
    expect($result['output'])->toContain('🔢 Modules réellement simulés: 1');
    expect($result['output'])->toContain('🔢 Modules annoncés sans exécution: ' . ($total - 2));
    expect($result['output'])->toContain('🔢 Modules déjà franchis (sentinelle): 0');
    expect($result['output'])->toContain('🔢 Modules écartés par une option (--skip-prereq): 1');
    expect($result['output'])->toContain('LISTE=oui');
});

// =============================================================================
// La porte d'entrée `make` — mesurée sur des EFFETS
// =============================================================================

/**
 * Bac à sable `make` : un `docker` et un `$(MAKE)` remplacés par des témoins.
 *
 * ⛔ POURQUOI CE HARNAIS PLUTÔT QU'UN `make -n`. `make -n` n'exécute rien : il
 * ne peut pas attraper un effet de bord, et c'est exactement ce qui a laissé
 * passer, tous gardes au vert, une recette qui `chown -R` et `chmod -R`
 * l'application de l'opérateur sous `DRY_RUN=true`.
 *
 * Le stub `docker` REJOUE le contenu de chaque `docker exec` dans un bac à
 * sable (`/var/www/html` → cible jetable). Une seule exception, explicite :
 * l'étape qui lance `install.sh` est ENREGISTRÉE sans être rejouée — c'est le
 * sujet des autres tests de ce fichier, pas de celui-ci.
 *
 * Le stub `$(MAKE)` est un témoin : `fix-permissions-host` fait un
 * `sudo chown -R ./src`, qu'aucun test ne doit déclencher. Sa NON-invocation se
 * mesure donc par l'absence du témoin, jamais en le laissant tourner.
 */
function harnaisMake(string $corps): string
{
    return <<<BASH
        set -e
        bac="\$(mktemp -d)"
        case "\$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
        esac

        mkdir -p "\$bac/bin"
        export JOURNAL="\$bac/journal"
        export TEMOIN_MAKE="\$bac/temoin-make"
        export SANDBOX="\$bac/html"
        export REPO="\$REPO_ROOT"
        : > "\$JOURNAL"

        # Cible : une application, avec des modes distinctifs qu'un `chmod -R`
        # écraserait.
        mkdir -p "\$SANDBOX/storage/logs" "\$SANDBOX/bootstrap/cache" "\$SANDBOX/vendor/bin"
        printf '#!/usr/bin/env php\\n' > "\$SANDBOX/artisan"
        printf 'contenu\\n' > "\$SANDBOX/composer.json"
        chmod 600 "\$SANDBOX/artisan"
        chmod 600 "\$SANDBOX/composer.json"
        chmod 700 "\$SANDBOX/storage"

        cat > "\$bac/bin/docker" <<'STUB'
        #!/bin/bash
        printf 'DOCKER %s\\n' "\$*" >> "\$JOURNAL"
        case "\$1" in
            ps)
                case "\$*" in
                    *--format*) printf 'laravel-app_php\\nlaravel-app_node\\n' ;;
                    *) echo "stub-container-id" ;;
                esac
                exit 0
                ;;
            exec)
                charge="\${@: -1}"
                case "\$charge" in
                    *install.sh*)
                        printf 'INSTALL_SH %s\\n' "\$charge" >> "\$JOURNAL"
                        exit 0
                        ;;
                esac
                printf 'REJOUE %s\\n' "\$charge" >> "\$JOURNAL"
                bash -c "\${charge//\\/var\\/www\\/html/\$SANDBOX}"
                exit \$?
                ;;
        esac
        exit 0
        STUB
        chmod +x "\$bac/bin/docker"

        # `claude mcp add …` modifierait la configuration MCP RÉELLE de
        # l'opérateur : le binaire est remplacé, jamais laissé au hasard du PATH.
        printf '#!/bin/bash\\nprintf "CLAUDE %%s\\\\n" "\$*" >> "\$JOURNAL"\\nexit 0\\n' > "\$bac/bin/claude"
        chmod +x "\$bac/bin/claude"

        printf '#!/bin/bash\\nprintf "SUBMAKE %%s\\\\n" "\$*" >> "\$TEMOIN_MAKE"\\nexit 0\\n' > "\$bac/bin/submake"
        chmod +x "\$bac/bin/submake"

        export PATH="\$bac/bin:\$PATH"

        modes() { find "\$SANDBOX" -exec stat -c '%n %a %U:%G' {} + | sort | md5sum; }

        lance_make() {
            ( cd "\$REPO" && make "\$@" COMPOSE_PROJECT_NAME=laravel-app MAKE="\$bac/bin/submake" ) \\
                > "\$bac/make-sortie" 2>&1
        }

        {$corps}

        rm -rf "\$bac"
        BASH;
}

/**
 * Bac à sable dont la cible EST une application Laravel.
 *
 * ⛔ SANS ÇA, LA MOITIÉ DU MODULE N'EST PAS ATTEINTE. `is_laravel_installed`
 * rend faux sur un répertoire de bric-à-brac, et la simulation s'arrête avant
 * le patch du skeleton, les permissions et la route de santé — c'est-à-dire
 * avant les commandes qui MUTENT une vraie installation.
 */
function cibleLaravelShaped(string $corps): string
{
    return <<<BASH
        set -e
        bac="\$(mktemp -d)"
        case "\$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
        esac

        cible="\$bac/cible"
        mkdir -p "\$cible/bootstrap/cache" "\$cible/config" "\$cible/routes" \\
                 "\$cible/storage/logs" "\$cible/vendor/phpunit/phpunit"

        printf '#!/usr/bin/env php\\n<?php\\n' > "\$cible/artisan"
        chmod 644 "\$cible/artisan"
        printf '{"require":{"laravel/framework":"^12.0"}}\\n' > "\$cible/composer.json"
        printf '<?php return [];\\n' > "\$cible/bootstrap/app.php"
        printf '<?php return [];\\n' > "\$cible/config/app.php"
        printf "<?php\\nRoute::get('/', fn () => 'ok');\\n" > "\$cible/routes/web.php"
        printf '<env name="DB_CONNECTION" value="sqlite"/>\\n<env name="DB_DATABASE" value=":memory:"/>\\n' \\
            > "\$cible/phpunit.xml"
        chmod 600 "\$cible/phpunit.xml"
        # ⚠️ PAS d'`APP_KEY` : avec une clé posée, `generate_application_key` sort
        # par sa branche « clé existante » et le site routé n'est pas atteint.
        printf 'APP_ENV=local\\n' > "\$cible/.env"
        chmod 600 "\$cible/.env"

        export INSTALL_STATE_DIR="\$bac/etat"
        mkdir -p "\$INSTALL_STATE_DIR"

        empreinte() {
            {
                find "\$cible" | sort
                find "\$cible" -type f -exec cat {} +
                find "\$cible" -exec stat -c '%n %a %U:%G' {} + | sort
            } | md5sum
        }

        modes() { find "\$cible" -exec stat -c '%n %a %U:%G' {} + | sort | md5sum; }

        {$corps}

        rm -rf "\$bac"
        BASH;
}

it('make install-laravel DRY_RUN=true ne MUTE rien: ni permissions, ni sudo, ni MCP', function (): void {
    // 🔴 CONSTAT STRUCTURANT DE LA REVUE 1. `install-laravel` est une recette en
    // 5 étapes ; `DRY_RUN=true` n'atteignait que l'étape 1/5. Les étapes 2 à 5
    // s'exécutaient ensuite POUR DE VRAI : `chown -R www-data:www-data
    // /var/www/html`, deux `find -exec chmod 775/664`, `chmod +x artisan`,
    // `chmod -R 775 storage bootstrap/cache`, puis `fix-permissions-host` EN
    // SUDO côté hôte. La porte d'entrée de la story réintroduisait la classe
    // d'effet de bord qu'elle venait de retirer de `validate_arguments`.
    $result = ShellProbe::run(harnaisMake(<<<'BASH'
        avant="$(modes)"

        statut=0
        lance_make install-laravel DRY_RUN=true || statut=$?
        echo "SIM_STATUS=$statut"

        apres="$(modes)"
        [ "$avant" = "$apres" ] && echo "SIM_MODES=INTACTS" || echo "SIM_MODES=MODIFIES"

        echo "SIM_REJOUES=$(grep -c '^REJOUE ' "$JOURNAL" | tr -d ' ')"
        echo "SIM_INSTALL_SH=$(grep -c '^INSTALL_SH ' "$JOURNAL" | tr -d ' ')"
        echo "SIM_SUDO=[$(cat "$TEMOIN_MAKE" 2>/dev/null)]"
        echo "SIM_CLAUDE=$(grep -c '^CLAUDE ' "$JOURNAL" | tr -d ' ')"
        grep -qE '^(REJOUE|DOCKER).*(chown|chmod)' "$JOURNAL" && echo "SIM_PERMS=oui" || echo "SIM_PERMS=non"

        # ── Anti-vacuité : la MÊME recette, sans DRY_RUN, mute bel et bien ──
        : > "$JOURNAL"
        : > "$TEMOIN_MAKE"
        avant="$(modes)"

        statut=0
        lance_make install-laravel || statut=$?
        echo "REEL_STATUS=$statut"

        apres="$(modes)"
        [ "$avant" = "$apres" ] && echo "REEL_MODES=INTACTS" || echo "REEL_MODES=MODIFIES"

        echo "REEL_REJOUES=$(grep -c '^REJOUE ' "$JOURNAL" | tr -d ' ')"
        grep -q 'SUBMAKE fix-permissions-host' "$TEMOIN_MAKE" && echo "REEL_SUDO=oui" || echo "REEL_SUDO=non"
        echo "REEL_CLAUDE=$(grep -c '^CLAUDE ' "$JOURNAL" | tr -d ' ')"
        BASH), [
        'REPO_ROOT' => ShellProbe::repoRoot(),
    ], 180);

    // ── Sous simulation : l'étape 1/5 seule, et rien d'autre ────────────────
    expect($result['output'])->toContain('SIM_STATUS=0');
    expect($result['output'])->toContain('SIM_MODES=INTACTS');
    expect($result['output'])->toContain('SIM_INSTALL_SH=1');
    // Aucune autre commande n'a été rejouée dans la cible.
    expect($result['output'])->toContain('SIM_REJOUES=0');
    expect($result['output'])->toContain('SIM_PERMS=non');
    // `fix-permissions-host` (sudo chown -R ./src) n'a PAS été appelé.
    expect($result['output'])->toContain('SIM_SUDO=[]');
    // …ni `claude mcp add`, qui modifierait la configuration de l'opérateur.
    expect($result['output'])->toContain('SIM_CLAUDE=0');

    // ── Anti-vacuité : sans DRY_RUN, les quatre effets sont là ──────────────
    // Sans cette passe, un harnais cassé (stub jamais atteint, cible vide)
    // rendrait les six assertions ci-dessus vertes sans rien mesurer.
    expect($result['output'])->toContain('REEL_STATUS=0');
    expect($result['output'])->toContain('REEL_MODES=MODIFIES');
    expect($result['output'])->toContain('REEL_REJOUES=1');
    expect($result['output'])->toContain('REEL_SUDO=oui');
    expect($result['output'])->toContain('REEL_CLAUDE=1');
});

it('make install-laravel-prod DRY_RUN=true ne MUTE rien non plus', function (): void {
    // Même défaut, même correctif : le bloc de permissions qui suit les cinq
    // `install.sh --only` mute l'arbre applicatif au lieu de le simuler.
    $result = ShellProbe::run(harnaisMake(<<<'BASH'
        avant="$(modes)"

        statut=0
        lance_make install-laravel-prod DRY_RUN=true || statut=$?
        echo "SIM_STATUS=$statut"

        apres="$(modes)"
        [ "$avant" = "$apres" ] && echo "SIM_MODES=INTACTS" || echo "SIM_MODES=MODIFIES"

        echo "SIM_REJOUES=$(grep -c '^REJOUE ' "$JOURNAL" | tr -d ' ')"
        echo "SIM_INSTALL_SH=$(grep -c '^INSTALL_SH ' "$JOURNAL" | tr -d ' ')"

        # ⛔ CHACUNE des cinq invocations porte le drapeau — jamais la première
        # seule. Retirer `$(INSTALL_ONLY_FLAGS)` d'UNE ligne (« 20-database »,
        # celle des migrations) laissait le garde précédent VERT.
        for module in 10-laravel-core 20-database 30-packages-prod 35-configure-spatie-packages 99-finalize; do
            if grep -qF -- "--only $module --dry-run" "$JOURNAL"; then
                echo "PORTE=$module"
            fi
        done

        # ── Anti-vacuité ────────────────────────────────────────────────────
        : > "$JOURNAL"
        avant="$(modes)"

        statut=0
        lance_make install-laravel-prod || statut=$?
        echo "REEL_STATUS=$statut"

        apres="$(modes)"
        [ "$avant" = "$apres" ] && echo "REEL_MODES=INTACTS" || echo "REEL_MODES=MODIFIES"
        echo "REEL_REJOUES=$(grep -c '^REJOUE ' "$JOURNAL" | tr -d ' ')"
        BASH), [
        'REPO_ROOT' => ShellProbe::repoRoot(),
    ], 180);

    expect($result['output'])->toContain('SIM_STATUS=0');
    expect($result['output'])->toContain('SIM_MODES=INTACTS');
    expect($result['output'])->toContain('SIM_INSTALL_SH=5');
    expect($result['output'])->toContain('SIM_REJOUES=0');

    foreach (['10-laravel-core', '20-database', '30-packages-prod', '35-configure-spatie-packages', '99-finalize'] as $module) {
        expect($result['output'])->toContain('PORTE=' . $module);
    }

    expect($result['output'])->toContain('REEL_STATUS=0');
    expect($result['output'])->toContain('REEL_MODES=MODIFIES');
    expect($result['output'])->toContain('REEL_REJOUES=1');
});

it('make relaie --resume-from à l’invocation nominale, et JAMAIS aux --only', function (): void {
    // La sixième invocation, et le refus de la combinaison contradictoire
    // `--only X --resume-from Y` (précédence non spécifiée).
    $result = ShellProbe::run(harnaisMake(<<<'BASH'
        statut=0
        lance_make install-laravel DRY_RUN=true RESUME_FROM=20-database || statut=$?
        echo "STATUS=$statut"
        grep -qF -- "install.sh --dry-run --resume-from 20-database" "$JOURNAL" \
            && echo "RELAIS=oui" || echo "RELAIS=non"

        # Contre-épreuve : sans les variables, aucun drapeau n'est ajouté. Un
        # pass-through toujours actif serait pire que pas de pass-through.
        : > "$JOURNAL"
        lance_make install-laravel DRY_RUN=true || true
        grep -q -- "--resume-from" "$JOURNAL" && echo "SANS=fuite" || echo "SANS=propre"

        # `install-laravel-prod` REFUSE `RESUME_FROM`, à l'analyse du Makefile.
        statut=0
        ( cd "$REPO" && make -n install-laravel-prod RESUME_FROM=20-database ) > "$bac/prod" 2>&1 || statut=$?
        echo "PROD_STATUS=$statut"
        grep -q "install-laravel RESUME_FROM=" "$bac/prod" && echo "PROD_ORIENTE=oui" || echo "PROD_ORIENTE=non"

        # …et un module INCONNU est refusé avant toute exécution.
        statut=0
        ( cd "$REPO" && make -n install-laravel RESUME_FROM=pas-un-module ) > "$bac/inconnu" 2>&1 || statut=$?
        echo "INCONNU_STATUS=$statut"
        grep -q "n'est pas un module connu" "$bac/inconnu" && echo "INCONNU_ORIENTE=oui" || echo "INCONNU_ORIENTE=non"

        # 🔴 `%` est un JOKER pour `$(filter)` : `RESUME_FROM=%` passait
        # l'appartenance à la liste des modules. L'appartenance est désormais
        # testée par `findstring` sur une liste délimitée.
        statut=0
        ( cd "$REPO" && make -n install-laravel RESUME_FROM=% ) > /dev/null 2>&1 || statut=$?
        echo "JOKER_STATUS=$statut"
        BASH), [
        'REPO_ROOT' => ShellProbe::repoRoot(),
    ], 180);

    expect($result['output'])->toContain('STATUS=0');
    expect($result['output'])->toContain('RELAIS=oui');
    expect($result['output'])->toContain('SANS=propre');

    expect($result['output'])->not->toContain('PROD_STATUS=0');
    expect($result['output'])->toContain('PROD_ORIENTE=oui');

    expect($result['output'])->not->toContain('INCONNU_STATUS=0');
    expect($result['output'])->toContain('INCONNU_ORIENTE=oui');
    expect($result['output'])->not->toContain('JOKER_STATUS=0');
});

it('make VALIDE la liste des modules contre INSTALL_MODULES, lue sur disque', function (): void {
    // La validation de `RESUME_FROM` côté make s'appuie sur une liste EXTRAITE
    // de `scripts/install.sh`. Ré-écrite en dur, elle divergerait au premier
    // module ajouté ou renommé — sans que rien ne rougisse. Ce test prouve que
    // les deux listes désignent le même ensemble, dans les deux sens.
    $modules = ShellProbe::installModules();

    expect($modules)
        ->not->toBeEmpty();

    $script = <<<'BASH'
        cd "$REPO_ROOT"
        for module in $MODULES; do
            statut=0
            make -n install-laravel RESUME_FROM="$module" > /dev/null 2>&1 || statut=$?
            echo "MODULE $module=$statut"
        done
        statut=0
        make -n install-laravel RESUME_FROM="module-inconnu-2-3" > /dev/null 2>&1 || statut=$?
        echo "INCONNU=$statut"
        BASH;

    $result = ShellProbe::run($script, [
        'REPO_ROOT' => ShellProbe::repoRoot(),
        'MODULES' => implode(' ', $modules),
    ], 180);

    foreach ($modules as $module) {
        expect($result['output'])->toContain('MODULE ' . $module . '=0');
    }

    // Anti-vacuité : un `filter` toujours vrai rendrait les 11 lignes ci-dessus
    // vertes. Un identifiant absent doit être refusé.
    expect($result['output'])->not->toContain('INCONNU=0');
});

it('make REFUSE une valeur de DRY_RUN qui n’est ni true ni false', function (): void {
    // 🔴 `ifeq ($(DRY_RUN),true)` est une égalité stricte SANS `else` :
    // `DRY_RUN=1`, `yes` ou `TRUE` retombaient silencieusement dans la branche
    // « pas de simulation » et lançaient une INSTALLATION RÉELLE pendant que
    // l'opérateur croyait simuler. Le pire mode de défaillance possible pour ce
    // drapeau : silencieux, et dans le sens destructeur.
    $result = ShellProbe::run(<<<'BASH'
        cd "$REPO_ROOT"

        essai() {
            local statut=0
            make -n install-laravel DRY_RUN="$1" > /dev/null 2>&1 || statut=$?
            echo "[$1]=$statut"
        }

        essai "true"
        essai "false"
        essai "1"
        essai "yes"
        essai "TRUE"
        essai "0"
        essai "oui"
        # 🔴 `%` EST UN JOKER POUR `$(filter)` : `DRY_RUN=%` passait la
        # validation, puis n'était égal ni à `true` ni à `false` — donc
        # installation RÉELLE en silence. La comparaison est désormais
        # littérale (`ifeq`).
        essai "%"

        # Une espace finale ne doit ni casser, ni basculer en installation
        # réelle : `$(strip)` la mange, la valeur reste « true ».
        sortie="$(mktemp)"
        case "$sortie" in
            /tmp/*) ;;
            *) echo "SORTIE_HORS_TMP=[$sortie]"; exit 9 ;;
        esac
        statut=0
        make -n install-laravel DRY_RUN="true " > "$sortie" 2>&1 || statut=$?
        echo "[espace]=$statut"
        grep -q -- "--dry-run" "$sortie" && echo "ESPACE=simule" || echo "ESPACE=reel"
        rm -f "$sortie"
        BASH
        , [
            'REPO_ROOT' => ShellProbe::repoRoot(),
        ], 120);

    // Les deux seules valeurs acceptées.
    expect($result['output'])->toContain('[true]=0');
    expect($result['output'])->toContain('[false]=0');

    // Toutes les autres sont refusées bruyamment.
    foreach (['1', 'yes', 'TRUE', '0', 'oui', '%'] as $valeur) {
        expect($result['output'])->not->toContain('[' . $valeur . ']=0');
    }

    // …et `true ` simule, il ne bascule pas en installation réelle silencieuse.
    expect($result['output'])->toContain('[espace]=0');
    expect($result['output'])->toContain('ESPACE=simule');
});

it('make REFUSE DRY_RUN=true sur CHACUNE des chaînes composites, y compris une NEUVE', function (): void {
    // 🔴 LE CONSTAT DE LA PASSE 1 N'ÉTAIT PAS CONSOMMÉ (relevé passe 2).
    // Le divorce test↔Makefile était bien fermé (la liste se lisait sur
    // disque), mais la liste elle-même restait une ÉNUMÉRATION : ajouter
    // `install-dev-turbo: build up-dev install-laravel npm-install` au Makefile
    // produisait une cible ACCEPTÉE sous `DRY_RUN=true` — elle bâtit des
    // images, démarre des conteneurs, puis lance une « simulation » — et la
    // suite restait verte. Une énumération ne garde pas ce qu'elle ignore.
    //
    // La composite-ness est désormais DÉRIVÉE du graphe de dépendances. Ce test
    // le prouve en ajoutant réellement une cible et en relançant make.
    $composites = ShellProbe::makefileComposites();

    expect($composites)
        ->not->toBeEmpty();
    // Anti-vacuité : la dérivation doit retrouver les chaînes connues.
    foreach (['install', 'install-dev', 'install-dev-full', 'install-prod', 'install-prod-fast'] as $connue) {
        expect($composites)->toContain($connue);
    }
    // …et elle en trouve une que l'énumération manuelle avait MANQUÉE.
    expect($composites)
        ->toContain('setup-quick');

    $result = ShellProbe::run(<<<'BASH'
        cd "$REPO_ROOT"

        for cible in $CIBLES; do
            statut=0
            sortie="$(make -n "$cible" DRY_RUN=true 2>&1)" || statut=$?
            echo "STATUT_$cible=$statut"
            case "$sortie" in
                *"install-laravel DRY_RUN=true"*) echo "ORIENTE_$cible=oui" ;;
                *) echo "ORIENTE_$cible=non" ;;
            esac
        done

        # ⛔ LA CIBLE NEUVE : elle n'existe dans aucune liste, seulement dans le
        # graphe. C'est le scénario exact du constat.
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac
        cp Makefile "$bac/Makefile-turbo"
        printf '\n.PHONY: install-dev-turbo\ninstall-dev-turbo: build up-dev install-laravel npm-install ## Turbo\n\t@echo turbo\n' \
            >> "$bac/Makefile-turbo"

        statut=0
        sortie="$(make -f "$bac/Makefile-turbo" -n install-dev-turbo DRY_RUN=true 2>&1)" || statut=$?
        echo "TURBO_STATUT=$statut"
        case "$sortie" in
            *"install-laravel DRY_RUN=true"*) echo "TURBO_ORIENTE=oui" ;;
            *) echo "TURBO_ORIENTE=non" ;;
        esac

        # Anti-vacuité de la sonde elle-même : la MÊME cible neuve, SANS
        # DRY_RUN, est acceptée. Sans cette passe, un Makefile cassé par la
        # copie rendrait « TURBO_STATUT != 0 » pour la mauvaise raison.
        statut=0
        make -f "$bac/Makefile-turbo" -n install-dev-turbo > /dev/null 2>&1 || statut=$?
        echo "TURBO_SANS_DRY=$statut"

        rm -rf "$bac"

        # Anti-vacuité : la cible NON composite passe, elle. Sans cette passe,
        # un `$(error)` inconditionnel rendrait ce test vert.
        statut=0
        make -n install-laravel DRY_RUN=true > /dev/null 2>&1 || statut=$?
        echo "STATUT_install-laravel=$statut"
        BASH
        , [
            'REPO_ROOT' => ShellProbe::repoRoot(),
            'CIBLES' => implode(' ', $composites),
        ], 240);

    foreach ($composites as $cible) {
        expect($result['output'])->not->toContain('STATUT_' . $cible . '=0');
        expect($result['output'])->toContain('ORIENTE_' . $cible . '=oui');
    }

    // La cible NEUVE est refusée, et orientée vers la bonne sortie.
    expect($result['output'])->not->toContain('TURBO_STATUT=0');
    expect($result['output'])->toContain('TURBO_ORIENTE=oui');
    // …tout en restant utilisable sans le drapeau.
    expect($result['output'])->toContain('TURBO_SANS_DRY=0');

    expect($result['output'])->toContain('STATUT_install-laravel=0');
});

it('DRY_RUN et RESUME_FROM ne TUENT pas les cibles génériques', function (): void {
    // 🔴 RÉGRESSION INTRODUITE PAR LE CORRECTIF DE LA PASSE 1 (relevé passe 2).
    // `DRY_RUN` et `RESUME_FROM` sont des noms GÉNÉRIQUES. Exportés dans le
    // shell de l'opérateur — ou hérités d'un CI — une validation évaluée au
    // PARSE GLOBAL faisait sortir en 2 des cibles qui n'ont rien à voir :
    // mesuré, `DRY_RUN=1 make help` et `RESUME_FROM=x make status` tuaient le
    // Makefile entier. Le garde doit être porté par les cibles d'installation,
    // comme le fait déjà le garde composite avec `MAKECMDGOALS`.
    $result = ShellProbe::run(<<<'BASH'
        cd "$REPO_ROOT"

        for cible in help status ps-profiles; do
            statut=0
            DRY_RUN=1 make -n "$cible" > /dev/null 2>&1 || statut=$?
            echo "DRY_$cible=$statut"
            statut=0
            RESUME_FROM=pas-un-module make -n "$cible" > /dev/null 2>&1 || statut=$?
            echo "RESUME_$cible=$statut"
        done

        # Anti-vacuité : sur une cible d'INSTALLATION, les mêmes valeurs sont
        # refusées. Sans cette passe, un garde entièrement retiré passerait.
        statut=0
        DRY_RUN=1 make -n install-laravel > /dev/null 2>&1 || statut=$?
        echo "DRY_install-laravel=$statut"
        statut=0
        RESUME_FROM=pas-un-module make -n install-laravel > /dev/null 2>&1 || statut=$?
        echo "RESUME_install-laravel=$statut"
        BASH
        , [
            'REPO_ROOT' => ShellProbe::repoRoot(),
        ], 120);

    foreach (['help', 'status', 'ps-profiles'] as $cible) {
        expect($result['output'])->toContain('DRY_' . $cible . '=0');
        expect($result['output'])->toContain('RESUME_' . $cible . '=0');
    }

    expect($result['output'])->not->toContain('DRY_install-laravel=0');
    expect($result['output'])->not->toContain('RESUME_install-laravel=0');
});

// =============================================================================
// L'engagement d'audit : la liste *aware*, et le routage qu'elle promet
// =============================================================================

it('DRY_RUN_AWARE_MODULES ne nomme que des modules RÉELS, et reste court', function (): void {
    // ⛔ Inscrire un module dans cette liste engage l'audit du module ENTIER.
    // Une entrée mal orthographiée ne ferait rien rougir : le module resterait
    // simplement en annonce-et-saut, et l'audit payé serait perdu sans bruit.
    $aware = ShellProbe::dryRunAwareModules();
    $modules = ShellProbe::installModules();

    expect($aware)
        ->not->toBeEmpty();
    expect($aware)
        ->toBe(['10-laravel-core']);

    foreach ($aware as $module) {
        expect($modules)->toContain($module);
        expect(is_file(ShellProbe::installModuleScript($module)))->toBeTrue();
    }
});

/**
 * Retire le commentaire de fin de ligne d'une ligne shell, en respectant les
 * guillemets.
 *
 * 🔴 SANS ÇA, LE SCAN EST CONTOURNABLE PAR UN COMMENTAIRE (relevé revue 2) :
 * unrouter une ligne à effet puis ajouter « # run_cmd retiré » en fin de ligne
 * la faisait compter comme ROUTÉE. Pour les parties du module que la fixture
 * n'atteint pas — `install_laravel_via_composer`, `adapt_environment_configuration` —
 * ce scan est le SEUL garde ; le rendre satisfaisable par un commentaire, c'est
 * ne rien garder du tout.
 */
function codeShellSeul(string $ligne): string
{
    $dansSimple = false;
    $dansDouble = false;
    $longueur = strlen($ligne);

    for ($i = 0; $i < $longueur; $i++) {
        $c = $ligne[$i];

        if ($c === '\\' && $dansSimple === false) {
            $i++;

            continue;
        }

        if ($c === "'" && ! $dansDouble) {
            $dansSimple = ! $dansSimple;

            continue;
        }

        if ($c === '"' && ! $dansSimple) {
            $dansDouble = ! $dansDouble;

            continue;
        }

        // Un `#` ne commence un commentaire qu'en début de mot, hors guillemets.
        if ($c === '#' && ! $dansSimple && ! $dansDouble && ($i === 0 || $ligne[$i - 1] === ' ' || $ligne[$i - 1] === "\t")) {
            return rtrim(substr($ligne, 0, $i));
        }
    }

    return rtrim($ligne);
}

it('aucune commande à effet de 10-laravel-core n’échappe à run_cmd', function (): void {
    // 🔴 LE GARDE PRÉCÉDENT NE GARDAIT RIEN (relevé revue 1) :
    // `substr_count($source, 'run_cmd') > 20` sur un fichier qui en compte 67,
    // et `substr_count` compte aussi les COMMENTAIRES — un fichier où plus
    // aucun appel réel ne subsisterait restait vert.
    //
    // Le vrai invariant n'est pas un compte, c'est une ABSENCE : aucune ligne de
    // CODE n'invoque une commande à effet sans passer par `run_cmd`. Retirer
    // `run_cmd` d'un seul site fait basculer cette ligne dans les suspects, donc
    // rougir ; en ajouter un non routé aussi.
    //
    // ⚠️ LE SCAN PORTE SUR DU CODE, PAS SUR LA LIGNE BRUTE — voir
    // `codeShellSeul()` : un `# run_cmd` en fin de ligne suffisait à le berner.
    $lignes = explode("\n", RepoFile::read('scripts/install/10-laravel-core.sh'));

    $effet = '/^(rm|mkdir|chmod|chown|cp|mv|sed|composer|php|touch|ln|cat|echo|printf|python3|find)\b/';

    $suspects = [];
    $routees = 0;

    foreach ($lignes as $ligne) {
        $code = trim(codeShellSeul($ligne));

        if ($code === '') {
            continue;
        }

        if (preg_match('/\brun_cmd(_quiet|_logged)?\b/', $code) === 1) {
            $routees++;

            continue;
        }

        // `if !`, `elif`, `!` en tête ne changent pas la nature de la commande.
        $commande = preg_replace('/^(el)?if\s+!?\s*/', '', $code) ?? $code;
        $commande = preg_replace('/^!\s*/', '', $commande) ?? $commande;

        if (preg_match($effet, $commande) === 1) {
            $suspects[] = $code;
        }
    }

    // ⚖️ CECI EST UN RATCHET EXACT, PAS UN PLANCHER AVEC DE LA MARGE.
    // Le nombre est PILE la valeur courante : retirer un seul `run_cmd` le fait
    // tomber à 52 et rougir. Ne le « détendez » pas en croyant garder du jeu —
    // il n'y en a pas, c'est le but. Un site ajouté ? Montez-le d'autant, dans
    // le même commit que l'ajout.
    expect($routees)
        ->toBe(53);

    // ⚖️ LA LISTE DES EXCEPTIONS EST EXPLICITE, COURTE, ET CHACUNE SE JUSTIFIE.
    // C'est elle qui rend l'audit relisible en revue plutôt que promis.
    expect($suspects)
        ->toBe([
            // Branche RÉELLE uniquement : la simulation sort avant (garde dry-run).
            'chmod -R 777 "$target_dir" 2>/dev/null || true',
            // Valeurs de retour de fonction, écrites sur stdout — pas des effets.
            'echo "$state_name"',
            'printf \'%s\n\' "$name"',
            // Corps de `patch_skeleton_composer_json_preinstall`, elle-même routée.
            'python3 << \'PYEOF\'',
            // Lectures, et `validate_laravel_installation` n'est pas atteinte en
            // simulation (garde explicite dans `create_laravel_project`).
            'if ! php artisan --version &>/dev/null; then',
            'if ! php -r "json_decode(file_get_contents(\'composer.json\')); if(json_last_error() !== JSON_ERROR_NONE) exit(1);" 2>/dev/null; then',
            // Branche RÉELLE uniquement : la simulation sort avant.
            'if cp "$source_env_file" "$target_env_file"; then',
            // Valeur de retour de fonction.
            'echo "$env_path"',
            // Corps de `append_line_to_env`, elle-même routée (la redirection ne
            // peut pas être enveloppée par `run_cmd`).
            'echo "$1" >> ".env"',
            // Sonde de décision, non jouée en simulation (elle boote l'application).
            'elif php artisan tinker --execute="try { DB::table(\'cache\')->limit(1)->get(); echo \'exists\'; } catch(Exception \$e) { echo \'missing\'; }" 2>/dev/null | grep -q "exists"; then',
            // Corps de `patch_skeleton_composer_json_idempotent`, elle-même routée.
            'python3 << \'PYEOF\'',
            // Corps de `append_healthcheck_route`, elle-même routée.
            'cat >> routes/web.php << \'EOF\'',
        ]);
});
