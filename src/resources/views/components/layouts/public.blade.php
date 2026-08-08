{{--
    <x-layouts.public> — squelette de document des pages publiques (Story 1.13, AC1/AC3/AC4/AC7).

    Composant ANONYME : pas de classe PHP. UX-DR-64 — « slots pour la
    flexibilité, props pour la configuration, pas d'over-abstraction ».

    ⚠️ C'est ce layout qui charge Alpine, via @livewireScripts. Tant qu'il
    n'existait pas, tout AC de comportement client se validait sans que rien
    ne s'exécute — le faux-vert qui a fait réordonner l'Epic 1 (ADR-0011).

    RÈGLE 1 (tokens.css) : aucune couleur en dur, aucune arbitrary value.

    ─────────────────────────────────────────────────────────────────────────
    LES DEUX PILES SONT DES POINTS D'INSERTION, ET ELLES SONT VIDES (AC7)

      @stack('head')      → la Story 1.9 y poussera les <link rel="preload">
                            de police. Elle est rendue AVANT @vite : un preload
                            déclaré après le script qui déclenche le chargement
                            arrive trop tard pour servir à quoi que ce soit.
      @stack('body-end')  → l'Epic 4 y poussera le bandeau de consentement.

    Rien n'est rendu ici pour l'une ni pour l'autre. Un preload de police
    pointant vers un woff2 absent, ou un bandeau factice, seraient un
    échafaudage PLUS PERMISSIF que la production : les stories qui les doivent
    se valideraient contre du décor (ADR-0011).

    ─────────────────────────────────────────────────────────────────────────
    POURQUOI LE <header> N'A PAS DE border-b

    L'AC4 exige une hauteur CALCULÉE de 48px / 56px. Or `getComputedStyle().height`
    renvoie la hauteur du CONTENU, jamais celle de la boîte de bordure : avec
    `border-b`, le même header mesurerait 47px / 55px et l'assertion devrait
    citer un nombre que rien dans le design ne justifie. La séparation est donc
    portée par le changement de surface (`bg-surface` sur `bg-bg`), qui est le
    vocabulaire des 90 % monochromes de la RÈGLE 2 — pas un contournement.
--}}

@props([
    'title' => null,
])

{{--
    `lang` descend du locale pour UNE raison précise, et il faut la dire : la
    Story 1.12 a besoin d'un locale unique (`Carbon::setLocale`), et graver `fr`
    ici en créerait un second. Ce n'est PAS le début d'une i18n.

    Conséquence assumée : tout le texte du chrome ci-dessous est du français en
    dur. Sous un autre locale — la mutation `de_DE` que fait le test de l'AC1 —
    le document annonce une langue qu'il ne parle pas. C'est sans conséquence
    tant que v1 est FR-only (UX-DR, `APP_LOCALE=fr` dans .env et .env.example).
    Le jour où une seconde langue arrive, ces chaînes passent par `__()` — pas
    avant : des clés de traduction sans fichier `lang/fr` rendraient leur clé
    brute, silencieusement.
--}}
<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">

        <title>{{ $title ?? config('app.name') }}</title>

        @stack('head')

        @vite(['resources/css/app.css', 'resources/js/app.js'])
    </head>
    <body class="bg-bg text-text-primary font-sans min-h-screen">
        {{--
            Premier élément focusable du document, et il DOIT le rester : c'est
            la seule façon d'atteindre le contenu sans traverser le chrome au
            clavier. `sr-only` le retire du flux visuel sans le retirer de
            l'ordre de tabulation ; `focus:not-sr-only` le ramène à l'écran dès
            qu'il est atteint. `focus:` et non `focus-visible:` : un utilisateur
            arrivé là par un moyen que Chromium ne juge pas « clavier » aurait
            sinon un lien focalisé et invisible.
        --}}
        <a
            href="#main"
            class="sr-only focus:not-sr-only focus:absolute focus:start-4 focus:top-4 focus:z-50 focus:rounded-md focus:bg-surface focus:px-4 focus:py-2 focus:text-sm focus:text-text-primary focus:outline-hidden focus:ring-2 focus:ring-lava/40"
        >
            Aller au contenu
        </a>

        <header
            data-role="site-header"
            class="sticky top-0 z-40 flex h-12 items-center bg-surface px-4 lg:h-14 lg:px-6"
        >
            <a href="/" class="text-sm font-medium tracking-tight text-text-primary">
                {{ config('app.name') }}
            </a>
        </header>

        {{--
            `tabindex="-1"` n'est PAS décoratif, et ne met pas <main> dans l'ordre
            de tabulation (valeur négative = focusable par programme seulement).

            Sans lui, activer le lien de saut déplace le DÉFILEMENT sans déplacer
            le FOCUS sur plusieurs moteurs — Safari/VoiceOver en tête. La
            tabulation suivante repart alors du header, c'est-à-dire exactement
            ce que le lien existe pour éviter : l'affordance a l'air de marcher,
            et ne marche pas. Trouvé en revue de code le 2026-08-08 — l'AC3
            vérifiait que le lien est premier focusable et qu'il devient visible,
            jamais ce qu'il fait quand on l'ACTIVE. Le garde-fou correspondant
            (Tab puis Entrée, focus lu ensuite) vit dans tests/Browser.
        --}}
        <main id="main" tabindex="-1" class="px-4 py-12 lg:px-6">
            {{ $slot }}
        </main>

        <footer data-role="site-footer" class="px-4 py-8 text-sm text-text-secondary lg:px-6">
            {{ config('app.name') }}
        </footer>

        @stack('body-end')

        @livewireScripts
    </body>
</html>
