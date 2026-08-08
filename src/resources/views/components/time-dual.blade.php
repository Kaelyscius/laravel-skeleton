{{--
    <x-time-dual> — publié, et mis à jour seulement si ça vaut la peine
    (Story 1.12, AC4/AC8/AC10).

    Destiné aux articles (Epic 5). « Mis à jour » n'apparaît QUE si la mise à
    jour est postérieure de plus de 30 jours à la publication : une coquille
    corrigée le lendemain n'est pas une information pour le lecteur, alors qu'un
    test réécrit six mois plus tard en est une.

    ⚠️ LE SEUIL EST STRICTEMENT SUPÉRIEUR, et ce n'est pas un détail : à
    exactement +30 jours, on rend « Publié » seul. C'est le seul cas qui
    distingue `>` de `>=`, et il a son test.

    ⚠️ `addDays()` MUTE l'instance en place en Carbon 3. Écrire
    `$published->addDays(30)` décalerait la date PUBLIÉE affichée de 30 jours —
    et la branche testée resterait juste, donc le test passerait en affichant
    une date fausse. D'où le `copy()` ci-dessous, et l'assertion sur la date
    publiée rendue dans tests/Feature/TimeAsTextureTest.php.

    Ce composant-ci rend bien ses libellés (« Publié », « Mis à jour ») : ils
    font partie de sa sémantique, pas du contexte d'écran. C'est la différence
    avec <x-time-since>, dont le préfixe change d'un écran à l'autre.

    Le marqueur d'inventaire `data-temporal` est porté par le CONTENEUR et par
    lui seul : un `<x-time-dual>` est UNE mention temporelle, pas deux. Le
    marquer sur les deux `<time>` intérieurs gonflerait le comptage de l'audit
    (docs/ux/references/time-as-texture-audit.md §4).
--}}

@props([
    'published',
    'updated' => null,
    'format' => 'd F Y',
])

@php
    $describe = static fn (mixed $value): string => is_scalar($value) ? (string) $value : get_debug_type($value);

    $toCarbon = static function (mixed $value, string $prop) use ($describe): \Carbon\Carbon {
        if ($value instanceof DateTimeInterface) {
            return \Carbon\Carbon::instance($value);
        }

        if (is_string($value) && trim($value) !== '') {
            try {
                return \Carbon\Carbon::parse($value);
            } catch (Throwable $exception) {
                throw new InvalidArgumentException(
                    '<x-time-dual> : '.$prop.' illisible ['.$value.'].', 0, $exception
                );
            }
        }

        throw new InvalidArgumentException(
            '<x-time-dual> : '.$prop.' doit être un DateTimeInterface ou une chaîne parsable, reçu ['.$describe($value).'].'
        );
    };

    if (! is_string($format) || trim($format) === '') {
        throw new InvalidArgumentException(
            '<x-time-dual> : format doit être un gabarit de date non vide, reçu ['.$describe($format).'].'
        );
    }

    $publishedAt = $toCarbon($published, 'published');
    $updatedAt = $updated === null ? null : $toCarbon($updated, 'updated');

    $showsUpdate = $updatedAt !== null
        && $updatedAt->greaterThan($publishedAt->copy()->addDays(30));
@endphp

<span
    data-temporal
    {{ $attributes->except(['data-temporal'])->merge([
        'class' => 'font-mono text-sm tabular-nums tracking-tight text-text-secondary',
    ]) }}
>Publié <time datetime="{{ $publishedAt->toIso8601String() }}">{{ $publishedAt->translatedFormat($format) }}</time>@if ($showsUpdate && $updatedAt !== null) · Mis à jour <time datetime="{{ $updatedAt->toIso8601String() }}">{{ $updatedAt->translatedFormat($format) }}</time>@endif</span>
