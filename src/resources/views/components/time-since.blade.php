{{--
    <x-time-since> — la durée nue, sans « il y a » et sans « depuis »
    (Story 1.12, AC5/AC8/AC10).

    Rend `4 ans`, pas `il y a 4 ans` ni `Streaming depuis 4 ans`. La différence
    n'est pas cosmétique : c'est la durée ABSOLUE (Carbon `DIFF_ABSOLUTE`),
    celle qu'on lit dans une fiche d'identité — « En stream depuis : 4 ans » —
    et non un repère dans le passé.

    ⚠️ LE PRÉFIXE APPARTIENT À L'APPELANT. L'AC d'origine disait « rend
    `Streaming depuis 4 ans` » ; l'écran de référence press kit (story 0c,
    `done`) rend `<dt>En stream depuis</dt>` + `<dd class="temporal">4 ans</dd>`.
    Non seulement le préfixe est hors du composant, mais ce n'est même pas le
    même mot. Un composant qui graverait « Streaming depuis » serait faux sur
    le SEUL écran qui l'emploie.

    `parts` sert le futur badge LIVE (Epic 4) : « 2 h 17 min » d'antenne se dit
    en deux unités. ⚠️ Carbon rend bien l'unité de la seconde part
    (« 2 h 17 min », pas « 2 h 17 ») — mesuré, pas supposé.

    Ce composant n'est pas rafraîchi côté client, et c'est volontaire : sa
    consommation prévue (le press kit, Epic 8) affiche des années. Le badge LIVE
    qui aura besoin d'un compteur vivant est un composant Livewire de l'Epic 4,
    avec sa propre source de vérité.
--}}

@props([
    'datetime',
    'parts' => 1,
    'short' => false,
])

@php
    $describe = static fn (mixed $value): string => is_scalar($value) ? (string) $value : get_debug_type($value);

    if ($datetime instanceof DateTimeInterface) {
        $instant = \Carbon\Carbon::instance($datetime);
    } elseif (is_string($datetime) && trim($datetime) !== '') {
        try {
            $instant = \Carbon\Carbon::parse($datetime);
        } catch (Throwable $exception) {
            throw new InvalidArgumentException(
                '<x-time-since> : datetime illisible ['.$datetime.'].', 0, $exception
            );
        }
    } else {
        throw new InvalidArgumentException(
            '<x-time-since> : datetime doit être un DateTimeInterface ou une chaîne parsable, reçu ['.$describe($datetime).'].'
        );
    }

    /*
     * `(int) $parts` transformerait 'deux' et 0 en 0 sans rien dire, et Carbon
     * rendrait alors une chaîne VIDE — une mention temporelle qui disparaît
     * sans que rien ne la réclame.
     */
    if (! is_numeric($parts) || (int) $parts < 1) {
        throw new InvalidArgumentException(
            '<x-time-since> : parts doit être un entier >= 1, reçu ['.$describe($parts).'].'
        );
    }
@endphp

<time
    datetime="{{ $instant->toIso8601String() }}"
    data-temporal
    {{ $attributes->except(['datetime', 'data-temporal'])->merge([
        'class' => 'font-mono text-sm tabular-nums tracking-tight text-text-secondary',
    ]) }}
>{{ $instant->diffForHumans(syntax: \Carbon\CarbonInterface::DIFF_ABSOLUTE, short: (bool) $short, parts: (int) $parts) }}</time>
