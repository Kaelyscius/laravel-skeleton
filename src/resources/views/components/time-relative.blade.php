{{--
    <x-time-relative> — la durée écoulée, jamais une date (Story 1.12, AC2/AC6/AC8/AC10).

    C'est la primitive « le temps comme texture » (Direction C) : l'information
    utile n'est pas « 14 mars 2026 à 21 h 03 », c'est « il y a 3 heures ». Le
    lecteur n'a aucune conversion mentale à faire.

    ─────────────────────────────────────────────────────────────────────────
    CE QUE CE COMPOSANT NE REND PAS, ET C'EST DÉLIBÉRÉ

    Aucun préfixe. « Dernier stream », « En direct depuis », « Publié » sont du
    contexte d'ÉCRAN, pas du composant — vérifié sur les écrans de référence
    (story 0c, `done`) : `03-press-kit.html` rend `<dt>En stream depuis</dt>`
    autour d'un `<dd>4 ans</dd>`, et le mot n'est même pas le même d'un écran à
    l'autre. Un composant qui graverait sa phrase serait faux sur le premier
    écran qui l'emploie. Le composant porte la DONNÉE, l'écran porte la PHRASE.

    ─────────────────────────────────────────────────────────────────────────
    UN SEUL ATTRIBUT PORTE L'INSTANT

    `<time datetime>` est l'attribut canonique du HTML pour cela, et c'est LUI
    que le JavaScript relit à chaque rafraîchissement. La Story 1.12 suggérait
    un `data-time-iso` en doublon : deux attributs portant le même instant
    seraient deux sources de vérité, c'est-à-dire exactement le défaut que le
    reste de cette story passe son temps à traquer.

    ─────────────────────────────────────────────────────────────────────────
    LES DEUX SEULS ATTRIBUTS ALPINE SONT DES RÉFÉRENCES NUES (AC6)

      x-data="timeRelative"  → la fabrique enregistrée par Alpine.data() dans app.js
      x-text="label"         → un simple accès de propriété

    Ni `@click`, ni `x-init`, ni `setInterval` ici : un scan récursif de tous les
    composants échoue si une expression y réapparaît (tests/Feature/LayoutsTest.php).
    L'intervalle est exposé en `data-time-refresh` et c'est le JS qui le LIT,
    comme la durée de <x-toast> avant lui.

    ─────────────────────────────────────────────────────────────────────────
    UN ATTRIBUT APPARAÎT À L'EXÉCUTION, ET C'EST UN INSTRUMENT

    `data-time-ticks` n'est PAS rendu par ce fichier : c'est app.js qui le pose,
    à '0' dès l'initialisation puis à chaque DÉCLENCHEMENT de l'intervalle. Il
    est écrit ici pour qu'un lecteur du composant ne le découvre pas dans le
    DOM sans savoir d'où il sort.

    Il compte les déclenchements, PAS les réécritures de libellé — la nuance a
    coûté une mutation survivante le 2026-08-08 : un intervalle programmé à
    tort sur un élément vieux de plusieurs mois se déclenchait, sortait sans
    réécrire, et un compteur de réécritures affichait 0, exactement ce qu'il
    aurait affiché si la garde avait tenu.

    Ce qu'il rend possible : distinguer « aucun tick » de « Alpine n'a jamais
    tourné », deux états qu'un attribut absent confondrait. Sa surface en
    production est un attribut de données, sans donnée sensible ; l'AC6 le
    demande explicitement (« compteur exposé »), et il a déjà attrapé un
    défaut réel. Arbitrage confirmé à la revue du 2026-08-08.

    ⚠️ Sous <x-layouts.minimal>, ce composant est SILENCIEUSEMENT INERTE : ce
    layout ne charge pas @livewireScripts, donc pas Alpine, donc `alpine:init`
    n'est jamais émis. Le libellé du serveur s'affiche et ne bouge plus. C'est
    inventorié dans l'en-tête de minimal.blade.php, avec son déclencheur de
    réveil.
--}}

