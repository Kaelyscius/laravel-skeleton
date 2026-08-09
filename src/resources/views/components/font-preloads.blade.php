{{--
    <x-font-preloads /> — les <link rel="preload"> ET les @font-face des faces
    IBM Plex self-hostées (Story 1.9, AC4 + AC5).

    UN SEUL FICHIER, INCLUS PAR LES DEUX LAYOUTS ET PAR welcome.blade.php.
    `<x-layouts.minimal>` charge la même CSS que `<x-layouts.public>` — une page
    d'erreur qui perd le design system est une seconde source de vérité visuelle,
    et une page d'erreur qui perd la police l'est tout autant.

    ─────────────────────────────────────────────────────────────────────────
    ⚠️ POURQUOI LES @font-face SONT ICI ET PLUS DANS resources/css/fonts.css

    Ils y étaient, écrits à la main, pour une bonne raison : c'était le seul
    artefact NON dérivé de la table, donc le seul capable d'en diverger — et
    c'est cette divergence que le test de l'AC4 attrapait.

    Le prix en était des URL en RACINE ABSOLUE (`url('/fonts/…')`). Une feuille
    statique ne peut pas interpoler un préfixe, et une url() relative serait
    happée par Vite, qui la hacherait vers build/assets/ — ce que l'AC4 interdit
    précisément. Conséquence, relevée à la revue du 2026-08-09 : un déploiement
    sous https://hôte/app/ donne quatre 404 SILENCIEUX, et `font-display: swap`
    rend alors la page en fonte système, correcte et muette. Aucun test serveur
    ne le voit — ils comparent des chaînes, ne résolvent pas d'URL. Or le
    fork-streamer est l'audience explicite d'ADR-0001.

    ⛔ ET CE N'ÉTAIT PAS DIVISIBLE EN DEUX MOITIÉS. Passer le seul `href` par
    asset() en laissant l'url() en racine aurait fait viser DEUX chemins
    différents au preload et au @font-face : le navigateur ne les rapproche
    jamais, donc second téléchargement complet du même fichier, sans erreur ni
    message. C'est le piège n°1 ci-dessous, fabriqué par son propre correctif.

    Les deux côtés dérivent donc de la table ET passent par `asset()`. Ce que
    l'AC4 garde désormais : qu'aucune propriété ni aucune face ne manque au
    rendu. Ce qu'une dérivation ne peut PAS garder — la table qui change sans
    décision — est gardé par le test « sert 4 faces et n'en précharge que 3 »,
    dont les valeurs sont écrites en dur.

    ─────────────────────────────────────────────────────────────────────────
    LES QUATRE ATTRIBUTS DU PRELOAD, ET CE QUE CHACUN COÛTE S'IL MANQUE

      rel="preload"     — sans lui, la police n'est découverte qu'à la lecture
                          du @font-face par le moteur CSS, soit après le CSS.
      as="font"         — sans lui, le navigateur ne sait pas quelle priorité
                          donner, et ne peut pas rapprocher le preload de la
                          requête réelle : le fichier est téléchargé DEUX FOIS.
      type="font/woff2" — laisse le navigateur ignorer le preload s'il ne sait
                          pas lire le format, plutôt que télécharger pour rien.
      crossorigin       — SANS VALEUR (équivaut à `anonymous`). Une police est
                          TOUJOURS demandée en mode CORS. Un preload sans
                          `crossorigin` n'est jamais rapproché de cette
                          requête : second téléchargement complet du même
                          fichier, sans erreur ni message console.

    ⚠️ Toutes les faces ne sont PAS préchargées. La graisse 500 ne l'est pas :
    elle n'est pas garantie au-dessus de la ligne de flottaison, et Chrome
    avertit sur un preload non consommé dans les premières secondes. Le
    booléen vit dans la table, pas ici.

    ⚠️ font-display: swap SUR CHACUNE (UX-DR-42). FOUT assumé, jamais de texte
    invisible : `block` ou le défaut `auto` masquent le texte jusqu'à 3 s sur 4G
    mobile, et une page qui ne dit rien pendant trois secondes est cassée même
    si elle finit par être jolie.

    ⛔ PAS DE unicode-range, ET C'EST UN CHOIX. Il sert à ÉVITER le
    téléchargement d'un sous-ensemble inutile — or nous préchargeons, donc nous
    téléchargeons de toute façon. Le sous-ensemble `latin` couvre le français :
    U+0000-00FF (lettres accentuées), U+0152-0153 (Œ œ), U+2000-206F
    (apostrophe typographique, tiret cadratin, et l'espace insécable posée par
    la Story 1.12 dans <x-time-dual>), U+20AC (€). Un caractère absent retombe
    glyphe par glyphe sur la famille suivante de --font-sans.

    ⛔ NE PAS revenir à `@import '@fontsource/ibm-plex-sans/latin-400.css'` —
    trois défauts, vérifiés sur le paquet 5.3.0 dépaqueté :
      1. Vite hache les url() relatives : le href du preload redevient
         inconnaissable à l'écriture du layout.
      2. Le `src` amont liste aussi un `.woff` que nous ne copions pas : une URL
         morte en production, sans erreur (le navigateur prend le woff2, listé
         en premier, et ne demande jamais le second).
      3. `400.css` sans préfixe de sous-ensemble déclare SIX @font-face —
         cyrillique, grec, vietnamien, latin-ext… Six fichiers par graisse au
         lieu d'un. (La première rédaction écrivait « sept », dans le bloc même
         qui affirmait avoir tout vérifié. Recompté à la revue du 2026-08-09.)

    ⚠️ LE `nonce` N'EST PAS DÉCORATIF, MÊME AVEC LA CSP ÉTEINTE. Le préréglage
    `Basic` de spatie/laravel-csp pose `style-src 'self' 'nonce-…'` : un <style>
    inline SANS nonce serait bloqué le jour où `CSP_ENABLED` passe à true — donc
    zéro @font-face, page en fonte système, et rien de rouge côté serveur. Le
    poser aujourd'hui coûte une ligne ; le découvrir plus tard coûterait une
    story. La garde `nonce_enabled` évite le second piège : sans elle,
    `CSP_NONCE_ENABLED=false` ferait lever `app('csp-nonce')` sur chaque page.

    ⛔ ET LA GARDE `nonce_enabled` A SON PROPRE PIÈGE, QUI EST REFUSÉ ICI.
    Relevé à la SECONDE passe de revue du 2026-08-09. Avec `CSP_ENABLED=true`
    ET `CSP_NONCE_ENABLED=false`, le <style> part sans nonce, `style-src 'self'`
    le bloque, LES QUATRE @font-face DISPARAISSENT, la page rend en fonte
    système — et rien ne rougit côté serveur, parce que le test du nonce ne
    tourne que sous le défaut `true` : il prouve que la configuration sûre est
    sûre. La garde avait donc échangé un échec BRUYANT contre un échec MUET.

    Ce composant SAIT, sous cette combinaison, qu'il ne peut pas garantir que
    ses règles atteignent le navigateur. Il le dit. C'est la doctrine déjà
    écrite dans config/fonts.php : l'échec est bruyant, et c'est voulu.
    Arbitrage Alex du 2026-08-09 — les trois autres voies (émettre le nonce
    inconditionnellement, revenir à une feuille statique, reporter) sont
    écartées dans la story, section Review Findings SECONDE PASSE.

    ⚠️ CE `throw` LÈVE AUSSI DEPUIS <x-layouts.minimal>, QUI EST LE LAYOUT
    D'ERREUR — donc le rendu du gestionnaire d'exception lèverait à son tour :
    500 blanc. C'est assumé, et voici pourquoi, parce que la question se
    reposera :

      - L'échec est TOTAL et IMMÉDIAT. Toute page passe par ce composant, donc
        la première requête après la mise en service échoue. On n'est jamais
        dans le cas « site sain dont seule la page d'erreur casse » — le cas qui
        rend un 500 blanc coûteux, parce qu'il survient des semaines plus tard
        sur un site qui marchait.
      - Le message nomme les DEUX variables et l'effet. Il se diagnostique sans
        lire ce fichier.
      - Le repli envisagé — rendre sans <style> et journaliser — a été REFUSÉ :
        il produit exactement la page en fonte système que cette garde existe
        pour empêcher, et déplace la preuve dans un log que personne ne lit.
        C'est le garde-fou silencieux reconstruit par son propre correctif.

    📌 À ne pas confondre avec le report « un cache de config périmé casse le
    layout d'erreur » (deferred-work.md) : celui-là frappe un déploiement
    CORRECT, ce qui est une tout autre affaire. Celui-ci exige une combinaison
    de configuration délibérée — `config/csp.php` met les deux clés à `true`
    par défaut.
--}}
@if (config('csp.enabled') && ! config('csp.nonce_enabled', true))
    @php
        throw new RuntimeException(
            'CSP_ENABLED=true avec CSP_NONCE_ENABLED=false : le <style> des @font-face partirait '
            ."sans nonce et serait bloqué par `style-src 'self'` (préréglage Basic de spatie/laravel-csp). "
            .'Les quatre faces IBM Plex disparaîtraient en silence, la page rendrait en fonte système. '
            .'Activer CSP_NONCE_ENABLED, ou désactiver CSP_ENABLED.'
        );
    @endphp
@endif

@foreach (config('fonts.faces') as $face)
    @continue(! $face['preload'])
    <link rel="preload" as="font" type="font/woff2" crossorigin href="{{ asset('fonts/' . $face['target']) }}">
@endforeach

<style @if (config('csp.nonce_enabled', true)) @cspNonce @endif>
@foreach (config('fonts.faces') as $face)
@font-face {
    font-family: '{{ $face['family'] }}';
    font-style: normal;
    font-weight: {{ $face['weight'] }};
    font-display: swap;
    src: url('{{ asset('fonts/' . $face['target']) }}') format('woff2');
}
@endforeach
</style>
