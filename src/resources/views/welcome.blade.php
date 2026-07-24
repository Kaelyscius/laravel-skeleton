<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">

        <title>{{ config('app.name', 'Laravel') }}</title>

        {{--
            Placeholder assumé. La vraie homepage est le module Public (Epic 4),
            posée sur les layouts de la Story 1.13.

            Cette page remplace celle du starter kit Laravel, qui contredisait le
            design system qu'elle était censée présenter : police Instrument Sans
            chargée depuis fonts.bunny.net (tiers), ~40 couleurs hex en dur en
            arbitrary values, et une bascule claire/sombre via prefers-color-scheme
            alors qu'UX-DR-45 verrouille le dark-only. Re-skinner 277 lignes de
            marketing Laravel n'aurait rien apporté : on ne garde ici que ce qui
            prouve que la chaîne tokens -> @theme -> utilities tient de bout en bout.

            Aucune couleur en dur : tout passe par les utilities issues des tokens.
        --}}
        @vite(['resources/css/app.css', 'resources/js/app.js'])
    </head>
    <body class="bg-bg text-text-primary font-sans min-h-screen flex items-center justify-center p-6">
        <main class="max-w-measure w-full">
            <div class="bg-surface border border-border rounded-lg p-8">
                <p class="font-mono text-sm text-text-secondary mb-2">{{ config('app.name', 'Laravel') }}</p>

                <h1 class="text-2xl mb-4">Le squelette tourne.</h1>

                <p class="text-text-secondary leading-prose">
                    Page d'attente. La homepage réelle arrive avec le module Public,
                    construite sur les composants et layouts d'Epic&nbsp;1.
                </p>
            </div>
        </main>
    </body>
</html>
