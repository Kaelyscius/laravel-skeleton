{{--
    <x-divider> — primitive présentationnelle (Story 1.11, AC5).

    `role="separator"` est écrit EXPLICITEMENT plutôt que délégué au rôle
    implicite de <hr> : l'AC porte sur l'attribut présent dans le HTML rendu, et
    un rôle implicite ne se vérifie pas dans le markup — il se suppose.

    ⚠️ `role="separator"` ne tire PAS son nom accessible de son contenu (ARIA :
    ce rôle n'autorise pas le « name from content »). Un séparateur libellé
    « Suite » était donc visible à l'écran et muet au lecteur d'écran — trouvé en
    revue de code. Le libellé est repris en `aria-label`.

    Le slot est optionnel, et un slot qui ne contient QUE des espaces compte pour
    vide : sinon on rendrait un conteneur de libellé creux, c'est-à-dire le trou
    dans la ligne que ce composant prétend éviter.
--}}

@php
    $slotHtml = $slot->toHtml();
    $hasLabel = trim($slotHtml) !== '';

    $labelText = trim((string) preg_replace('/\s+/', ' ', strip_tags($slotHtml)));
@endphp

<div
    role="separator"
    @if ($labelText !== '') aria-label="{{ $labelText }}" @endif
    {{ $attributes->except(['role', 'aria-label'])->merge(['class' => 'flex w-full items-center gap-3']) }}
>
    @if ($hasLabel)
        <span class="h-px flex-1 bg-border"></span>
        <span data-role="divider-label" class="text-xs font-medium tracking-wide text-text-secondary uppercase">
            {{ $slot }}
        </span>
        <span class="h-px flex-1 bg-border"></span>
    @else
        <span class="h-px w-full bg-border"></span>
    @endif
</div>
