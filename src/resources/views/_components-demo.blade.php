{{--
    Galerie des composants de base (Story 1.11, T9).

    Cette page n'est PAS une page produit : c'est le support des tests
    navigateur. Elle n'est enregistrée qu'en `local` et `testing` (voir
    routes/web.php), parce qu'un pseudo-état ne s'observe que dans un vrai
    moteur de rendu.

    Pas de layout : les layouts arrivent en Story 1.13. Le document est donc
    autonome, sur le modèle de welcome.blade.php.

    ⚠️ La section #focus-lab doit rester LA DERNIÈRE et ses éléments contigus :
    les tests y naviguent à la touche Tab depuis #focus-start pour obtenir un
    vrai :focus-visible (un focus programmatique ne le déclenche pas sur un
    bouton). Insérer un focusable entre eux casserait l'ordre de tabulation.

    @var \App\Core\Models\Streamer $streamer
--}}
<!DOCTYPE html>
<html lang="fr">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Composants de base — {{ config('app.name', 'Laravel') }}</title>
        @vite(['resources/css/app.css', 'resources/js/app.js'])
    </head>
    <body class="bg-bg text-text-primary font-sans min-h-screen p-8">
        <main class="mx-auto max-w-measure space-y-12">
            <header class="space-y-2">
                <h1 id="page-title" class="text-2xl font-medium">Composants de base</h1>
                <p class="text-text-secondary leading-prose">
                    Story&nbsp;1.11. Page de support des tests navigateur, absente en production.
                </p>
            </header>

            <section id="section-buttons" class="space-y-4">
                <h2 class="font-mono text-sm text-text-secondary uppercase">Boutons</h2>

                <div class="flex flex-wrap items-center gap-4">
                    <x-button id="btn-primary" variant="primary">Primaire</x-button>
                    <x-button id="btn-secondary" variant="secondary">Secondaire</x-button>
                    <x-button id="btn-ghost" variant="ghost">Ghost</x-button>
                    <x-button id="btn-disabled" variant="primary" :disabled="true">Désactivé</x-button>
                    <x-button id="btn-loading" variant="primary" :loading="true">Chargement</x-button>
                </div>
            </section>

            <section id="section-cards" class="space-y-4">
                <h2 class="font-mono text-sm text-text-secondary uppercase">Cartes</h2>

                <div class="grid gap-4">
                    <x-card id="card-default">
                        <p class="text-text-secondary">Carte au repos, survolable.</p>
                    </x-card>

                    <x-card id="card-selected" :selected="true">
                        <p class="text-text-secondary">Carte sélectionnée.</p>
                    </x-card>
                </div>
            </section>

            <section id="section-badges" class="space-y-4">
                <h2 class="font-mono text-sm text-text-secondary uppercase">Badges</h2>

                <div class="flex flex-wrap items-center gap-3">
                    <x-badge id="badge-neutral" variant="neutral">Neutre</x-badge>
                    <x-badge id="badge-lava" variant="lava">LIVE</x-badge>
                    <x-badge id="badge-ok" variant="ok">OK</x-badge>
                    <x-badge id="badge-warn" variant="warn">Attention</x-badge>
                    <x-badge id="badge-err" variant="err">Erreur</x-badge>
                </div>
            </section>

            <section id="section-dividers" class="space-y-6">
                <h2 class="font-mono text-sm text-text-secondary uppercase">Séparateurs</h2>

                <x-divider id="divider-plain" />
                <x-divider id="divider-labelled">Suite</x-divider>
            </section>

            <section id="section-toasts" class="space-y-3">
                <h2 class="font-mono text-sm text-text-secondary uppercase">Notifications</h2>

                <x-toast id="toast-success" type="success">Enregistré.</x-toast>
                <x-toast id="toast-info" type="info">Pour information.</x-toast>
                <x-toast id="toast-warning" type="warning">Attention à ceci.</x-toast>
                <x-toast id="toast-error" type="error">Quelque chose a échoué.</x-toast>
            </section>

            <section id="section-streamer" class="space-y-4">
                <h2 class="font-mono text-sm text-text-secondary uppercase">Streamer</h2>

                {{--
                    AC8 : tout vient de la base, rien n'est écrit en dur ici.

                    Le CTA est rendu en <button> porteur de l'URL, et non en <a>
                    enveloppant un bouton : un élément interactif imbriqué dans
                    un autre est du HTML invalide. Un vrai CTA cliquable est un
                    lien, mais <x-button href> n'est pas dans le périmètre de
                    cette story — il appartiendra au module qui possède l'écran
                    (Epic 4/5). Cette page est un support de test, pas une page
                    produit : elle prouve que les champs sont consommés.
                --}}
                @if (filled($streamer->cta_text) && filled($streamer->cta_url))
                    <x-button id="streamer-cta" variant="primary" data-cta-url="{{ $streamer->cta_url }}">
                        {{ $streamer->cta_text }}
                    </x-button>
                @endif

                @php
                    $socialLinks = $streamer->orderedSocialLinks();
                @endphp

                @if ($socialLinks !== [])
                    <ul id="streamer-social-links" class="flex flex-wrap gap-3">
                        @foreach ($socialLinks as $link)
                            <li>
                                {{-- rel="noopener noreferrer" : ces liens sortent
                                     vers des domaines tiers configurés par le
                                     streamer. Sans noopener, la page cible peut
                                     manipuler window.opener. --}}
                                <a href="{{ $link['url'] }}" data-role="social-link"
                                   rel="noopener noreferrer"
                                   class="text-sm text-text-secondary underline transition hover:text-text-primary">
                                    {{ $link['label'] }}
                                </a>
                            </li>
                        @endforeach
                    </ul>
                @endif
            </section>

            <section id="focus-lab" class="space-y-4">
                <h2 class="font-mono text-sm text-text-secondary uppercase">Anneau de focus</h2>

                <div class="flex flex-wrap items-center gap-4">
                    <a id="focus-start" href="#focus-lab" class="text-sm text-text-secondary underline">
                        Point de départ de la tabulation
                    </a>
                    <x-button id="fl-button" variant="secondary">Bouton focusable</x-button>
                    <x-icon-button id="fl-icon" aria-label="Bouton icône focusable">
                        <span aria-hidden="true">&bull;</span>
                    </x-icon-button>
                </div>
            </section>
        </main>
    </body>
</html>
