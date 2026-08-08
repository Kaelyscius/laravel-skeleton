import './bootstrap';

/*
 * ─────────────────────────────────────────────────────────────────────────────
 * Comportement de <x-toast> — Story 1.13, AC6 + AC8
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * POURQUOI ICI, ET PAS DANS LE TEMPLATE
 *
 * `toast.blade.php` ne contient AUCUNE expression JS : uniquement des
 * références nues (`x-data="toast"`, `x-show="open"`). Toute la logique vit ici,
 * bundlée par Vite, donc servie depuis l'origine — `script-src 'self'` suffira.
 *
 * La CSP n'est PAS allumée aujourd'hui (`CSP_ENABLED=false`, arbitrage PO du
 * 2026-08-09). L'AC8 ne prétend pas l'allumer : elle garantit que le jour où
 * l'Epic 4 le fera, il n'y aura rien à réécrire — donc pas de desserrage sous
 * pression. Coût aujourd'hui : nul.
 *
 * ⚠️ Alpine n'est PAS installé via npm, et ne doit pas l'être : Livewire 4
 * l'embarque dans son bundle. Deux Alpine enregistrés en parallèle est un bug
 * classique. On se greffe donc sur `alpine:init`, l'évènement que Livewire
 * émet avant de démarrer Alpine.
 *
 * ORDRE D'EXÉCUTION, vérifié plutôt que supposé : `livewire.js` est un script
 * classique en fin de <body>, il s'exécute PENDANT l'analyse du document ;
 * `app.js` est un module, donc différé, il s'exécute APRÈS l'analyse mais AVANT
 * `DOMContentLoaded` — instant où Livewire démarre Alpine. L'écouteur ci-dessous
 * est donc en place quand `alpine:init` est émis.
 */

/**
 * Fabrique du composant Alpine `toast`.
 *
 * La durée est LUE DEPUIS LE DOM (`data-toast-duration`), jamais passée en
 * paramètre : `toast.blade.php` promet dans son propre en-tête que la Story 1.13
 * la lira sans toucher au fichier côté PHP. Le composant Blade reste donc la
 * source de vérité de la valeur — y compris de sa validation, qui échoue
 * bruyamment côté serveur sur une durée <= 0 ou non numérique.
 */
const toast = () => ({
    open: true,
    timer: null,

    init() {
        /*
         * ⚠️ LE BOUTON EST CÂBLÉ EN PREMIER, ET L'ORDRE N'EST PAS INDIFFÉRENT.
         *
         * Revue de code du 2026-08-08 : la première rédaction lisait la durée
         * d'abord et sortait par `return` sur une durée invalide — emportant avec
         * elle le câblage du bouton. Un toast à durée cassée devenait donc
         * TOTALEMENT infermable, alors que les deux mécanismes n'ont aucune
         * raison de tomber ensemble. Les deux gardes sont indépendantes, elles
         * échouent indépendamment.
         *
         * Le bouton est câblé ICI, et non par un `@click` inline : c'est la
         * moitié « zéro expression dans le template » de l'AC8.
         */
        const dismiss = this.$el.querySelector('[data-toast-dismiss]');

        if (dismiss === null) {
            console.error('<x-toast> : aucun [data-toast-dismiss] — le toast n\'est pas fermable à la main.');
        } else {
            dismiss.addEventListener('click', () => this.close());
        }

        const raw = this.$el.dataset.toastDuration;
        const duration = Number.parseInt(raw ?? '', 10);

        /*
         * Fail-loud, à l'image des gardes PHP du composant. Un repli silencieux
         * sur une durée par défaut ferait disparaître le toast « à peu près au
         * bon moment » et masquerait un attribut cassé : le test de fermeture
         * resterait vert en n'observant plus ce qu'il croit observer.
         *
         * ⚠️ Ne PAS retirer cette garde au motif que `<x-toast>` valide déjà la
         * durée côté PHP : sans elle, `setTimeout(fn, NaN)` se déclenche
         * IMMÉDIATEMENT — le toast disparaîtrait en silence, ce qui est
         * strictement pire que pas de garde du tout. Chemin exercé par
         * `#toast-broken` dans tests/Browser/LayoutsTest.php.
         */
        if (!Number.isFinite(duration) || duration <= 0) {
            console.error(
                `<x-toast> : data-toast-duration invalide [${raw}] — aucune auto-fermeture programmée.`,
            );

            return;
        }

        this.timer = window.setTimeout(() => this.close(), duration);
    },

    close() {
        /*
         * On annule la minuterie AVANT de fermer. Sans cela, un toast fermé à la
         * main laisse un setTimeout vivant qui réécrit `open` plus tard : sans
         * conséquence visible ici, mais c'est la fuite qui rend les tests de
         * durée non déterministes.
         */
        window.clearTimeout(this.timer);
        this.timer = null;
        this.open = false;
    },

    destroy() {
        window.clearTimeout(this.timer);
    },
});

