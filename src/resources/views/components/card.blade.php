{{--
    <x-card> — primitive présentationnelle (Story 1.11, AC2).

    Trois états observables par valeur calculée : `default`, `hover`, `selected`.
    Ils se distinguent par la COULEUR DE BORDURE, pas par un accent : une carte
    est du 90 % monochrome (RÈGLE 2), jamais un porteur de lava.

    `selected` est une prop et non un pseudo-état : la sélection est un fait
    applicatif, elle doit survivre au départ du curseur.
--}}

@props([
    'selected' => false,
])

@php
    // filter_var : `selected="false"` arrive en chaîne, et `(bool) 'false'` vaut true.
    $isSelected = filter_var($selected, FILTER_VALIDATE_BOOL);

    $stateClasses = $isSelected
        ? 'border-text-secondary'
        : 'border-border hover:border-text-secondary/40';
@endphp

<div
    @if ($isSelected) data-selected="true" @endif
    {{ $attributes->except('data-selected')->merge([
        'class' => 'rounded-lg border bg-surface p-6 transition '.$stateClasses,
    ]) }}
>
    {{ $slot }}
</div>
