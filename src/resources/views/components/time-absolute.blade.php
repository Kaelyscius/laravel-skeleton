{{--
    <x-time-absolute> — la date, écrite en français (Story 1.12, AC3/AC8/AC10).

    Le pendant de <x-time-relative> : là où la durée relative sert l'immédiateté
    (« il y a 3 heures »), la date absolue sert l'archive et la citation — un
    article de 2024 n'a pas besoin d'être daté « il y a 2 ans ».

    ⚠️ `translatedFormat()`, JAMAIS `format()`. `format('d F Y')` rend
    « 14 January 2026 » : en anglais, sans erreur, sans warning, quelle que soit
    la locale de l'application. C'est le genre de défaut qui traverse une revue
    de code parce que la sortie a l'air d'une date correcte. Le test associé
    emploie JANVIER et non mars, parce qu'avec mars `d M Y` et `d F Y` rendent
    la même chaîne et l'assertion ne distinguerait plus rien.

    Pas de préfixe ici non plus (« Publié le… ») : voir l'en-tête de
    <x-time-relative>, c'est la même règle et la même raison.
--}}

@props([
    'datetime',
    'format' => 'd F Y',
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
                '<x-time-absolute> : datetime illisible ['.$datetime.'].', 0, $exception
            );
        }
    } else {
        throw new InvalidArgumentException(
            '<x-time-absolute> : datetime doit être un DateTimeInterface ou une chaîne parsable, reçu ['.$describe($datetime).'].'
        );
    }

    if (! is_string($format) || trim($format) === '') {
        throw new InvalidArgumentException(
            '<x-time-absolute> : format doit être un gabarit de date non vide, reçu ['.$describe($format).'].'
        );
    }
@endphp

<time
    datetime="{{ $instant->toIso8601String() }}"
    data-temporal
    {{ $attributes->except(['datetime', 'data-temporal'])->merge([
        'class' => 'font-mono text-sm tabular-nums tracking-tight text-text-secondary',
    ]) }}
>{{ $instant->translatedFormat($format) }}</time>