/*
 * ─────────────────────────────────────────────────────────────────────────────
 * Comportement de <x-time-relative> — Story 1.12, AC6 + AC7
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * LE PROBLÈME, EN UNE PHRASE : le serveur écrit « il y a 59 minutes » avec
 * Carbon, et personne ne le réécrit jamais. Une page laissée ouverte ment.
 *
 * LA SOLUTION REFUSÉE : `<livewire:time-relative>` + `wire:poll.60s`. Une seule
 * source de vérité, mais UNE REQUÊTE HTTP PAR COMPOSANT ET PAR MINUTE sur des
 * pages publiques anonymes — une page d'archive à 12 vignettes ferait 12
 * requêtes/minute/visiteur pour réécrire trois mots.
 *
 * LA SOLUTION RETENUE, ET SON COÛT ASSUMÉ : recalculer côté client. Cela
 * DUPLIQUE le formatage français, et deux implémentations d'une même règle
 * finissent toujours par diverger. Celle-ci divergerait en silence, à l'écran,
 * chez l'utilisateur — d'où les deux garde-fous ci-dessous.
 *
 *  1. CE QUI BORNE LA DUPLICATION. Le JS ne calcule que les libellés qui PEUVENT
 *     changer pendant une session : secondes, minutes, heures, jours. Au-delà de
 *     7 jours, aucun intervalle n'est programmé et le libellé du serveur fait
 *     foi. La surface de dérive passe de 7 unités à 4.
 *
 *     Coût assumé, écrit plutôt que découvert : une page laissée ouverte
 *     plusieurs jours à cheval sur la bascule des 7 jours affichera un libellé
 *     périmé. C'est un arbitrage, pas un oubli.
 *
 *  2. CE QUI PROUVE LA NON-DÉRIVE. Une table de cas unique
 *     (tests/Fixtures/RelativeTimeCases.php) est consommée par DEUX tests : un
 *     test Feature qui assère que Carbon produit chaque libellé, un test
 *     navigateur qui assère que le JS ci-dessous produit le même. Une dérive
 *     d'un seul côté rougit.
 *
 * ⚠️ `numeric: 'always'`, jamais `'auto'` : avec `'auto'`, Intl rend « hier »
 * là où Carbon rend « il y a 1 jour ». C'est la dérive la plus probable de
 * toutes, et elle est invisible sans la table.
 */

/**
 * Unités que le client a le droit de calculer, de la plus fine à la plus large.
 * Le seuil de chacune est la valeur de la SUIVANTE — Carbon TRONQUE (89 s donne
 * « il y a 1 minute », pas « il y a 2 minutes »), donc `Math.floor` et non
 * `Math.round` : mesuré dans le vendor, pas supposé.
 */
const RELATIVE_UNITS = [
    ['day', 86400],
    ['hour', 3600],
    ['minute', 60],
    ['second', 1],
];

/** Au-delà de 7 jours, le libellé du serveur fait foi (voir l'en-tête). */
const RELATIVE_CEILING_SECONDS = 604800;

const relativeFormatters = new Map();

/**
 * Formateur pour la langue RÉELLEMENT annoncée par le document.
 *
 * `document.documentElement.lang` descend de `config('app.locale')` via
 * <x-layouts.public>. Écrire `'fr'` en dur ici créerait une seconde source de
 * vérité sur la langue, qui dériverait dans le seul sens qui ne casse rien :
 * l'affichage.
 *
 * ⚠️ Côté serveur, cette source unique n'a rien coûté à établir : Carbon suit
 * déjà `config('app.locale')` par SON PROPRE provider Laravel
 * (`vendor/nesbot/carbon/src/Carbon/Laravel/ServiceProvider.php`), qui pose la
 * locale au boot et écoute `LocaleUpdated`. L'AC1 demandait un
 * `Carbon::setLocale()` dans AppServiceProvider ; il n'a jamais été livré,
 * parce qu'il n'aurait rien gardé — voir le commentaire d'AppServiceProvider,
 * qui documente la décision. Ne pas lire cette ligne-ci comme s'il existait
 * quelque part un appel serveur à imiter.
 */
