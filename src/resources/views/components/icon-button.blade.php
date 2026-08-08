{{--
    <x-icon-button> — primitive présentationnelle (Story 1.11, AC4 + AC6).

    Un bouton dont le contenu est une icône n'a AUCUN nom accessible : sans
    `aria-label`, il est muet pour un lecteur d'écran et rien ne le signale.
    D'où le fail-loud — l'absence de label est une erreur de programmation, pas
    une valeur par défaut acceptable.

    ⚠️ `aria-label` est lu depuis $attributes et NON déclaré en @props : Blade
    convertit les noms de props en camelCase, et un attribut à tiret déclaré en
    prop sortirait du sac d'attributs sans être rendu dans le HTML. Le lire ici
    garantit qu'il reste rendu tel quel (AC4) tout en servant de `title`.

    `title` est fourni via merge(), donc en DÉFAUT : un appelant qui passe son
    propre `title` (infobulle plus riche que le nom accessible) gagne.

    Anneau de focus : voir le commentaire de button.blade.php — même mécanique,
    mêmes raisons (`outline-hidden` + `ring-offset`, et non `outline-none`).
--}}

@props([
    'type' => 'button',
    'disabled' => false,
])

@php
    $describe = static fn (mixed $value): string => is_scalar($value) ? (string) $value : get_debug_type($value);

    $ariaLabel = $attributes->get('aria-label');

    if (! is_string($ariaLabel) || trim($ariaLabel) === '') {
        throw new InvalidArgumentException(
            '<x-icon-button> exige un attribut aria-label non vide : une icône seule '
            .'n\'expose aucun nom accessible.'
        );
    }

    $buttonType = match ($type) {
        'button', 'submit', 'reset' => $type,
        default => throw new InvalidArgumentException(
            '<x-icon-button> : type inconnu ['.$describe($type).']. Attendu : button, submit ou reset.'
        ),
    };
@endphp

<button
    type="{{ $buttonType }}"
    @disabled(filter_var($disabled, FILTER_VALIDATE_BOOL))
    {{ $attributes->except('type')->merge([
        'title' => $ariaLabel,
        'class' => 'inline-flex size-8 shrink-0 items-center justify-center rounded-md border border-transparent '
            .'bg-transparent text-text-secondary transition hover:bg-surface hover:text-text-primary '
            .'active:bg-border focus-visible:outline-hidden focus-visible:outline-offset-2 focus-visible:ring-2 '
            .'focus-visible:ring-lava/40 focus-visible:ring-offset-2 focus-visible:ring-offset-bg '
            .'disabled:cursor-not-allowed disabled:opacity-50',
    ]) }}
>
    {{ $slot }}
</button>
