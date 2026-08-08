{{--
    <x-button> — primitive présentationnelle (Story 1.11, AC1 + AC6).

    Composant ANONYME : pas de classe PHP. UX-DR-64 — « slots pour la flexibilité,
    props pour la configuration, pas d'over-abstraction ».

    RÈGLE 1 (tokens.css) : aucune couleur en dur, aucune arbitrary value. Tout
    passe par les utilities générées depuis les tokens (bg-lava, text-bg…).

    RÈGLE 2 (90/8/2) : `variant="primary"` est le SEUL variant à porter
    --accent-lava en SURFACE — c'est l'usage 2/4 « CTA primaires ». `secondary`
    et `ghost` sont strictement monochromes.

    ⚠️ L'anneau de focus (`ring-lava/40`) est porté par les TROIS variants, et
    c'est voulu : AC6 impose que tout focusable de cette story dérive son anneau
    du token. C'est un ÉTAT (les 2 % de 90/8/2), pas une surface — exemption
    désormais inscrite dans `tokens.css` RÈGLE 2 elle-même, pour qu'elle ne se
    re-débatte pas à chaque story. Le test AC1 n'écarte donc que les utilities
    d'anneau NOMMÉMENT, jamais tout le préfixe `focus-visible:`.

    ⚠️ `outline-hidden` et non `outline-none` : en Tailwind 4, `outline-none`
    pose `outline-style: none` PARTOUT, y compris en contrastes forcés (Windows
    High Contrast) où les box-shadow sont supprimées — l'utilisateur perdrait
    alors tout indicateur de focus. `outline-hidden` conserve un
    `outline: 2px solid transparent` sous `forced-colors`, que le système
    repeint, et c'est LUI que gouverne `outline-offset-2`.
    Le décalage visible en mode normal vient de `ring-offset-2 ring-offset-bg`.
    Trouvé en revue de code : sans lui, `outline-offset` ne décalait rien du
    tout — l'anneau est une box-shadow — et l'assertion d'AC6 mesurait une
    propriété qui ne peignait rien.

    `disabled` et `loading` sont des ATTRIBUTS RÉELS, pas du style : un bouton
    qui a l'air désactivé mais reste cliquable est le motif de garde-fou
    silencieux que ce projet passe son temps à corriger.
--}}

@props([
    'variant' => 'primary',
    'type' => 'button',
    'loading' => false,
    'disabled' => false,
])

@php
    /*
     * Un variant passé en tableau ou en objet produirait une « Array to string
     * conversion » — une Error, pas l'InvalidArgumentException documentée.
     */
    $describe = static fn (mixed $value): string => is_scalar($value) ? (string) $value : get_debug_type($value);

    $variantClasses = match ($variant) {
        'primary' => 'bg-lava text-bg hover:bg-lava/80 active:bg-lava/60',
        'secondary' => 'bg-surface text-text-primary border border-border hover:border-text-secondary active:bg-border',
        'ghost' => 'bg-transparent text-text-secondary border border-transparent hover:bg-surface hover:text-text-primary active:bg-border',
        default => throw new InvalidArgumentException(
            '<x-button> : variant inconnu ['.$describe($variant).']. Attendu : primary, secondary ou ghost.'
        ),
    };

    /*
     * `type` était interpolé sans contrôle alors que `variant` échoue bruyamment.
     * Une faute de frappe (`sumbit`) retombe silencieusement sur `submit` d'après
     * la spec HTML : dans un formulaire, c'est une soumission non voulue.
     */
    $buttonType = match ($type) {
        'button', 'submit', 'reset' => $type,
        default => throw new InvalidArgumentException(
            '<x-button> : type inconnu ['.$describe($type).']. Attendu : button, submit ou reset.'
        ),
    };

    /*
     * filter_var et non (bool) : un attribut HTML arrive en CHAÎNE, et
     * `(bool) 'false'` vaut true. `<x-button disabled="false">` rendait donc un
     * bouton désactivé.
     */
    $isLoading = filter_var($loading, FILTER_VALIDATE_BOOL);
    $isDisabled = filter_var($disabled, FILTER_VALIDATE_BOOL) || $isLoading;
@endphp

<button
    type="{{ $buttonType }}"
    @disabled($isDisabled)
    @if ($isLoading) aria-busy="true" @endif
    {{ $attributes->except(['type', 'aria-busy'])->merge([
        'class' => 'inline-flex items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-medium transition '
            .'focus-visible:outline-hidden focus-visible:outline-offset-2 focus-visible:ring-2 '
            .'focus-visible:ring-lava/40 focus-visible:ring-offset-2 focus-visible:ring-offset-bg '
            .'disabled:cursor-not-allowed disabled:opacity-50 '
            .$variantClasses,
    ]) }}
>
    @if ($isLoading)
        {{-- motion-reduce : une animation infinie sans échappatoire est un
             déclencheur vestibulaire (UX-DR-43, WCAG 2.3.3). --}}
        <span
            class="size-4 shrink-0 animate-spin rounded-full border-2 border-current border-t-transparent motion-reduce:animate-none"
            data-role="spinner"
            aria-hidden="true"
        ></span>
    @endif
    {{ $slot }}
</button>