const relativeFormatter = (short) => {
    const locale = document.documentElement.lang || 'fr';
    const key = `${locale}|${short ? 'short' : 'long'}`;

    if (!relativeFormatters.has(key)) {
        relativeFormatters.set(
            key,
            new Intl.RelativeTimeFormat(locale, {
                numeric: 'always',
                style: short ? 'short' : 'long',
            }),
        );
    }

    return relativeFormatters.get(key);
};

/**
 * Réconcilie l'espacement d'Intl avec celui de Carbon.
 *
 * ⚠️ TROUVÉ PAR LA TABLE DE L'AC7, ET STRICTEMENT INVISIBLE À L'ŒIL. En forme
 * courte, Intl sépare le nombre de son unité par une ESPACE INSÉCABLE (U+00A0)
 * — « il y a 1 h » — là où Carbon emploie une espace ordinaire (U+0020). Même
 * rendu à l'écran, deux chaînes différentes. Sans la table, cette dérive serait
 * partie en production, et absolument personne n'aurait pu la voir.
 *
 * C'est le SERVEUR qui fait foi : il écrit le premier rendu, et le client n'a
 * pas à « améliorer » la typographie en cours de route — un libellé qui change
 * d'espacement à la minute est un tressautement de plus, pas un raffinement.
 * Le jour où l'insécable est jugée souhaitable, elle se décide côté Carbon,
 * pour les deux à la fois.
 */
/*
 * \u26A0\uFE0F LE REMPLACEMENT EST CIBL\u00C9, PAS GLOBAL \u2014 corrig\u00E9 \u00E0 la revue du 2026-08-08.
 *
 * La d\u00E9rive mesur\u00E9e est LOCALE : une ins\u00E9cable entre le NOMBRE et son unit\u00E9, et
 * seulement en forme courte. Un `/\u00A0/g` effacerait aussi, en silence, toute
 * ins\u00E9cable qu'une future version d'ICU introduirait ailleurs \u2014 typographie
 * fran\u00E7aise avant \u00AB : \u00BB, s\u00E9parateur de milliers. Et la table de l'AC7 ne
 * pourrait pas le voir, puisqu'elle compare des cha\u00EEnes D\u00C9J\u00C0 normalis\u00E9es : une
 * normalisation large est un garde-fou qui avale ce qu'il devrait signaler.
 */
const normalizeSpacing = (label) => label.replace(/(\d)\u00A0/g, '$1 ');

/**
 * Libellé relatif pour une durée écoulée en secondes (positive = passé).
 *
 * Renvoie `null` — et non une chaîne approximative — au-delà du plafond des
 * 7 jours : c'est ce `null` qui dit à l'appelant « ceci ne t'appartient pas »,
 * plutôt que de produire « il y a 7 jours » là où Carbon dit « il y a 1 semaine ».
 */
const relativeLabel = (elapsedSeconds, short) => {
    if (!Number.isFinite(elapsedSeconds)) {
        return null;
    }

    const magnitude = Math.abs(elapsedSeconds);

    if (magnitude >= RELATIVE_CEILING_SECONDS) {
        return null;
    }

    // Sous la seconde, aucune unité ne « matche » : on retombe sur la plus fine
    // plutôt que sur `undefined`, et « il y a 0 seconde » est ce que Carbon rend.
    const [unit, size] = RELATIVE_UNITS.find(([, seconds]) => magnitude >= seconds)
        ?? RELATIVE_UNITS[RELATIVE_UNITS.length - 1];
    const value = Math.floor(magnitude / size);

    return normalizeSpacing(relativeFormatter(short).format(elapsedSeconds < 0 ? value : -value, unit));
};

/**
 * Fabrique du composant Alpine `timeRelative`.
 *
 * L'instant est LU DEPUIS LE DOM à chaque calcul, et il est lu dans l'attribut
 * `datetime` du `<time>` — l'attribut canonique du HTML pour cela. Pas de copie
 * en `data-*` : deux attributs portant le même instant seraient deux sources de
 * vérité.
 */
