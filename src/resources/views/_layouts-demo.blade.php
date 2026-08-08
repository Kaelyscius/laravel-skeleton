{{--
    Page de démonstration de <x-layouts.public> (Story 1.13, T7).

    Ce n'est PAS une page produit : c'est le support des tests navigateur. Elle
    n'est enregistrée qu'en `local` et `testing` (voir routes/web.php), parce
    qu'une hauteur calculée, un `position: sticky` après défilement, une
    préférence média et une fermeture différée ne s'observent que dans un vrai
    moteur de rendu.

    ⛔ NE PAS fusionner avec `_components-demo.blade.php`. Les 8 tests navigateur
    de la Story 1.11 dépendent de son ordre de tabulation (#focus-lab dernier et
    contigu) : y insérer un header — donc un focusable — les casserait pour un
    gain nul.

    Ce que chaque bloc sert à observer :

      #motion-probe   — AC5. Porte `transition` seul, donc sa durée vient de
                        --default-transition-duration, elle-même branchée sur le
                        token --duration-default (app.css). Sous
                        `prefers-reduced-motion: reduce`, elle doit tomber à une
                        valeur négligeable.
      #toast-short    — AC6. Durée courte : doit disparaître seul.
      #toast-long     — AC6. Durée longue : doit être ENCORE LÀ au même instant.
                        C'est cette seconde moitié qui rend l'assertion non-vide
                        — sans elle, un toast masqué dès le chargement passerait.
      #toast-dismiss  — AC6. Durée longue, fermé au bouton : prouve que le
                        bouton n'attend pas la durée.
      #toast-broken   — AC6, CHEMIN D'ERREUR (revue de code du 2026-08-08).
                        Durée invalide : ne doit JAMAIS se fermer seul, et doit
                        rester fermable à la main. Écrit en HTML brut à dessein
                        — `<x-toast>` refuse de le rendre (garde PHP sur la
                        durée), c'est bien pour ça que le chemin d'erreur de
                        `app.js` n'était exercé par rien.
      #filler         — AC4. De quoi faire défiler la page, sans quoi
                        `position: sticky` n'est jamais mis à l'épreuve.
--}}
<x-layouts.public title="Démonstration des layouts">
    <div class="mx-auto max-w-measure space-y-12">
        <section id="section-intro" class="space-y-2">
            <h1 id="page-title" class="text-2xl font-medium">Layouts</h1>
            <p class="text-text-secondary leading-prose">
                Story&nbsp;1.13. Page de support des tests navigateur, absente en production.
            </p>
        </section>

        <section id="section-motion" class="space-y-4">
            <h2 class="font-mono text-sm text-text-secondary uppercase">Mouvement</h2>

            <div
                id="motion-probe"
                data-role="motion-probe"
                class="size-8 rounded-md bg-surface transition"
            ></div>
        </section>

        <section id="section-toasts" class="space-y-3">
            <h2 class="font-mono text-sm text-text-secondary uppercase">Notifications</h2>

            <x-toast id="toast-short" type="info" :duration="900">Durée courte.</x-toast>
            <x-toast id="toast-long" type="success" :duration="60000">Durée longue.</x-toast>
            <x-toast id="toast-dismiss" type="warning" :duration="60000">Fermable à la main.</x-toast>

            {{--
                ⚠️ HTML BRUT, ET C'EST LE POINT. `<x-toast>` lève une
                InvalidArgumentException sur une durée non numérique : impossible
                de produire ce cas par le composant. Or c'est exactement pour ça
                que les deux branches fail-loud de `app.js` n'étaient exercées
                par rien — une garde jamais vue rouge est une promesse sans
                référent.

                Ce n'est PAS un échafaudage plus permissif que la production
                (ADR-0011) : ça ne simule aucune fonctionnalité absente, ça
                exerce un chemin d'erreur réel du code livré.
            --}}
            <div
                id="toast-broken"
                x-data="toast"
                x-show="open"
                role="status"
                data-toast-duration="pas-un-nombre"
                class="flex w-full items-start gap-3 rounded-lg border border-border bg-surface p-4 text-sm text-text-secondary"
            >
                <span class="mt-1.5 size-2 shrink-0 rounded-full bg-current" aria-hidden="true"></span>

                <div class="flex-1 text-text-primary">Durée invalide — chemin d'erreur.</div>

                <x-icon-button aria-label="Fermer la notification" data-toast-dismiss>
                    <span aria-hidden="true">&times;</span>
                </x-icon-button>
            </div>
        </section>

        <section id="filler" class="space-y-4">
            <h2 class="font-mono text-sm text-text-secondary uppercase">Matière à défiler</h2>

            @for ($paragraph = 1; $paragraph <= 30; $paragraph++)
                <p class="text-text-secondary leading-prose">
                    Paragraphe {{ $paragraph }}. Le header est le seul élément sticky du site
                    (UX spec §Layout principles) : sans page défilable, la propriété CSS serait
                    déclarée sans jamais être mise à l'épreuve.
                </p>
            @endfor
        </section>
    </div>
</x-layouts.public>
