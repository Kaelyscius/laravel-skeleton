{{--
    <x-layouts.minimal> — document dépouillé (Story 1.13, AC2).

    Destiné aux écrans qui n'ont pas de chrome à offrir : pages d'erreur, écran
    offline (ADR-0012), futures pages d'authentification. Le CÂBLAGE de ces
    écrans sur ce layout n'est PAS dans cette story — seul le layout l'est.

    Ce qu'il ne rend pas est aussi important que ce qu'il rend : NI <header>,
    NI <footer>. Un garde-fou d'ABSENCE le tient (tests/Feature/LayoutsTest.php),
    sans quoi ce fichier dériverait vers une copie de `public` et « minimal »
    ne voudrait plus rien dire.

    Il charge la même CSS que <x-layouts.public> : une page d'erreur qui perd
    le design system est une seconde source de vérité visuelle. Il ne charge en
    revanche PAS @livewireScripts — rien d'interactif n'y vit, et une page
    d'erreur qui dépend d'un bundle JS est une page d'erreur fragile.

    ─────────────────────────────────────────────────────────────────────────
    ⚠️ CE QUI EST SILENCIEUSEMENT INERTE ICI (revue de code du 2026-08-08)

    Pas de @livewireScripts VEUT DIRE pas d'Alpine. Tout composant qui dépend
    d'Alpine est donc mort dans ce layout, SANS erreur console et SANS test
    rouge :

      <x-toast>  → s'affiche, ne se ferme jamais seul, bouton inopérant.
                   (`x-data="toast"` ne résout rien, `x-show="open"` non plus)

      <x-time-relative> → affiche le libellé du serveur et ne le rafraîchit
                   JAMAIS. (Story 1.12) Le plus sournois des deux : rien n'a
                   l'air cassé, la durée est simplement fausse à partir de la
                   minute suivante — « il y a 1 minute » pour l'éternité.

    `app.js` est bien chargé par @vite — il enregistre sa fabrique sur
    `alpine:init`, un évènement qui n'est jamais émis ici. Le bundle est donc
    servi pour rien : c'est le prix d'une seule feuille d'entrée, assumé.

    ⛔ AUCUN GARDE-FOU N'EXISTE POUR CE PIÈGE, ET C'EST DÉLIBÉRÉ : aucune page
    n'utilise encore ce layout (le câblage des pages d'erreur est hors AC de la
    Story 1.13). Le contenu vient du SLOT, donc de l'appelant : « minimal ne
    rend aucun x-data » n'est pas une propriété de ce fichier, c'est une
    propriété de pages qui n'existent pas. Un test écrit aujourd'hui serait vert
    par vacuité — « l'affirmation précède son référent », dans l'autre sens.
    Le garde-fou appartient à la story qui câblera les pages d'erreur ; elle en
    hérite via deferred-work.md (« Trouvé en revue de code de la Story 1.13 »).
--}}

@props([
    'title' => null,
])

<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">

        <title>{{ $title ?? config('app.name') }}</title>

        @stack('head')

        @vite(['resources/css/app.css', 'resources/js/app.js'])
    </head>
    <body class="bg-bg text-text-primary font-sans flex min-h-screen items-center justify-center p-6">
        <main class="max-w-measure w-full">
            {{ $slot }}
        </main>
    </body>
</html>
