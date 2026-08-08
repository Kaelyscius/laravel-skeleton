{{--
    <x-badge> — primitive présentationnelle (Story 1.11, AC3).

    ⚠️ Le variant `lava` n'est PAS « réservé au badge LIVE ». La rédaction
    d'origine de l'AC le disait ; elle contredisait `tokens.css` RÈGLE 2, livrée
    et testée par la Story 1.8. Le token fait foi : lava couvre EXACTEMENT
    4 usages — badge LIVE, CTA primaires, notes ≥ 9/10, destructif admin. Ce
    variant sert les usages 1, 3 et 4 ; l'usage 2 est <x-button variant="primary">.

    Aucun autre variant n'a le droit d'émettre --accent-lava : c'est ce que
    vérifie BladeComponentsTest, et ce garde-fou a été vu rouge en ajoutant
    `text-lava` au variant `neutral`.

    `data-variant` est retiré du sac d'attributs avant le merge : sans cela, un
    appelant passant `data-variant` produirait l'attribut DEUX FOIS, HTML
    invalide où le parseur garde silencieusement le premier.
--}}

@props([
    'variant' => 'neutral',
])

@php
    $describe = static fn (mixed $value): string => is_scalar($value) ? (string) $value : get_debug_type($value);

    $variantClasses = match ($variant) {
        'neutral' => 'bg-surface text-text-secondary border-border',
        'lava' => 'bg-lava/10 text-lava border-lava/30',
        'ok' => 'bg-ok/10 text-ok border-ok/30',
        'warn' => 'bg-warn/10 text-warn border-warn/30',
        'err' => 'bg-err/10 text-err border-err/30',
        default => throw new InvalidArgumentException(
            '<x-badge> : variant inconnu ['.$describe($variant).']. Attendu : neutral, lava, ok, warn ou err.'
        ),
    };
@endphp

<span
    data-variant="{{ $variant }}"
    {{ $attributes->except('data-variant')->merge([
        'class' => 'inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium '.$variantClasses,
    ]) }}
>
    {{ $slot }}
</span>
