{{--
    Page de démonstration des faces self-hostées (Story 1.9, T8).

    Ce n'est PAS une page produit : c'est le support des tests navigateur. Elle
    n'est enregistrée qu'en `local` et `testing` (voir routes/web.php).

    ⛔ ELLE DOIT EMPLOYER CHAQUE FACE DE LA TABLE, ET C'EST TOUTE SA RAISON
    D'ÊTRE. `font-display: swap` ne déclenche le téléchargement d'une face qu'à
    son USAGE : une face déclarée par un @font-face que rien n'emploie reste au
    statut `unloaded`, et le preload seul ne la charge pas non plus. Sans un
    élément par face, l'AC6 n'aurait rien à observer — et son test serait vert
    par vacuité sur trois faces sur quatre.

    Une section par face de resources/fonts.json :

      #face-sans-400  — la graisse par défaut du corps de texte.
      #face-sans-500  — `font-medium`. La face la plus silencieuse des quatre :
                        sans elle, l'algorithme CSS résout 500 vers 400 SANS
                        synthèse, le rendu est indiscernable du texte normal, et
                        rien ne rougit. Elle est employée 8 fois dans le code
                        livré, dont 4 dans des composants déjà `done`.
      #face-sans-600  — `font-semibold`, les titres H1/H2 de l'échelle UX.
      #face-mono-400  — `font-mono`, la texture temporelle de la Story 1.12.

    ⛔ NE PAS fusionner avec _components-demo, _layouts-demo, _layouts-demo-minimal
    ou _time-demo : leurs tests navigateur dépendent de leur ordre de tabulation
    et de leurs sélecteurs.
--}}
<x-layouts.public title="Démonstration des polices">
    <div class="mx-auto max-w-measure space-y-10">
        <section id="section-intro" class="space-y-2">
            <h1 id="page-title" class="text-2xl font-semibold">Polices</h1>
            <p class="text-text-secondary leading-prose">
                Story&nbsp;1.9. Page de support des tests navigateur, absente en production.
            </p>
        </section>

        <section id="face-sans-400" data-role="face" class="space-y-1">
            <h2 class="font-mono text-sm text-text-secondary uppercase">IBM Plex Sans 400</h2>
            {{--
                ⚠️ `font-normal` est ÉCRIT, alors que 400 est déjà la graisse par
                défaut. Le test T8 exigeait auparavant `leading-prose` comme témoin
                de cette face — une utility de HAUTEUR DE LIGNE, présente dans les
                quatre sections : elle ne disait rien de la graisse, et l'assertion
                ne pouvait pas échouer. Relevé à la revue du 2026-08-09. Le témoin
                doit être la chose observée, pas une chose qui l'accompagne.
            --}}
            <p class="font-normal leading-prose">
                Portez ce vieux whisky au juge blond qui fume — œuvre, çà et là, 12&nbsp;€.
            </p>
        </section>

        <section id="face-sans-500" data-role="face" class="space-y-1">
            <h2 class="font-mono text-sm text-text-secondary uppercase">IBM Plex Sans 500</h2>
            <p class="font-medium leading-prose">
                Portez ce vieux whisky au juge blond qui fume — œuvre, çà et là, 12&nbsp;€.
            </p>
        </section>

        <section id="face-sans-600" data-role="face" class="space-y-1">
            <h2 class="font-mono text-sm text-text-secondary uppercase">IBM Plex Sans 600</h2>
            <p class="font-semibold leading-prose">
                Portez ce vieux whisky au juge blond qui fume — œuvre, çà et là, 12&nbsp;€.
            </p>
        </section>

        <section id="face-mono-400" data-role="face" class="space-y-1">
            <h2 class="font-mono text-sm text-text-secondary uppercase">IBM Plex Mono 400</h2>
            <p class="font-mono leading-prose">
                Portez ce vieux whisky au juge blond — 0O 1lI 12&nbsp;€.
            </p>
        </section>
    </div>
</x-layouts.public>
