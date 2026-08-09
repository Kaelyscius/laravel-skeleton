import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { basename, join } from 'node:path';
import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import tailwindcss from '@tailwindcss/vite';

/**
 * Copie les faces IBM Plex de node_modules vers public/fonts/ (Story 1.9, AC3).
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI UNE COPIE, ET PAS LE PIPELINE VITE
 *
 * Écrire `@import '@fontsource/ibm-plex-sans/latin-400.css'` dans app.css
 * marcherait — et rendrait la story INVÉRIFIABLE. Vite réécrit les `url()`
 * relatives vers `public/build/assets/<nom>-<hash>.woff2` : le `href` du
 * `<link rel="preload">` deviendrait inconnaissable au moment d'écrire le
 * layout, donc l'AC de preload ne pourrait être que faux-vert.
 *
 * Committer les woff2 marcherait aussi — et créerait une seconde source de
 * vérité, capable de diverger de la version verrouillée dans package-lock.json
 * sans que rien ne le dise.
 *
 * Reste la copie au build, depuis une table unique. Le nom servi n'est donc pas
 * haché — il DOIT être connu à l'écriture du preload. L'invalidation de cache
 * vient de la VERSION portée par le `target` (`…-normal-5.3.0.woff2`), qu'un
 * test rapproche de package-lock.json : le vhost sert les woff2 en
 * `access plus 1 year`, une convention non gardée y serait un an d'ancienne face.
 *
 * ⚠️ `buildStart` et PAS `closeBundle` : le premier tourne pour `vite build`
 * ET pour `vite` (dev server). Un plugin en `closeBundle` seul laisserait
 * `npm run dev` servir des pages sans polices — sans erreur.
 *
 * ⚠️ Le dossier est VIDÉ avant chaque copie. Sans cela, un `target` renommé
 * laisserait son ancien fichier derrière lui : `public/fonts/` contiendrait
 * alors plus que ce que décrit la table, et le compte de l'AC7 mesurerait un
 * état que plus aucune source ne décrit.
 *
 * ⚠️ TOUT EST VALIDÉ AVANT QUE QUOI QUE CE SOIT NE SOIT EFFACÉ. La première
 * rédaction vidait le dossier puis contrôlait chaque source DANS la boucle de
 * copie : une entrée fautive en 3ᵉ position laissait public/fonts/ avec deux
 * fichiers sur six, et le rouge qui suivait disait « ne correspond pas à la
 * table » au lieu de nommer l'entrée. Relevé à la revue du 2026-08-09 — c'est
 * le défaut de rouge illisible que la mutation MF-E avait déjà fait corriger un
 * fichier plus loin.
 *
 * ⛔ AUCUN paquet npm pour copier six fichiers.
 */
