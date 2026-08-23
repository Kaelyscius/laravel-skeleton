<?php

declare(strict_types=1);

use Tests\Support\ShellProbe;

/*
|------------------------------------------------------------------------------
| Le repli `DatabaseHealthCheck` écrit par `scripts/install/35-…`
|------------------------------------------------------------------------------
|
| 🔴 CE FICHIER EST ÉCRIT DANS LA SITUATION QUE PERSONNE NE RELIT — un squelette
| rebâti de zéro, où `app/HealthChecks/DatabaseHealthCheck.php` n'existe pas
| encore. C'est exactement pour cela qu'il a pu FUIR LE DSN pendant toute la vie
| du dépôt : `Result::failed('… ' . $e->getMessage())` publiait l'hôte, le port,
| la base et l'utilisateur dans le corps de `/health` et dans les notifications
| de Spatie — pendant que la version versionnée de la même classe scrubait
| soigneusement les mêmes informations.
|
| ⛔ ET LE CORRECTIF DE LA REVUE 1 N'ÉTAIT OBSERVABLE PAR AUCUN TEST : réintroduire
| `. $e->getMessage()` ne changeait rien à la suite. Le module 10 a un harnais
| (`harnaisComposer`) ; le 35 n'en avait aucun. Il en a un ici.
|
| ⚖️ Le module est SOURCÉ, pas exécuté : on remplace ses sondes (`php artisan`,
| `is_package_installed`) plutôt que le code sous test — même discipline que
| `InstallDryRunTest`.
|
*/

it('écrit un repli qui NE PUBLIE JAMAIS le message d’exception', function (): void {
    $result = ShellProbe::run(<<<'BASH'
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        export LOG_FILE="$bac/log"
        mkdir -p "$bac/appli/config"
        cd "$bac/appli"

        # `php artisan vendor:publish` ne doit rien faire ici : on éprouve le
        # GABARIT écrit par le module, pas la publication de Spatie.
        mkdir -p "$bac/bin"
        printf '#!/bin/sh\nexit 0\n' > "$bac/bin/php"
        chmod +x "$bac/bin/php"
        PATH="$bac/bin:$PATH"

        source "$MODULE_SH"

        # Sonde remplacée : le module part sinon en `return 0` silencieux.
        is_package_installed() { return 0; }

        # `config/health.php` existe déjà → pas de publication de config.
        printf '<?php return [];\n' > config/health.php

        statut=0
        ( configure_laravel_health ) > "$bac/sortie" 2>&1 || statut=$?
        echo "STATUS=$statut"

        cible="app/HealthChecks/DatabaseHealthCheck.php"
        [ -f "$cible" ] && echo "ECRIT=oui" || echo "ECRIT=non"

        grep -q 'getMessage()' "$cible" && echo "FUITE=oui" || echo "FUITE=non"
        grep -q "failed('Database unreachable')" "$cible" && echo "MESSAGE_NEUTRE=oui" || echo "MESSAGE_NEUTRE=non"
        grep -q "Log::error" "$cible" && echo "JOURNALISE=oui" || echo "JOURNALISE=non"
        grep -q "sqlstate" "$cible" && echo "SQLSTATE=oui" || echo "SQLSTATE=non"

        # Le gabarit doit être du PHP réellement analysable : le module suivant
        # lance `php artisan`, qui autocharge cette classe.
        if command -v php > /dev/null 2>&1; then
            PATH="$(echo "$PATH" | sed "s|$bac/bin:||")" php -l "$cible" > /dev/null 2>&1 \
                && echo "PHP_VALIDE=oui" || echo "PHP_VALIDE=non"
        else
            echo "PHP_VALIDE=indisponible"
        fi

        # Idempotence : un second passage ne réécrit pas par-dessus.
        printf '// sentinelle operateur\n' >> "$cible"
        ( configure_laravel_health ) > "$bac/sortie-2" 2>&1 || true
        grep -q 'sentinelle operateur' "$cible" && echo "IDEMPOTENT=oui" || echo "IDEMPOTENT=non"

        rm -rf "$bac"
        BASH
        , [
            'MODULE_SH' => ShellProbe::installModuleScript('35-configure-spatie-packages'),
        ], 60);

    expect($result['output'])->toContain('STATUS=0');
    expect($result['output'])->toContain('ECRIT=oui');

    // 🔒 LE GARDE : aucune fuite du message d'exception.
    expect($result['output'])->toContain('FUITE=non');

    // Anti-vacuité : le fichier dit bien quelque chose, et scrube en le disant.
    expect($result['output'])->toContain('MESSAGE_NEUTRE=oui');
    expect($result['output'])->toContain('JOURNALISE=oui');
    expect($result['output'])->toContain('SQLSTATE=oui');
    expect($result['output'])->toContain('PHP_VALIDE=oui');

    // Un opérateur qui a personnalisé la classe ne la perd pas.
    expect($result['output'])->toContain('IDEMPOTENT=oui');
});
