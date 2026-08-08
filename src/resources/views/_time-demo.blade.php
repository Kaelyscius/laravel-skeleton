{{--
    Page de démonstration des composants time-as-texture (Story 1.12, T10).

    Ce n'est PAS une page produit : c'est le support des tests navigateur. Elle
    n'est enregistrée qu'en `local` et `testing` (voir routes/web.php), parce
    qu'un rafraîchissement Alpine, une famille de police calculée et une largeur
    qui ne bouge pas ne s'observent que dans un vrai moteur de rendu.

    ⛔ NE PAS fusionner avec `_components-demo.blade.php` ni `_layouts-demo.blade.php` :
    ce sont EUX qui portent l'ordre de tabulation et les ancres de temporisation
    dont dépendent les tests navigateur de la Story 1.13.

    ⚠️ Cette page-ci n'a ni l'un ni l'autre. La rédaction d'origine recopiait
    l'avertissement du fichier voisin (« 20 tests navigateur dépendent de leur
    ordre de tabulation… ») : faux ici, où 9 tests lisent des libellés, des
    compteurs et des valeurs calculées, et aucun ne tabule. Corrigé à la revue du
    2026-08-08 — un ⛔ qui crie faux est un ⛔ qu'on cesse de lire, et il compte
    vraiment dans le fichier d'à côté.

    Ce que chaque bloc sert à observer :

      #time-fast        — AC6/AC7. Intervalle court (250 ms) : c'est lui qui rend
                          le rafraîchissement OBSERVABLE. Attendre 60 s n'est pas
                          une option ; la valeur par défaut se vérifie
                          structurellement, dans le test Feature.
      #time-fast-short  — AC7. Le même, en forme COURTE — celle des écrans de
                          référence. Sans lui, la moitié réellement employée du
                          formatage dériverait librement.
      #time-slow        — AC6. Intervalle par défaut (60 000 ms) : doit être
                          ENCORE au libellé du serveur quand #time-fast a déjà
                          bougé. C'est cette seconde moitié qui rend l'assertion
                          non-vide — « le texte a changé » serait vrai d'un
                          rechargement, d'un Alpine qui plante, d'un sélecteur
                          qui ne trouve rien.
      #time-old         — AC6. Daté de plusieurs mois, intervalle court : AUCUN
                          tick ne doit être programmé. Un libellé en semaines ne
                          peut pas changer pendant une session.
      #time-absolute /
      #time-dual /
      #time-since       — AC8. Support des mesures typographiques sur les 4
                          composants, pas seulement sur celui qui bouge.
      #time-broken-*    — AC6, CHEMINS D'ERREUR. Écrits en HTML brut à dessein :
                          <x-time-relative> REFUSE de les produire (ses gardes
                          PHP lèvent), et c'est exactement pour ça que les deux
                          branches fail-loud de app.js ne seraient exercées par
                          rien. Leçon directe de la revue de code du 2026-08-08.

    ⚠️ Ce n'est PAS un échafaudage plus permissif que la production (ADR-0011) :
    ça ne simule aucune fonctionnalité absente, ça exerce des chemins d'erreur
    réels du code livré.
--}}
<x-layouts.public title="Démonstration du temps comme texture">
    <div class="mx-auto max-w-measure space-y-12">
        <section id="section-intro" class="space-y-2">
            <h1 id="page-title" class="text-2xl font-medium">Le temps comme texture</h1>
            <p class="text-text-secondary leading-prose">
                Story&nbsp;1.12. Page de support des tests navigateur, absente en production.
            </p>
        </section>

        <section id="section-relative" class="space-y-3">
            <h2 class="font-mono text-sm text-text-secondary uppercase">Durées relatives</h2>

            <p><x-time-relative id="time-fast" :datetime="$ticking" :refresh="250" /></p>
            <p><x-time-relative id="time-fast-short" :datetime="$ticking" :refresh="250" short /></p>
            <p><x-time-relative id="time-slow" :datetime="$ticking" /></p>
            <p><x-time-relative id="time-old" :datetime="$ancient" :refresh="250" /></p>
        </section>

        <section id="section-other" class="space-y-3">
            <h2 class="font-mono text-sm text-text-secondary uppercase">Dates, seuils, anciennetés</h2>

            <p><x-time-absolute id="time-absolute" :datetime="$published" /></p>
            <p><x-time-dual id="time-dual" :published="$published" :updated="$updated" /></p>
            <p><x-time-since id="time-since" :datetime="$ancient" /></p>
        </section>

        <section id="section-broken" class="space-y-3">
            <h2 class="font-mono text-sm text-text-secondary uppercase">Chemins d'erreur</h2>

            {{--
                HTML BRUT n°1 — intervalle illisible.

                La garde doit signaler ET NE PROGRAMMER AUCUN INTERVALLE, sans
                pour autant emporter le recalcul initial du libellé : les deux
                mécanismes n'ont aucune raison de tomber ensemble (leçon de la
                Story 1.13, où une garde en avait désarmé une autre).

                Le texte ci-dessous est un MARQUEUR, pas un libellé : s'il est
                encore là après l'initialisation, c'est que le recalcul initial
                a été emporté par la garde sur l'intervalle.

                ⚠️ setInterval(fn, NaN) ne se contente pas d'échouer : il tourne
                à intervalle minimal, en continu. Cette garde empêche une boucle
                chaude, elle n'est pas défensive par principe.
            --}}
            <p>
                <time
                    id="time-broken-refresh"
                    datetime="{{ $recent->toIso8601String() }}"
                    data-temporal
                    data-time-short="0"
                    data-time-refresh="pas-un-nombre"
                    x-data="timeRelative"
                    x-text="label"
                    class="inline-block min-w-temporal font-mono text-sm tabular-nums tracking-tight text-text-secondary"
                >LIBELLE-SERVEUR-A-REMPLACER</time>
            </p>

            {{--
                HTML BRUT n°2 — instant illisible.

                Le libellé rendu par le serveur doit être LAISSÉ INTACT. Un
                composant qui viderait son texte sur une date cassée remplacerait
                une information périmée par rien du tout.
            --}}
            <p>
                <time
                    id="time-broken-iso"
                    datetime="pas-une-date"
                    data-temporal
                    data-time-short="0"
                    data-time-refresh="250"
                    x-data="timeRelative"
                    x-text="label"
                    class="inline-block min-w-temporal font-mono text-sm tabular-nums tracking-tight text-text-secondary"
                >texte du serveur intact</time>
            </p>
        </section>
    </div>
</x-layouts.public>