function selfHostedFonts() {
    const manifestPath = join(import.meta.dirname, 'resources/fonts.json');
    const outputDirectory = join(import.meta.dirname, 'public/fonts');

    return {
        name: 'self-hosted-fonts',
        buildStart() {
            let manifest;

            /*
             * Le seul échec du plugin qui ne nommait pas sa cause : `JSON.parse`
             * lève un `SyntaxError` nu, sans dire quel fichier il lisait. Tous
             * les autres throw d'ici nomment la table ET l'entrée fautive.
             */
            try {
                manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
            } catch (error) {
                throw new Error(
                    `resources/fonts.json est illisible ou malformé : ${error.message}`,
                );
            }

            /*
             * ⚠️ LA RACINE EST CONTRÔLÉE AVANT D'ÊTRE DÉRÉFÉRENCÉE. Relevé à la
             * seconde passe de revue du 2026-08-09 : un fichier contenant `null`
             * (ou une chaîne, ou un nombre) est du JSON PARFAITEMENT VALIDE. Le
             * try/catch ci-dessus ne se déclenche donc pas, et `manifest.faces`
             * lève un `TypeError: Cannot read properties of null` qui ne nomme ni
             * le fichier, ni la cause — exactement ce que le bloc ci-dessus
             * affirmait être le SEUL échec anonyme restant.
             */
            if (manifest === null || typeof manifest !== 'object' || Array.isArray(manifest)) {
                throw new Error(
                    'resources/fonts.json ne contient pas un objet : sa racine doit porter [faces] et [licenses].',
                );
            }

            const faces = manifest.faces ?? [];
            const licenses = manifest.licenses ?? [];

            /*
             * `faces` est contrôlé SÉPARÉMENT des licences. Un test global sur le
             * total serait vert sur une table qui n'a plus que ses deux licences :
             * le build sortirait 0, copierait deux LICENSE, et public/fonts/ ne
             * contiendrait pas un seul woff2.
             */
            if (! Array.isArray(faces) || faces.length === 0) {
                throw new Error('resources/fonts.json ne décrit aucune face sous [faces].');
            }

            if (! Array.isArray(licenses) || licenses.length === 0) {
                throw new Error('resources/fonts.json ne redistribue aucune licence sous [licenses].');
            }

            const assets = [...faces, ...licenses];
            const seen = new Map();

            for (const [index, asset] of assets.entries()) {
                /*
                 * ⚠️ LA FORME DE L'ENTRÉE EST CONTRÔLÉE AVANT QUE SES CHAMPS NE
                 * SERVENT. Relevé à la seconde passe de revue du 2026-08-09 : les
                 * gardes nommées ci-dessous tournaient TOUTES après le `join()` et
                 * le `basename()`, donc aucune ne pouvait rapporter l'index. Une
                 * entrée non-objet, ou sans `package`/`source`/`target`, levait un
                 * `TypeError [ERR_INVALID_ARG_TYPE]` de node — la forme la plus
                 * probable d'une faute de frappe, et la seule qui ne disait rien.
                 */
                if (asset === null || typeof asset !== 'object' || Array.isArray(asset)) {
                    throw new Error(
                        `resources/fonts.json : l'entrée n°${index} n'est pas un objet.`,
                    );
                }

                for (const field of ['package', 'source', 'target']) {
                    if (typeof asset[field] !== 'string' || asset[field] === '') {
                        throw new Error(
                            `resources/fonts.json : l'entrée n°${index} n'a pas de [${field}] utilisable `
                            + '(chaîne non vide attendue).',
                        );
                    }
                }

                /*
                 * ⛔ LA TRAVERSÉE EST REFUSÉE DES DEUX CÔTÉS, PAS SEULEMENT À LA
                 * DESTINATION. Relevé à la seconde passe de revue du 2026-08-09 :
                 * le `target` était contrôlé, la SOURCE ne l'était pas. `join()`
                 * résout les `..`, donc un `package` ou une `source` remontante
                 * désignait n'importe quel fichier du dépôt — et la copie l'aurait
                 * déposé dans public/fonts/, que le vhost sert publiquement. La
                 * table est contrôlée par le dépôt, donc l'exploitabilité est
                 * faible ; c'est l'ASYMÉTRIE qui était le défaut, un modèle de
                 * menace écrit puis appliqué à une moitié de sa propre boucle.
                 */
                for (const field of ['package', 'source']) {
                    if (asset[field].split('/').includes('..')) {
                        throw new Error(
                            `resources/fonts.json : l'entrée n°${index} a un [${field}] remontant `
                            + `[${asset[field]}] — la copie sortirait de node_modules.`,
                        );
                    }
                }

                const source = join(import.meta.dirname, 'node_modules', asset.package, asset.source);

                /*
                 * `copyFileSync` lèverait de toute façon — mais sur un ENOENT qui
                 * ne nomme ni la table, ni l'entrée fautive. Une copie silencieusement
                 * sautée serait pire encore : la page resterait jolie, en fonte
                 * système, et rien ne rougirait avant le test navigateur.
                 *
                 * ⚠️ `statSync().isFile()` ET PAS `existsSync()`. Relevé à la
                 * seconde passe de revue du 2026-08-09 : `existsSync` répond VRAI
                 * pour un RÉPERTOIRE. Une `source` valant `files` (le dossier du
                 * paquet, au lieu d'un fichier dedans) passait la validation, le
                 * rmSync vidait public/fonts/, puis copyFileSync levait EISDIR —
                 * l'invariant « tout est validé avant que quoi que ce soit ne soit
                 * effacé » ne tenait que pour les sources ABSENTES.
                 */
                if (! existsSync(source) || ! statSync(source).isFile()) {
                    throw new Error(
                        `Face absente ou non-fichier : ${asset.package}/${asset.source}. `
                        + 'Vérifier resources/fonts.json et `npm install`.',
                    );
                }

                /*
                 * Un `target` porteur d'un chemin sortirait du dossier de sortie —
                 * `../../.env` s'écrirait hors de public/fonts/, et un `sous/x.woff2`
                 * échouerait en ENOENT nu faute de mkdir. Le `target` est un NOM DE
                 * FICHIER, et c'est ici qu'on le dit.
                 */
                if (asset.target !== basename(asset.target) || asset.target.startsWith('.')) {
                    throw new Error(
                        `resources/fonts.json : le target [${asset.target}] n'est pas un nom de fichier nu.`,
                    );
                }

                /*
                 * L'unicité est contrôlée sur TOUTES les sections à la fois. Les
                 * tests la vérifient à l'intérieur de `faces` et à l'intérieur de
                 * `licenses` ; une collision ENTRE les deux écraserait un fichier à
                 * la copie, et seule la suite navigateur l'aurait vue.
                 */
                if (seen.has(asset.target)) {
                    throw new Error(
                        `resources/fonts.json : le target [${asset.target}] est décrit deux fois `
                        + `(${seen.get(asset.target)} puis ${asset.package}) — la copie en écraserait un.`,
                    );
                }

                seen.set(asset.target, asset.package);
            }

            rmSync(outputDirectory, { force: true, recursive: true });
            mkdirSync(outputDirectory, { recursive: true });

            for (const asset of assets) {
                copyFileSync(
                    join(import.meta.dirname, 'node_modules', asset.package, asset.source),
                    join(outputDirectory, asset.target),
                );
            }
        },
    };
}

export default defineConfig({
    plugins: [
        laravel({
            input: ['resources/css/app.css', 'resources/js/app.js'],
            refresh: true,
        }),
        tailwindcss(),
        selfHostedFonts(),
    ],
    server: {
        watch: {
            ignored: ['**/storage/framework/views/**'],
        },
    },
});
