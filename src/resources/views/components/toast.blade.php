{{--
    <x-toast> — STRUCTURE SEULEMENT (Story 1.11, AC7).

    ⛔ AUCUN COMPORTEMENT JS ICI, y compris « en attendant ».

    Arbitrage PO du 2026-08-08 (option 1) : l'auto-fermeture exige Alpine, qui
    arrive avec @livewireScripts câblé par la Story 1.13. En 1.11 aucune page ne
    charge Alpine — un AC de comportement s'y validerait sans rien exécuter,
    c'est-à-dire le faux-vert qui a fait réordonner tout l'Epic 1. La 1.11 livre
    donc ce qui est vérifiable par rendu Blade : structure et accessibilité.

    `duration` est exposée en prop (défaut 5000 ms) et rendue en attribut de
    données. La Story 1.13 la LIRA depuis le DOM pour brancher le comportement,
    sans toucher à ce fichier.

    Le `role` n'est pas décoratif : `alert` interrompt le lecteur d'écran, ce qui
    n'est justifié que si l'utilisateur doit agir (error, warning). `status` est
    annoncé poliment, ce que méritent success et info.

    ⚠️ La pastille de type porte `bg-current` et hérite donc du `text-*` du
    conteneur. Sans elle, ce `text-*` ne peignait RIEN — le corps du message a sa
    propre couleur et le bouton de fermeture la sienne — et « les 4 types sont
    visuellement distincts » ne tenait que par la bordure. Trouvé en revue de
    code : le test comparait des chaînes de classes, pas des pixels.
--}}

@props([
    'type' => 'info',
    'duration' => 5000,
    'dismissLabel' => 'Fermer la notification',
])

@php
    $describe = static fn (mixed $value): string => is_scalar($value) ? (string) $value : get_debug_type($value);

    $typeClasses = match ($type) {
        'success' => 'border-ok/40 text-ok',
        'error' => 'border-err/40 text-err',
        'warning' => 'border-warn/40 text-warn',
        'info' => 'border-border text-text-secondary',
        default => throw new InvalidArgumentException(
            '<x-toast> : type inconnu ['.$describe($type).']. Attendu : success, error, warning ou info.'
        ),
    };

    $role = in_array($type, ['error', 'warning'], true) ? 'alert' : 'status';

    /*
     * `(int) $duration` transformait '5s', 'abc' et -1 en 0 sans rien dire — la
     * Story 1.13 aurait hérité d'un toast qui se ferme instantanément, et le
     * défaut aurait eu l'air de fonctionner. Une durée est un entier > 0.
     */
    if (! is_numeric($duration) || (int) $duration <= 0) {
        throw new InvalidArgumentException(
            '<x-toast> : duration doit être un entier de millisecondes > 0, reçu ['.$describe($duration).'].'
        );
    }

    /*
     * Sans ce contrôle, un dismissLabel vide fait échouer <x-icon-button> avec
     * un message qui nomme un composant que l'appelant n'a jamais écrit.
     */
    if (! is_string($dismissLabel) || trim($dismissLabel) === '') {
        throw new InvalidArgumentException(
            '<x-toast> : dismissLabel doit être une chaîne non vide — c\'est le nom accessible du bouton de fermeture.'
        );
    }
@endphp

<div
    role="{{ $role }}"
    data-toast-type="{{ $type }}"
    data-toast-duration="{{ (int) $duration }}"
    {{ $attributes->except(['role', 'data-toast-type', 'data-toast-duration'])->merge([
        'class' => 'flex w-full items-start gap-3 rounded-lg border bg-surface p-4 text-sm '.$typeClasses,
    ]) }}
>
    <span data-role="toast-indicator" class="mt-1.5 size-2 shrink-0 rounded-full bg-current" aria-hidden="true"></span>

    <div class="flex-1 text-text-primary">
        {{ $slot }}
    </div>

    <x-icon-button aria-label="{{ $dismissLabel }}" data-toast-dismiss>
        <span aria-hidden="true">&times;</span>
    </x-icon-button>
</div>
