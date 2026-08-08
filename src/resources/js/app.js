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

document.addEventListener('alpine:init', () => {
    window.Alpine.data('toast', toast);
});