@props([
    'datetime',
    'short' => false,
    'refresh' => 60000,
])

@php
    $describe = static fn (mixed $value): string => is_scalar($value) ? (string) $value : get_debug_type($value);

    /*
     * Garde fail-loud sur l'instant. Un repli silencieux sur `now()` afficherait
     * « il y a 0 seconde » sur une prop cassée : une valeur plausible, donc
     * indétectable à l'œil, et un test de rendu resterait vert en n'observant
     * plus ce qu'il croit observer.
     */
    if ($datetime instanceof DateTimeInterface) {
        $instant = \Carbon\Carbon::instance($datetime);
    } elseif (is_string($datetime) && trim($datetime) !== '') {
        try {
            $instant = \Carbon\Carbon::parse($datetime);
        } catch (Throwable $exception) {
            throw new InvalidArgumentException(
                '<x-time-relative> : datetime illisible ['.$datetime.'].', 0, $exception
            );
        }
    } else {
        throw new InvalidArgumentException(
            '<x-time-relative> : datetime doit être un DateTimeInterface ou une chaîne parsable, reçu ['.$describe($datetime).'].'
        );
    }

    /*
     * Même garde que <x-toast> sur sa durée, et pour la même raison précise :
     * `setInterval(fn, NaN)` ne se contente PAS d'échouer, il tourne à
     * intervalle minimal, en continu. Une boucle chaude sur une page publique.
     *
     * ⚠️ LA GARDE EST BORNÉE DES DEUX CÔTÉS — corrigé à la revue du 2026-08-08.
     * `> 0` seul laissait passer `:refresh="1"`, qui produit EXACTEMENT la boucle
     * chaude que cette garde dit exister pour empêcher (les navigateurs clampent
     * à 4 ms, ce qui fait 250 réveils par seconde et par mention). Et une valeur
     * au-delà de 2^31-1 déborde l'entier signé de `setInterval` et se déclenche
     * IMMÉDIATEMENT, en continu — le même défaut par l'autre bout.
     *
     * 250 ms est le plancher parce que c'est la valeur qu'emploie la page de
     * démonstration pour rendre le rafraîchissement observable ; 24 h est le
     * plafond parce qu'au-delà l'intervalle ne se déclenche jamais dans une
     * session et qu'un `refresh` inatteignable est un attribut mort.
     */
    if (! is_numeric($refresh) || (int) $refresh < 250 || (int) $refresh > 86400000) {
        throw new InvalidArgumentException(
            '<x-time-relative> : refresh doit être un entier de millisecondes entre 250 et 86400000, reçu ['.$describe($refresh).'].'
        );
    }

    $isShort = (bool) $short;

    /*
     * Chaque forme réserve SA largeur (revue du 2026-08-08). `--width-temporal`
     * vaut 18ch, dimensionné sur « il y a 59 secondes » ; sous « il y a 14 h »,
     * la forme des écrans de référence, cela creuse 5 caractères de vide en
     * plein milieu de « Dernier stream il y a 14 h ». Une largeur réservée
     * existe pour empêcher un tressautement, pas pour creuser un trou.
     */
    $widthUtility = $isShort ? 'min-w-temporal-short' : 'min-w-temporal';

    // La forme COURTE est celle des écrans de référence (« il y a 14 h »), la
    // LONGUE reste le défaut, conformément à l'AC.
    $label = $instant->diffForHumans(short: $isShort);
@endphp

<time
    datetime="{{ $instant->toIso8601String() }}"
    data-temporal
    data-time-short="{{ $isShort ? '1' : '0' }}"
    data-time-refresh="{{ (int) $refresh }}"
    x-data="timeRelative"
    x-text="label"
    {{ $attributes->except(['datetime', 'data-temporal', 'data-time-short', 'data-time-refresh'])->merge([
        'class' => 'inline-block '.$widthUtility.' font-mono text-sm tabular-nums tracking-tight text-text-secondary',
    ]) }}
>{{ $label }}</time>