const timeRelative = () => ({
    label: '',
    ticks: 0,
    timer: null,

    init() {
        /*
         * ⚠️ LE LIBELLÉ DU SERVEUR EST REPRIS AVANT TOUTE AUTRE CHOSE.
         *
         * `x-text="label"` est évalué APRÈS ce init() (Alpine traite `x-data`
         * en premier). Sans cette ligne, un `label` vide effacerait le rendu du
         * serveur — et sur le chemin d'erreur « datetime illisible », il ne
         * resterait plus rien à laisser intact.
         */
        this.label = (this.$el.textContent ?? '').trim();

        /*
         * Posé AVANT les gardes, et c'est ce qui rend l'observation non-vide :
         * un compteur absent voudrait dire « aucun tick » ET « Alpine n'a jamais
         * tourné », deux choses que le test doit pouvoir distinguer.
         */
        this.$el.dataset.timeTicks = '0';

        /*
         * ⚠️ LES DEUX GARDES SONT INDÉPENDANTES, ET L'ORDRE N'EST PAS INDIFFÉRENT.
         *
         * Leçon directe de la Story 1.13 : sa première rédaction sortait par
         * `return` sur une durée invalide et emportait avec elle le câblage du
         * bouton de fermeture. Ici, un `data-time-refresh` cassé ne doit PAS
         * empêcher le recalcul initial du libellé — les deux mécanismes n'ont
         * aucune raison de tomber ensemble. La garde signale, puis on continue.
         */
        const rawRefresh = this.$el.dataset.timeRefresh;
        const refresh = Number.parseInt(rawRefresh ?? '', 10);
        const refreshIsUsable = Number.isFinite(refresh) && refresh > 0;

        if (!refreshIsUsable) {
            console.error(
                `<x-time-relative> : data-time-refresh invalide [${rawRefresh}] — aucun rafraîchissement programmé.`,
            );
        }

        const raw = this.$el.getAttribute('datetime');

        if (!Number.isFinite(Date.parse(raw ?? ''))) {
            console.error(
                `<x-time-relative> : datetime illisible [${raw}] — le libellé rendu par le serveur est laissé intact.`,
            );

            return;
        }

        const fresh = this.compute();

        if (fresh !== null) {
            this.label = fresh;
        }

        /*
         * Aucun intervalle au-delà de 7 jours (`compute()` renvoie `null`) : un
         * libellé en semaines, mois ou années ne peut pas changer pendant une
         * session, et un setInterval qui réécrit la même chaîne toutes les
         * minutes est un coût sans contrepartie.
         */
        if (!refreshIsUsable || fresh === null) {
            return;
        }

        this.timer = window.setInterval(() => this.tick(), refresh);
    },

    compute() {
        const instant = Date.parse(this.$el.getAttribute('datetime') ?? '');

        if (!Number.isFinite(instant)) {
            return null;
        }

        return relativeLabel((Date.now() - instant) / 1000, this.$el.dataset.timeShort === '1');
    },

    tick() {
        /*
         * ⚠️ LE COMPTEUR COMPTE LES DÉCLENCHEMENTS, PAS LES RÉÉCRITURES — et
         * l'incrément est DONC en tête de méthode.
         *
         * Première rédaction : il était en fin, après le calcul. La campagne de
         * mutation du 2026-08-08 a montré qu'il ne gardait rien — en retirant le
         * plafond des 7 jours, l'intervalle était bien programmé sur un élément
         * vieux de plusieurs mois, se déclenchait, sortait par `fresh === null`
         * SANS incrémenter, et le compteur restait à 0. Le test lisait « aucun
         * tick » là où il aurait dû lire « un intervalle a tourné ».
         *
         * Ce que l'AC6 interdit au-delà de 7 jours, c'est la PROGRAMMATION de
         * l'intervalle. Un compteur de réécritures ne sait pas la voir ; un
         * compteur de déclenchements, si.
         */
        this.ticks += 1;
        this.$el.dataset.timeTicks = String(this.ticks);

        const fresh = this.compute();

        if (fresh === null) {
            // Le plafond des 7 jours a été franchi pendant la session : on
            // s'arrête plutôt que de rendre « il y a 7 jours » là où le serveur
            // dirait « il y a 1 semaine ». Le libellé gèle, c'est l'arbitrage.
            this.stop();

            return;
        }

        this.label = fresh;
    },

    stop() {
        window.clearInterval(this.timer);
        this.timer = null;
    },

    destroy() {
        this.stop();
    },
});

document.addEventListener('alpine:init', () => {
    window.Alpine.data('toast', toast);
    window.Alpine.data('timeRelative', timeRelative);
});
