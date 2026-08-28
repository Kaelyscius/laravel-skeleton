<?php

declare(strict_types=1);

use Illuminate\Contracts\Http\Kernel;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Routing\UrlGenerator;
use Illuminate\Support\Facades\Blade;
use Tests\Support\BladeTemplates;
use Tests\Support\FontManifest;
use Tests\Support\RepoFile;
use Tests\Support\RouteTable;

uses(RefreshDatabase::class);

/**
 * Story 1.9 — le CÂBLAGE du self-hosting IBM Plex.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * CE QUE CE FICHIER NE PROUVE PAS, ET NE PEUT PAS PROUVER
 *
 * Qu'une police est effectivement CHARGÉE. Rien dans une chaîne de HTML ni dans
 * un fichier CSS ne le dit : un `@font-face` parfaitement écrit vers un fichier
 * absent produit une page correcte, en fonte système, sans erreur. Cette preuve
 * est dans tests/Browser/FontsTest.php, par énumération de `document.fonts`.
 *
 * ⛔ ET SURTOUT : `getComputedStyle(document.body).fontFamily` NE LA DONNE PAS
 * NON PLUS. tests/Browser/CascadeSmokeTest.php fait cette lecture et il est vert
 * depuis le 2026-08-06, alors qu'aucun woff2 n'existait dans le dépôt. La
 * propriété rend la PILE DÉCLARÉE, pas la fonte employée. Ne pas se fier à son
 * vert pour croire cette story terminée.
 *
 * Ce qui se vérifie ICI est le câblage, et il se vérifie sans build :
 *
 *   table ↔ package.json   (AC1)   la dépendance est VOULUE, pas transitive
 *   table ↔ ses lecteurs   (AC2)   aucune liste recopiée à la main
 *   table ↔ le rendu       (AC4)   un @font-face complet par face, même URL que
 *                                  le preload — les règles ont quitté
 *                                  resources/css/fonts.css à la revue du
 *                                  2026-08-09, voir le bloc AC4 pour le motif
 *   table ↔ les 2 layouts  (AC5)   les preloads, leur ordre, leurs attributs
 *   table ↔ TOUS les Blade (AC9)   toute graisse employée a une face
 *
 * ⚠️ AUCUN test de ce fichier ne doit dépendre de l'existence de `public/fonts/`.
 * Ce dossier est DÉRIVÉ (gitignoré, produit par le build) : un test Feature qui
 * le lirait rougirait chez un développeur qui n'a pas encore buildé, pour une
 * raison étrangère à ce qu'il teste. Le contenu réel du dossier est vérifié par
 * la suite navigateur, qui exige déjà un build.
 *
 * `toContain()` est PROSCRIT (variadique sur les needles, donc
 * `->not->toContain('a', 'message')` passe toujours) : str_contains() +
 * toBeFalse($message).
 */

/**
 * Supprime les commentaires Blade, HTML et CSS : un fichier a le droit d'écrire
 * ce qu'il s'interdit de faire — et tous ceux de cette story le font.
 *
 * ⚠️ L'ÉCHEC DE REGEX EST UNE EXCEPTION, PAS UNE CHAÎNE VIDE. `preg_replace`
 * renvoie `null` sur `PREG_BACKTRACK_LIMIT_ERROR`, et `(string) null` vaut `''` :
 * la première rédaction rendait alors un fichier VIDE, sur lequel tous les scans
 * de l'AC9 passaient — verts, sur un fichier que personne n'avait lu. Relevé à
 * la revue du 2026-08-09 : un garde-fou dont l'échec ressemble au succès est
 * exactement ce que cette story existe pour ne pas produire.
 */
$stripComments = static function (string $source): string {
    $stripped = preg_replace(
        ['#\{\{--.*?--\}\}#s', '#<!--.*?-->#s', '#/\*.*?\*/#s'],
        '',
        $source,
    );

    if (! is_string($stripped)) {
        throw new RuntimeException(
            'Le retrait des commentaires a échoué (preg_error: ' . preg_last_error_msg()
            . ') : le scan aurait porté sur une chaîne vide, donc conclu au vert sans rien lire.',
        );
    }

    return $stripped;
};

/**
 * `preg_match` dont l'ÉCHEC est une exception, jamais un « pas de violation ».
 *
 * ⚠️ RELEVÉ À LA SECONDE PASSE DE REVUE DU 2026-08-09. Le durcissement de la
 * première passe avait été appliqué aux `preg_match_all` (qui lèvent sur `false`,
 * avec leur motif écrit) et PAS aux `preg_match` : sept sites comparaient
 * `=== 1`, or `preg_match` rend `false` sur `PREG_BACKTRACK_LIMIT_ERROR` — et
 * `false === 1` est faux, ce qui se lit exactement comme « aucune violation
 * trouvée ». Un scan qui échoue et un scan qui ne trouve rien rendaient le même
 * verdict. C'est le motif dominant du projet, dans le fichier qui le traque.
 */
$matchesPattern = static function (string $pattern, string $subject): bool {
    $result = preg_match($pattern, $subject);

    if ($result === false) {
        throw new RuntimeException(
            "Le scan [{$pattern}] a échoué (preg_error: " . preg_last_error_msg()
            . ') : sans cette exception, l\'échec se serait lu « aucune violation ».',
        );
    }

    return $result === 1;
};

/**
 * Toutes les valeurs d'attribut `class` d'un template, DANS LEURS TROIS FORMES.
 *
 * ⚠️ LA SECONDE FORME EST CELLE DU CODE RÉEL, ET LE SCANNER NE LA CONNAISSAIT
 * PAS. Les quatre `<x-time-*>` n'écrivent aucun `class="…"` littéral : ils
 * passent par `$attributes->merge(['class' => 'font-mono …'])`, donc une valeur
 * de tableau PHP. Mesuré à la revue du 2026-08-09 : la regex d'origine capturait
 * **0 attribut sur les 4**, alors que chacun emploie `font-mono`. Le seul fichier
 * du dépôt dont un `class="…"` littéral porte `font-mono` était
 * `welcome.blade.php` — hors périmètre du scan à l'époque. Le garde-fou était
 * donc vide sur 100 % de sa cible réelle, et son auto-contrôle ne pouvait pas
 * l'attraper : il ne se nourrissait que de fixtures littérales.
 *
 * ⚠️ LA TROISIÈME FORME, AJOUTÉE À LA SECONDE PASSE DE REVUE DU 2026-08-09 :
 * `@class(['font-mono font-medium' => $condition])`. C'est la directive Blade
 * idiomatique pour une classe conditionnelle, elle produit exactement la même
 * graisse, et elle échappait aux deux premières formes. C'est la même classe de
 * trou que MR-1 venait de fermer, une idiome plus loin — d'où la règle : ce
 * relevé se corrige en AJOUTANT une forme, jamais en élargissant une regex.
 *
 * ⛔ LIMITE ASSUMÉE, ET REPORTÉE PLUTÔT QUE TUE. `class="{{ $classes }}"` et
 * `'class' => $variable` ne se résolvent PAS sans exécuter le template : ce
 * relevé les capture comme la chaîne littérale `{{ $classes }}`, qui ne contient
 * aucune utility. La seule vraie réponse est une assertion sur du HTML RENDU,
 * pas une regex plus large. Voir `deferred-work.md`.
 *
 * @return list<string>
 */
$classAttributes = static function (string $code): array {
    $values = [];

    foreach (['/class\s*=\s*(["\'])(.*?)\1/s', '/[\'"]class[\'"]\s*=>\s*(["\'])(.*?)\1/s'] as $pattern) {
        if (preg_match_all($pattern, $code, $matches) === false) {
            throw new RuntimeException(
                'Le relevé des attributs class a échoué (preg_error: ' . preg_last_error_msg()
                . ') : le scan aurait rendu « aucune violation » sans avoir rien lu.',
            );
        }

        foreach ($matches[2] as $value) {
            $values[] = $value;
        }
    }

    /*
     * `@class([...])` : toute chaîne littérale du tableau est un jeu de classes,
     * qu'elle soit clé (`'font-bold' => $x`) ou entrée nue (`'font-bold'`). Les
     * deux sont relevées — sur-capturer une valeur qui ne serait pas une classe
     * ne produirait au pire qu'un faux positif nommé, là où en rater une produit
     * un vert silencieux.
     */
    if (preg_match_all('/@class\s*\(\s*\[(?<body>.*?)\]\s*\)/s', $code, $directives) === false) {
        throw new RuntimeException(
            'Le relevé des directives @class a échoué (preg_error: ' . preg_last_error_msg()
            . ') : le scan aurait rendu « aucune violation » sans avoir rien lu.',
        );
    }

    foreach ($directives['body'] as $body) {
        if (preg_match_all('/([\'"])(?<value>(?:(?!\1).)*)\1/s', $body, $literals) === false) {
            throw new RuntimeException(
                'Le relevé des littéraux d\'une directive @class a échoué : ' . preg_last_error_msg(),
            );
        }

        foreach ($literals['value'] as $value) {
            $values[] = $value;
        }
    }

    return $values;
};

/**
 * Les utilities de graisse de Tailwind, et la graisse CSS que chacune produit.
 *
 * @var array<string, int>
 */
$weightUtilities = [
    'font-thin' => 100,
    'font-extralight' => 200,
    'font-light' => 300,
    'font-normal' => 400,
    'font-medium' => 500,
    'font-semibold' => 600,
    'font-bold' => 700,
    'font-extrabold' => 800,
    'font-black' => 900,
];

/**
 * Relève les utilities de graisse et de style SANS face correspondante (AC9).
 *
 * ⚠️ LES VARIANTES COMPTENT. `lg:font-bold` et `hover:font-bold` produisent la
 * même graisse que `font-bold`, sous condition. Un scanner qui ne verrait que la
 * forme nue serait vert par ignorance — c'est la leçon exacte de la Story 1.13,
 * dont le scanner ne connaissait que les guillemets doubles.
 *
 * ⚠️ `not-italic` N'EST PAS `italic` : il remet `font-style: normal`, ce qui est
 * précisément ce que nous servons. Le lookbehind sur `-` l'exclut.
 *
 * ⚠️ LIMITE ASSUMÉE, ET ÉCRITE PLUTÔT QUE TUE : ce relevé compare à l'UNION des
 * graisses servies, toutes familles confondues. Il ne peut pas savoir quelle
 * famille s'applique à un élément donné — cela demanderait de résoudre la
 * cascade, donc un navigateur. Le cas « `font-medium` sur du `font-mono` », lui,
 * est attrapé séparément ci-dessous, parce qu'il est déterminable dans l'attribut.
 *
 * @return list<string>
 */
$findUnservedTypography = static function (string $code) use ($weightUtilities, $classAttributes, $matchesPattern): array {
    $served = FontManifest::servedWeights();
    $found = [];

    foreach ($weightUtilities as $utility => $weight) {
        if (isset($served[$weight])) {
            continue;
        }

        if ($matchesPattern('/(?<![-\w])' . preg_quote($utility, '/') . '(?![-\w])/', $code)) {
            $found[] = "{$utility} (graisse {$weight})";
        }
    }

    /*
     * ⚠️ LES FORMES NON-UTILITY, AJOUTÉES À LA REVUE DU 2026-08-09. Le scan ne
     * connaissait que les neuf noms de classe de Tailwind. Or une graisse
     * intermédiaire manquante est résolue SANS synthèse — rendu strictement
     * indiscernable — quelle que soit la manière dont elle a été demandée. Les
     * quatre formes ci-dessous produisent la même graisse et échappaient toutes.
     */

    /*
     * 1. Valeur arbitraire numérique : `font-[550]`.
     *
     * ⚠️ `\d{1,4}` ET PAS `\d{3}`. Relevé à la seconde passe de revue du
     * 2026-08-09 : la classe CSS `font-weight` va de 1 à 1000, donc `font-[1000]`
     * est une valeur PARFAITEMENT VALIDE que `\d{3}` ne matchait pas du tout —
     * la graisse non servie passait sans un mot. Une regex de garde-fou trop
     * étroite ne rend pas un faux positif : elle rend un silence.
     */
    if (preg_match_all('/(?<![-\w])font-\[(\d{1,4})\]/', $code, $arbitrary) === false) {
        throw new RuntimeException('Le relevé des graisses arbitraires a échoué : ' . preg_last_error_msg());
    }

    foreach ($arbitrary[1] as $literal) {
        if (! isset($served[(int) $literal])) {
            $found[] = "font-[{$literal}] (graisse {$literal})";
        }
    }

    // 2. Valeur pilotée par une propriété personnalisée : `font-(--x)`. La
    //    graisse n'est PAS déterminable statiquement — donc invérifiable, donc
    //    refusée. Un scan qui la laisserait passer serait vert par ignorance.
    if ($matchesPattern('/(?<![-\w])font-\((--[^)]+)\)/', $code)) {
        $found[] = 'font-(--…) (graisse indéterminable statiquement)';
    }

    /*
     * 2 bis. LA MÊME INDÉTERMINATION, ÉCRITE EN CSS : `font-weight: var(--x)`.
     *
     * Relevé à la seconde passe de revue du 2026-08-09. La forme utility est
     * refusée juste au-dessus, explicitement, parce qu'elle est indéterminable ;
     * la forme CSS produit exactement la même indétermination et n'était matchée
     * par rien. Refuser l'une et pas l'autre, c'est appliquer une doctrine à la
     * moitié de son objet.
     */
    if ($matchesPattern('/font-weight\s*:\s*var\s*\(/i', $code)) {
        $found[] = 'font-weight: var(…) (graisse indéterminable statiquement)';
    }

    /*
     * 3. `font-weight` écrit en CSS — dans un `style="…"`, un `<style>` ou un
     *    `@apply`. Les mots-clés comptent : `bold`/`bolder` valent 700.
     *
     * ⚠️ `\d{1,4}`, MÊME MOTIF QU'AU POINT 1 — et ici le défaut était PIRE que
     * le silence : `\d{3}` matchait bien `font-weight: 1000`, mais ne capturait
     * que `100`. Le message rapportait donc « graisse 100 » pour une déclaration
     * de 1000, c'est-à-dire un rouge qui nomme la mauvaise cause.
     */
    if (preg_match_all('/font-weight\s*:\s*(\d{1,4}|bold|bolder|lighter)(?![\d.])/i', $code, $declared) === false) {
        throw new RuntimeException('Le relevé des font-weight déclarés a échoué : ' . preg_last_error_msg());
    }

    foreach ($declared[1] as $value) {
        $weight = match (mb_strtolower($value)) {
            'bold', 'bolder' => 700,
            'lighter' => 100,
            default => (int) $value,
        };

        if (! isset($served[$weight])) {
            $found[] = "font-weight: {$value} (graisse {$weight})";
        }
    }

    // 4. La PRÉFLIGHT de Tailwind : `b, strong { font-weight: bolder }`. Aucune
    //    classe n'est écrite, la graisse 700 est pourtant demandée — et faute de
    //    face 700, le navigateur SYNTHÉTISE un faux-gras. Visible, mais ce n'est
    //    pas la fonte, et personne ne l'a décidé.
    if (! isset($served[700]) && $matchesPattern('/<(b|strong)(?=[\s>\/])/i', $code)) {
        $found[] = '<b>/<strong> (préflight Tailwind : font-weight: bolder → 700)';
    }

    /*
     * Aucune face italique n'est servie : l'utility est interdite tant que le
     * design n'en demande pas.
     *
     * ⚠️ RESTREINT AUX ATTRIBUTS class, contrairement aux graisses. Le mot
     * « italic » peut apparaître dans une copie visible, un `alt` ou un `data-*`,
     * et l'AC9 aurait alors échoué sur du texte. Un faux positif bruyant ne casse
     * rien — il désarme, ce qui est pire. `font-style: italic` est couvert à part.
     */
    foreach ($classAttributes($code) as $attribute) {
        if ($matchesPattern('/(?<![-\w])italic(?![-\w])/', $attribute)) {
            $found[] = 'italic (aucune face italique servie)';

            break;
        }
    }

    if ($matchesPattern('/font-style\s*:\s*italic/i', $code)) {
        $found[] = 'font-style: italic (aucune face italique servie)';
    }

    return $found;
};

/**
 * Relève les graisses appliquées à `font-mono` sans face mono correspondante.
 *
 * C'est le cas VRAIMENT silencieux, et il est déterminable sans navigateur :
 * quand `font-mono` et une utility de graisse cohabitent dans le MÊME attribut
 * `class`, la famille appliquée est connue. Sans face mono à cette graisse,
 * l'algorithme CSS résout vers la face la plus proche SANS synthèse pour les
 * graisses intermédiaires : le rendu est indiscernable, et rien ne rougit.
 *
 * ⚠️ LES DEUX FORMES DE GUILLEMETS. Un scanner qui ne connaîtrait que `class="…"`
 * serait vert sur `class='…'` — la Story 1.13 a payé exactement ça.
 *
 * ⚠️ ET LES DEUX FORMES D'ÉCRITURE. Le relevé passe par `$classAttributes`, qui
 * connaît aussi `'class' => '…'` — la forme employée par les quatre `<x-time-*>`,
 * c'est-à-dire par 100 % du code qui emploie réellement `font-mono`. Voir le
 * docblock de `$classAttributes`.
 *
 * @return list<string>
 */
$findMonoWeightMismatches = static function (string $code) use ($weightUtilities, $classAttributes, $matchesPattern): array {
    $monoWeights = FontManifest::monospaceWeights();
    $found = [];

    foreach ($classAttributes($code) as $attribute) {
        if (! $matchesPattern('/(?<![-\w])font-mono(?![-\w])/', $attribute)) {
            continue;
        }

        foreach ($weightUtilities as $utility => $weight) {
            if (isset($monoWeights[$weight])) {
                continue;
            }

            if ($matchesPattern('/(?<![-\w])' . preg_quote($utility, '/') . '(?![-\w])/', $attribute)) {
                $found[] = "{$utility} sur font-mono (graisse {$weight} non servie en mono)";
            }
        }
    }

    return $found;
};

/*
|--------------------------------------------------------------------------
| AC1 — les paquets sont des dépendances DÉCLARÉES
|--------------------------------------------------------------------------
*/

it('déclare les deux paquets @fontsource dans package.json, pas seulement dans le lock (AC1)', function (): void {
    /*
     * Le lock prouve qu'un paquet est INSTALLÉ, jamais qu'il est VOULU. C'est la
     * forme exacte du défaut transverse relevé le 2026-07-30 : `livewire/livewire`
     * annoncé par l'architecture, absent du manifeste, présent en transitif — un
     * paquet que personne n'a déclaré vouloir disparaît le jour où son parent
     * disparaît, et le build casse pour une raison qu'aucun document n'explique.
     *
     * Vu rouge : en retirant les deux lignes de `devDependencies`.
     */
    $devDependencies = RepoFile::section(RepoFile::json('src/package.json'), 'devDependencies');

    expect($devDependencies)
        ->not->toBeEmpty('package.json ne déclare aucune devDependency : le test ne prouve rien.');

    foreach (['@fontsource/ibm-plex-sans', '@fontsource/ibm-plex-mono'] as $package) {
        expect(array_key_exists($package, $devDependencies))
            ->toBeTrue("{$package} n'est pas déclaré dans les devDependencies de src/package.json.");
    }

    /*
     * `devDependencies` et pas `dependencies` : le build les consomme, rien ne
     * les lit à l'exécution. C'est l'emplacement de tailwindcss et de vite — on
     * ne crée pas une seconde convention.
     */
    $runtime = RepoFile::section(RepoFile::json('src/package.json'), 'dependencies');

    foreach (['@fontsource/ibm-plex-sans', '@fontsource/ibm-plex-mono'] as $package) {
        expect(array_key_exists($package, $runtime))
            ->toBeFalse("{$package} est déclaré en dépendance d'exécution : rien ne le lit à l'exécution.");
    }
});

it('résout les deux paquets @fontsource dans la plage que package.json déclare (AC1)', function (): void {
    /*
     * Les chemins `source` de la table nomment des fichiers du paquet
     * (`files/ibm-plex-sans-latin-400-normal.woff2`). Une montée majeure qui les
     * renommerait ferait échouer le build BRUYAMMENT — c'est voulu.
     *
     * ⚠️ CE TEST EXIGEAIT `5.3.0` EXACTEMENT, ET package.json DÉCLARE `^5.3.0`.
     * Un `npm update` de routine rougissait alors avec un message décrivant une
     * politique que le manifeste n'exprimait pas — la forme d'un garde-fou qu'on
     * finit par désarmer parce qu'il a tort. Arbitrage à la revue du 2026-08-09 :
     * le test contrôle la PLAGE, qui est ce que le dépôt a réellement décidé.
     *
     * Ce qui reste verrouillé, et qui compte davantage : le `target` servi porte
     * la version RÉSOLUE (test suivant). Une montée de version change donc l'URL,
     * donc l'entrée de cache — ce qu'un numéro figé ici n'aurait jamais garanti.
     */
    $declared = RepoFile::section(RepoFile::json('src/package.json'), 'devDependencies');
    $packages = RepoFile::section(RepoFile::json('src/package-lock.json'), 'packages');

    expect($packages)
        ->not->toBeEmpty('package-lock.json ne décrit aucun paquet : le test ne prouve rien.');

    foreach (['@fontsource/ibm-plex-sans', '@fontsource/ibm-plex-mono'] as $package) {
        $key = "node_modules/{$package}";

        expect(array_key_exists($key, $packages))
            ->toBeTrue("{$package} n'est pas résolu par package-lock.json.");

        $range = RepoFile::stringAt($declared, $package);
        $resolved = RepoFile::stringAt($packages, "{$key}.version");

        expect($range)
            ->toBe('^5.3.0', "{$package} ne déclare plus la plage ^5.3.0 dans package.json : la table et le vhost ont été écrits pour la 5.x.");

        expect($resolved)
            ->toMatch('/^5\.(?:3\.(?:[1-9]\d*|0)|(?:[4-9]|\d{2,})\.\d+)$/', "{$package} est résolu en [{$resolved}], hors de la plage ^5.3.0 déclarée par package.json.");
    }
});

it('fait porter au nom de fichier servi la version résolue de son paquet (AC1/AC3)', function (): void {
    /*
     * ⚠️ C'EST LE SEUL MÉCANISME D'INVALIDATION DE CACHE DE CETTE STORY, ET IL
     * NE TIENDRAIT PAS TOUT SEUL.
     *
     * Les woff2 ne sont pas hachés par Vite — leur nom DOIT être connu à
     * l'écriture du preload. Le vhost les sert désormais en
     * `ExpiresByType font/woff2 "access plus 1 year"` (ajouté à la revue du
     * 2026-08-09, où ils tombaient dans un ExpiresDefault à 2 jours). Sans la
     * version dans le nom, une montée de @fontsource servirait l'ANCIENNE face à
     * tout visiteur récurrent pendant un an, sans une seule erreur.
     *
     * Une convention de nommage qu'aucun test ne garde est une convention qui
     * sera oubliée à la première montée de version — laquelle est justement le
     * seul moment où elle compte.
     *
     * ⚠️ LE RAPPROCHEMENT EST UN SUFFIXE EXACT, PAS UNE INCLUSION. Relevé à la
     * seconde passe de revue du 2026-08-09 : la première rédaction faisait un
     * `str_contains($target, $version)`. Un `target` figé à `…-5.3.10.woff2`
     * satisfait alors une version résolue de `5.3.1` — le seul garde-fou entre
     * une montée de @fontsource et douze mois d'ancienne face était une
     * comparaison par inclusion, là où l'invariant est l'égalité.
     */
    $packages = RepoFile::section(RepoFile::json('src/package-lock.json'), 'packages');
    $faces = FontManifest::faces();

    expect($faces)
        ->not->toBeEmpty('La table ne décrit aucune face : le test ne prouve rien.');

    foreach ($faces as $face) {
        $version = RepoFile::stringAt($packages, "node_modules/{$face['package']}.version");

        expect($version)
            ->not->toBeNull("{$face['package']} n'est pas résolu par package-lock.json : la version servie est inconnaissable.");

        expect(str_ends_with($face['target'], "-{$version}.woff2"))
            ->toBeTrue("Le fichier servi [{$face['target']}] ne se termine pas par [-{$version}.woff2], la version résolue de {$face['package']} : une montée de version servirait l'ancienne face pendant un an de cache.");
    }
});

it('fait servir les woff2 par le vhost en cache long, l\'autre moitié de la convention (AC3)', function (): void {
    /*
     * ⚠️ LES DEUX MOITIÉS DE LA DÉCISION SE TIENNENT L'UNE PAR L'AUTRE, ET UNE
     * SEULE ÉTAIT GARDÉE. Relevé à la seconde passe de revue du 2026-08-09.
     *
     * La version dans le nom de fichier (test précédent) n'existe QUE parce que
     * le vhost sert les woff2 en `access plus 1 year` : sans cache long, aucune
     * invalidation à organiser, et le suffixe de version serait décoratif. Sans
     * la version, le cache long servirait l'ancienne face pendant un an.
     *
     * Or `grep -rn ExpiresByType src/tests/` ne trouvait qu'un commentaire en
     * prose : supprimer la ligne du vhost faisait retomber tous les woff2 dans
     * l'`ExpiresDefault "access plus 2 days"` pendant que le test de version
     * restait vert — et sans objet. Un garde-fou dont la moitié gardée n'a plus
     * de raison d'être est un garde-fou qui ment.
     *
     * ⛔ ET LE PÉRIMÈTRE DE LA CI A ÉTÉ ÉLARGI DANS LE MÊME COMMIT. Ce test vit
     * sous `src/**` ; sa cible vit sous `docker/apache/**`, qui n'était PAS dans
     * les `paths` de `.github/workflows/ci.yml`. Une modification du vhost ne
     * déclenchait donc pas la CI qui l'assure.
     */
    /*
     * ⚠️ LE SUJET EST DEVENU UN GABARIT (story 2.5). `laravel.conf` a été
     * renommé en `laravel.conf.template` : le fichier est rendu au démarrage
     * vers une cible inscriptible, parce que ce répertoire est monté `:ro`.
     * Ce que ce test garde est INCHANGÉ — la directive `Expires` ne porte
     * aucune variable, donc ce qui est écrit ici est ce qui est servi.
     */
    $vhost = RepoFile::read('docker/apache/conf/sites-enabled/laravel.conf.template');

    expect(str_contains($vhost, 'ExpiresByType font/woff2 "access plus 1 year"'))
        ->toBeTrue('Le vhost ne sert plus les woff2 en cache long : ils retombent dans ExpiresDefault (2 jours), et le suffixe de version dans le nom de fichier n\'a plus d\'objet.');

    /*
     * L'anti-vacuité : sans lui, un fichier vide ou renommé rendrait la chaîne
     * introuvable pour une raison qui n'est pas celle qu'annonce le message.
     */
    expect(str_contains($vhost, 'ExpiresDefault'))
        ->toBeTrue('Le vhost lu ne contient aucune directive Expires : ce n\'est pas le fichier attendu, et le test ci-dessus aurait rougi pour la mauvaise raison.');
});

it('redistribue une licence SIL OFL PAR PAQUET, et pas une seule pour les deux (AC1)', function (): void {
    /*
     * Une police servie sans sa licence est un problème juridique offert à chaque
     * forkeur (ADR-0001). Et il en faut DEUX : les LICENSE des deux paquets ne
     * sont pas identiques — leur première ligne porte la notice de copyright de
     * la fonte concernée (2019/Sans, 2017/Mono). N'en redistribuer qu'une
     * perdrait celle de l'autre, ce que l'OFL §1 interdit précisément.
     */
    $packages = array_map(
        static fn (array $license): string => $license['package'],
        FontManifest::licenses(),
    );

    foreach (['@fontsource/ibm-plex-sans', '@fontsource/ibm-plex-mono'] as $package) {
        expect(in_array($package, $packages, true))
            ->toBeTrue("La licence de {$package} n'est pas redistribuée à côté des woff2.");
    }

    // Deux licences distinctes, donc deux fichiers servis distincts : un `target`
    // partagé écraserait silencieusement l'une des deux à la copie.
    $targets = array_map(
        static fn (array $license): string => $license['target'],
        FontManifest::licenses(),
    );

    expect(array_unique($targets))
        ->toHaveCount(count($targets), 'Deux licences partagent le même nom de fichier servi : la copie en écraserait une.');
});

/*
|--------------------------------------------------------------------------
| AC2 — une table unique, et personne ne recopie ses noms de fichiers
|--------------------------------------------------------------------------
*/

it('décrit chaque face par les six champs que ses lecteurs attendent (AC2)', function (): void {
    /*
     * FontManifest lève sur tout champ manquant ou mal typé : appeler faces()
     * EST l'assertion de structure. Ce test vérifie ce que la classe ne peut pas
     * savoir — que la table décrit bien quelque chose, et que ses noms de
     * fichiers servis sont uniques.
     */
    $faces = FontManifest::faces();

    expect($faces)
        ->not->toBeEmpty('resources/fonts.json ne décrit aucune face.');

    $targets = array_map(static fn (array $face): string => $face['target'], $faces);

    expect(array_unique($targets))
        ->toHaveCount(count($targets), 'Deux faces partagent le même nom de fichier servi.');

    // Une face par couple (famille, graisse, style normal) : deux entrées de même
    // famille ET même graisse rendraient l'une des deux inatteignable, sans erreur.
    $couples = array_map(
        static fn (array $face): string => $face['family'] . '/' . $face['weight'],
        $faces,
    );

    expect(array_unique($couples))
        ->toHaveCount(count($couples), 'Deux faces déclarent la même famille à la même graisse.');
});

it('ne recopie AUCUN nom de fichier de police hors de la table (AC2)', function () use ($stripComments): void {
    /*
     * Le défaut que la table existe pour éliminer : un nom de fichier apparaîtrait
     * sinon quatre fois — copie Vite, `src: url()` du @font-face, `href` du
     * preload, et le test.
     *
     * ⚠️ LES QUATRE DÉRIVENT MAINTENANT, ET IL N'Y A PLUS D'EXEMPTION. Le
     * quatrième était resources/css/fonts.css, écrit à la main délibérément parce
     * qu'il était le seul capable de diverger — donc le seul que l'AC4 pouvait
     * attraper. Le prix en était des URL en racine absolue, donc quatre 404
     * silencieux sous un déploiement en sous-chemin (revue du 2026-08-09) : les
     * règles sont passées dans <x-font-preloads />, où asset() s'applique. Ce que
     * l'AC4 garde désormais est écrit dans son propre bloc plus bas.
     *
     * Vu rouge : en écrivant un `href` littéral dans le composant de preload.
     */
    $derived = [
        'vite.config.js',
        'resources/views/components/font-preloads.blade.php',
        'config/fonts.php',
    ];

    $targets = array_map(static fn (array $face): string => $face['target'], FontManifest::faces());

    foreach ($derived as $relative) {
        $code = $stripComments((string) file_get_contents(base_path($relative)));

        foreach ($targets as $target) {
            expect(str_contains($code, $target))
                ->toBeFalse("{$relative} recopie le nom de fichier [{$target}] : il doit le DÉRIVER de resources/fonts.json.");
        }

        expect(str_contains($code, '.woff'))
            ->toBeFalse("{$relative} cite une extension de police en dur : la table est la seule à nommer des fichiers.");
    }
});

it('fait lire la table par vite.config.js ET par le composant de preload (AC2)', function () use ($stripComments): void {
    /*
     * L'anti-vacuité du test précédent : « aucun nom recopié » serait trivialement
     * vert dans un fichier qui ne parle pas de polices du tout. Chacun doit
     * prouver qu'il LIT la table.
     */
    $vite = $stripComments((string) file_get_contents(base_path('vite.config.js')));

    expect(str_contains($vite, 'resources/fonts.json'))
        ->toBeTrue('vite.config.js ne lit pas resources/fonts.json : la copie a une seconde source de vérité.');

    $config = $stripComments((string) file_get_contents(base_path('config/fonts.php')));

    expect(str_contains($config, 'fonts.json'))
        ->toBeTrue('config/fonts.php ne lit pas resources/fonts.json : les preloads ont une seconde source de vérité.');

    $component = $stripComments((string) file_get_contents(
        base_path('resources/views/components/font-preloads.blade.php'),
    ));

    expect(str_contains($component, "config('fonts.faces')"))
        ->toBeTrue('Le composant de preload ne lit pas la table.');
});

/*
|--------------------------------------------------------------------------
| AC4 — nos propres @font-face, dérivés de la table
|--------------------------------------------------------------------------
*/

/**
 * Les blocs `@font-face` du rendu, sans leurs accolades.
 *
 * @return list<string>
 */
function fontFaceBlocks(string $html): array
{
    if (preg_match_all('/@font-face\s*\{(?<body>[^}]*)\}/s', $html, $matches) === false) {
        throw new RuntimeException('Le relevé des @font-face a échoué : ' . preg_last_error_msg());
    }

    /** @var list<string> $blocks */
    $blocks = $matches['body'];

    return $blocks;
}

it('rend un @font-face par face de la table, avec ses quatre propriétés (AC4)', function (): void {
    /*
     * ⚠️ CE TEST A CHANGÉ D'ARTEFACT À LA REVUE DU 2026-08-09, ET IL FAUT SAVOIR
     * CE QU'IL GARDE MAINTENANT.
     *
     * Il lisait resources/css/fonts.css, écrit à la main : le seul artefact NON
     * dérivé de la table, donc le seul capable d'en diverger — et c'est cette
     * divergence qu'il attrapait. Le prix en était des `url('/fonts/…')` en
     * racine absolue, une feuille statique ne pouvant pas interpoler un préfixe.
     * Sous un déploiement en sous-chemin, cela faisait quatre 404 silencieux,
     * `swap` rendant la page en fonte système sans un mot — et le fork-streamer
     * est l'audience explicite d'ADR-0001. Les règles sont donc passées dans
     * <x-font-preloads />, où `asset()` s'applique.
     *
     * ⛔ Ce qu'il NE PEUT PLUS attraper : une divergence entre la table et les
     * URL, puisque les deux dérivent. Ce serait tautologique de le prétendre.
     *
     * ✅ Ce qu'il attrape RÉELLEMENT, et qui reste un vrai défaut silencieux : le
     * template est écrit à la main, et une propriété qui y manque ne casse rien
     * d'observable. Sans `font-style`, une face italique demandée par une autre
     * feuille pourrait se rattacher à notre déclaration ; sans `format('woff2')`,
     * le navigateur télécharge pour deviner ; sans la boucle complète, une face
     * de la table n'est jamais déclarée et reste `unloaded`.
     *
     * Le défaut qu'une dérivation ne peut PAS voir — la table qui change sans
     * décision — est gardé par « sert 4 faces et n'en précharge que 3 », dont les
     * valeurs sont écrites en dur.
     */
    $html = Blade::render('<x-font-preloads />');
    $blocks = fontFaceBlocks($html);

    expect($blocks)
        ->toHaveCount(count(FontManifest::faces()), 'Le nombre de règles @font-face rendues ne correspond pas au nombre de faces de la table.');

    foreach (FontManifest::faces() as $face) {
        $expectedUrl = "url('" . asset('fonts/' . $face['target']) . "')";

        $matching = array_values(array_filter(
            $blocks,
            static fn (string $block): bool => str_contains($block, $expectedUrl),
        ));

        expect($matching)
            ->toHaveCount(1, "Aucune règle @font-face unique ne pointe vers [{$expectedUrl}].");

        $block = $matching[0];

        expect(str_contains($block, "font-family: '{$face['family']}'"))
            ->toBeTrue("La règle de [{$face['target']}] ne déclare pas font-family: '{$face['family']}'.");

        expect(str_contains($block, "font-weight: {$face['weight']};"))
            ->toBeTrue("La règle de [{$face['target']}] ne déclare pas font-weight: {$face['weight']}.");

        expect(str_contains($block, 'font-style: normal;'))
            ->toBeTrue("La règle de [{$face['target']}] ne déclare pas font-style: normal.");

        expect(str_contains($block, "format('woff2')"))
            ->toBeTrue("La règle de [{$face['target']}] ne déclare pas le format woff2.");
    }
});

it('pose font-display: swap sur CHAQUE face, jamais de texte invisible (AC4)', function (): void {
    /*
     * UX-DR-42. Sans `swap`, le défaut `auto` masque le texte jusqu'à trois
     * secondes sur 4G mobile : une page qui ne dit rien pendant trois secondes est
     * cassée, même si elle finit par être jolie. Une seule règle qui l'oublierait
     * suffirait — d'où le compte, et pas une simple présence.
     *
     * Vu rouge : en retirant la ligne du bloc <style> du composant.
     */
    $blocks = fontFaceBlocks(Blade::render('<x-font-preloads />'));

    expect($blocks)
        ->not->toBeEmpty('Aucune règle @font-face rendue : le test ne prouve rien.');

    foreach ($blocks as $index => $block) {
        expect(str_contains($block, 'font-display: swap;'))
            ->toBeTrue("La règle @font-face n°{$index} n'est pas en font-display: swap.");
    }
});

it('fait viser au preload et au @font-face EXACTEMENT la même URL (AC4/AC5)', function (): void {
    /**
     * ⚠️ LE PIÈGE QUE CE TEST EXISTE POUR ATTRAPER EST CELUI QU'UN CORRECTIF À
     * MOITIÉ APPLIQUÉ AURAIT FABRIQUÉ.
     * Passer le seul `href` du preload par `asset()` en laissant l'`url()` du
     * @font-face en racine absolue aurait fait viser DEUX chemins différents sous
     * un déploiement en sous-chemin : `/app/fonts/x.woff2` d'un côté,
     * `/fonts/x.woff2` de l'autre. Le navigateur ne rapproche jamais un preload
     * d'une requête dont l'URL diffère — donc second téléchargement complet du
     * même fichier, sans erreur, sans message, avec un preload qui n'a servi à
     * rien. C'est le piège n°1 des Dev Notes §4, reconstruit par son correctif.
     * D'où l'assertion d'ÉGALITÉ, et pas deux assertions de forme séparées.
     */
    $html = Blade::render('<x-font-preloads />');
    $blocks = fontFaceBlocks($html);

    expect($blocks)
        ->not->toBeEmpty('Aucune règle @font-face rendue : le test ne prouve rien.');

    if (preg_match_all('/as="font"[^>]*href="(?<href>[^"]+)"/', $html, $matches) === false) {
        throw new RuntimeException('Le relevé des href de preload a échoué : ' . preg_last_error_msg());
    }

    /** @var list<non-empty-string> $hrefs */
    $hrefs = $matches['href'];

    expect($hrefs)
        ->toHaveCount(count(FontManifest::preloaded()), 'Le composant ne rend pas un preload par face marquée preload.');

    foreach (FontManifest::preloaded() as $index => $face) {
        $expected = asset('fonts/' . $face['target']);

        expect($hrefs[$index])
            ->toBe($expected, "Le href du preload de [{$face['target']}] ne dérive pas de asset() : un sous-chemin de déploiement le ferait pointer ailleurs que le @font-face.");
    }

    foreach (FontManifest::faces() as $face) {
        $expected = asset('fonts/' . $face['target']);

        $matching = array_values(array_filter(
            $blocks,
            static fn (string $block): bool => str_contains($block, "url('{$expected}')"),
        ));

        expect($matching)
            ->toHaveCount(1, "Le @font-face de [{$face['target']}] ne vise pas [{$expected}] : preload et @font-face demanderaient deux URL différentes, donc deux téléchargements.");
    }
});

it('déplace preload ET @font-face ENSEMBLE sous un déploiement en sous-chemin (AC4/AC5)', function (): void {
    /*
     * ⚠️ CE TEST EST LA CHARGE UTILE DU REFACTOR, ET ELLE N'ÉTAIT VÉRIFIÉE PAR
     * RIEN. Relevé à la seconde passe de revue du 2026-08-09.
     *
     * Toute la justification du passage de `resources/css/fonts.css` à un <style>
     * rendu par ce composant est le déploiement sous sous-chemin : une feuille
     * statique ne peut pas interpoler un préfixe, donc `url('/fonts/…')` donnait
     * quatre 404 SILENCIEUX chez un fork-streamer déployant sous /app/ — audience
     * explicite d'ADR-0001, motif déclaré de la story.
     *
     * Or aucun test ne posait de préfixe. Le test frère (« EXACTEMENT la même
     * URL ») compare deux valeurs produites par le MÊME appel `asset()` dans le
     * même ordre : il ne peut pas distinguer « les deux corrects » de « les deux
     * également faux ». Et l'AC7 navigateur code la négation du scénario
     * (`str_starts_with($name, $origin . '/fonts/')`, donc racine en dur).
     *
     * Ici le préfixe est POSÉ, et les deux côtés doivent bouger ensemble.
     */
    $url = app(UrlGenerator::class);

    try {
        $url->useAssetOrigin('https://exemple.test/app');

        $html = Blade::render('<x-font-preloads />');
        $blocks = fontFaceBlocks($html);

        expect($blocks)
            ->toHaveCount(count(FontManifest::faces()), 'Aucune règle @font-face rendue sous préfixe : le test ne prouve rien.');

        foreach (FontManifest::faces() as $face) {
            $expected = "https://exemple.test/app/fonts/{$face['target']}";

            $matching = array_values(array_filter(
                $blocks,
                static fn (string $block): bool => str_contains($block, "url('{$expected}')"),
            ));

            expect($matching)
                ->toHaveCount(1, "Sous un déploiement en sous-chemin, le @font-face de [{$face['target']}] ne vise pas [{$expected}] : quatre 404 muets et un repli en fonte système.");
        }

        foreach (FontManifest::preloaded() as $face) {
            $expected = "https://exemple.test/app/fonts/{$face['target']}";

            expect(str_contains($html, 'href="' . $expected . '"'))
                ->toBeTrue("Sous un déploiement en sous-chemin, le preload de [{$face['target']}] ne vise pas [{$expected}] : il pointerait ailleurs que son propre @font-face, donc second téléchargement complet.");
        }

        /*
         * Et la racine absolue ne doit subsister NULLE PART : c'est la forme
         * exacte du défaut d'origine, et un correctif à moitié appliqué la
         * laisserait d'un seul des deux côtés.
         */
        expect(str_contains($html, "url('/fonts/") || str_contains($html, 'href="/fonts/'))
            ->toBeFalse('Une URL de police est restée en racine absolue malgré le préfixe de déploiement.');
    } finally {
        $configured = config('app.asset_url');

        $url->useAssetOrigin(is_string($configured) ? $configured : null);
    }
});

it('refuse de rendre sous CSP_ENABLED=true avec CSP_NONCE_ENABLED=false (AC4)', function (): void {
    /*
     * ⛔ LA GARDE `nonce_enabled` AVAIT SON PROPRE PIÈGE. Décision D1 de la
     * seconde passe de revue du 2026-08-09.
     *
     * Le préréglage `Basic` de spatie/laravel-csp pose `style-src 'self'` PLUS
     * un nonce. Sous CSP_ENABLED=true + CSP_NONCE_ENABLED=false, le <style> part
     * sans nonce, `style-src 'self'` le bloque, LES QUATRE @font-face
     * DISPARAISSENT, la page rend en fonte système — et rien ne rougissait côté
     * serveur, parce que le test du nonce ne tourne que sous le défaut `true` :
     * il prouvait que la configuration sûre est sûre.
     *
     * Le composant SAIT, sous cette combinaison, qu'il ne peut pas garantir que
     * ses règles atteignent le navigateur. Il le dit maintenant. C'est la
     * doctrine déjà écrite dans config/fonts.php : l'échec est bruyant.
     */
    config([
        'csp.enabled' => true,
        'csp.nonce_enabled' => false,
    ]);

    /*
     * ⚠️ L'ASSERTION PORTE SUR LE MESSAGE, PAS SUR LA CLASSE. Blade enveloppe
     * toute exception levée pendant le rendu dans une `ViewException` : exiger
     * `RuntimeException` ferait rougir ce test pour une raison qui n'est pas la
     * sienne, et un futur changement d'enveloppe le casserait sans qu'aucun
     * comportement n'ait bougé. Ce qui compte est qu'il devienne IMPOSSIBLE de
     * rendre cette combinaison, et que le rouge nomme les deux variables.
     */
    $thrown = null;

    try {
        Blade::render('<x-font-preloads />');
    } catch (Throwable $exception) {
        $thrown = $exception;
    }

    expect($thrown)
        ->not->toBeNull('Le composant a rendu sous CSP_ENABLED=true + CSP_NONCE_ENABLED=false : le <style> partirait sans nonce, et les quatre @font-face disparaîtraient en silence.');

    expect(str_contains((string) $thrown?->getMessage(), 'CSP_ENABLED=true avec CSP_NONCE_ENABLED=false'))
        ->toBeTrue('Le refus ne nomme pas la combinaison fautive : un rouge qui ne se lit pas se fait désarmer au premier run pressé.');
});

it('rend les @font-face dans le <head> des deux layouts, avant @vite (AC4)', function (): void {
    /*
     * Le SEUL lien entre les règles et l'application. Il remplace le contrôle de
     * l'`@import './fonts.css'` d'app.css, devenu sans objet : sans lui, les
     * quatre règles n'atteignaient jamais le navigateur et absolument rien ne
     * rougissait côté serveur — le CSS compilé était simplement plus court.
     *
     * AVANT @vite pour la même raison que les preloads : une @font-face déclarée
     * après le chargement de la feuille principale est découverte plus tard, ce
     * qui annule l'intérêt du preload qui la précède.
     */
    foreach (['public', 'minimal'] as $layout) {
        $html = Blade::render("<x-layouts.{$layout}>Contenu</x-layouts.{$layout}>");

        expect(fontFaceBlocks($html))
            ->toHaveCount(count(FontManifest::faces()), "<x-layouts.{$layout}> ne rend pas les @font-face de la table : la page s'affichera en fonte système, sans une erreur.");

        $lastFace = mb_strrpos($html, '@font-face');
        $vite = mb_strpos($html, '/build/assets/app-');
        $headEnd = mb_strpos($html, '</head>');

        expect(is_int($lastFace) ? $lastFace : PHP_INT_MAX)
            ->toBeLessThan(is_int($vite) ? $vite : 0, "<x-layouts.{$layout}> déclare ses @font-face APRÈS @vite.");

        expect(is_int($lastFace) ? $lastFace : PHP_INT_MAX)
            ->toBeLessThan(is_int($headEnd) ? $headEnd : 0, "<x-layouts.{$layout}> déclare ses @font-face hors du <head>.");
    }
});

it('pose un nonce sur le <style> des @font-face, pour la CSP à venir (AC4)', function (): void {
    /*
     * La CSP est ÉTEINTE aujourd'hui (`CSP_ENABLED=false`, arbitrage PO du
     * 2026-08-09) — et c'est précisément pourquoi ce test existe maintenant.
     *
     * Le préréglage `Basic` de spatie/laravel-csp pose `style-src 'self'` plus un
     * nonce. Un <style> inline SANS nonce serait purement et simplement bloqué le
     * jour où la CSP s'allume : zéro @font-face, page en fonte système, et pas un
     * test rouge — puisque le HTML, lui, contiendrait toujours les règles. La
     * story notait que le self-hosting rendrait `font-src 'self'` trivial ; en
     * déplaçant les règles dans un <style>, la revue a créé la dette symétrique.
     * Elle est payée ici plutôt que découverte à l'Epic 4.
     */
    $html = Blade::render('<x-font-preloads />');

    expect(preg_match('/<style[^>]*\snonce="[^"]+"/', $html))
        ->toBe(1, 'Le <style> des @font-face ne porte pas de nonce : il sera bloqué dès que CSP_ENABLED passera à true.');
});

/*
|--------------------------------------------------------------------------
| AC5 — les preloads, dans les DEUX layouts
|--------------------------------------------------------------------------
*/

it('sert 4 faces et n\'en précharge que 3 — l\'arbitrage, écrit ICI EN DUR (AC5)', function (): void {
    /*
     * ⚠️ CE TEST EXISTE PARCE QU'UNE MUTATION LUI A SURVÉCU (2026-08-09, T10).
     *
     * Basculer un `preload` de `true` à `false` dans resources/fonts.json ne
     * faisait rougir personne. Le composant DÉRIVE son rendu de la table, et le
     * test qui le vérifie DÉRIVAIT ses attentes de la même table : les deux
     * côtés se calculaient l'un l'autre. Le compte restait cohérent, le preload
     * disparaissait, la page restait jolie — une police de moins au premier
     * rendu, et pas un test rouge. C'est mot pour mot la réserve écrite en tête
     * de tests/Fixtures/RelativeTimeCases.php : « une table que les deux côtés
     * liraient pour se calculer l'un l'autre ne prouverait rien ».
     *
     * Les valeurs ci-dessous sont donc ÉCRITES À LA MAIN, jamais dérivées. Elles
     * ne décrivent pas la table : elles décrivent la DÉCISION dont la table est
     * l'exécution.
     *
     *   UX-DR-42 + ux-design-specification.md:909 → 3 preloads.
     *   Échelle typographique (ux-design-specification.md:886-894) → 400, 500,
     *   600 employées par le code livré (`font-medium` est employé 8 fois, dont
     *   4 dans des composants déjà `done`).
     *   Arbitrage PO du 2026-08-09 → 4 faces SERVIES, 3 PRÉCHARGÉES.
     *
     * Précharger n'est pas self-héberger : la face 500 est servie pour que
     * `font-medium` existe (sans elle, CSS résout 500 vers 400 SANS synthèse —
     * rendu indiscernable, aucun signal), et elle n'est pas préchargée parce
     * qu'elle n'est pas garantie au-dessus de la ligne de flottaison.
     *
     * ⚠️ CE TEST DOIT RAIDIR. Changer la table sans changer ces lignes fait
     * rougir, et c'est le point : le jeu de preloads est un arbitrage produit, il
     * ne se modifie pas en marge d'un autre travail.
     */
    $servedExpected = [
        'IBM Plex Mono/400',
        'IBM Plex Sans/400',
        'IBM Plex Sans/500',
        'IBM Plex Sans/600',
    ];

    $preloadedExpected = [
        'IBM Plex Mono/400',
        'IBM Plex Sans/400',
        'IBM Plex Sans/600',
    ];

    $served = FontManifest::describe(FontManifest::faces());
    $preloaded = FontManifest::describe(FontManifest::preloaded());

    sort($served);
    sort($preloaded);

    expect($served)
        ->toBe($servedExpected, 'Les faces SERVIES ne sont plus celles de l\'arbitrage du 2026-08-09 (4 faces).');

    expect($preloaded)
        ->toBe($preloadedExpected, 'Les faces PRÉCHARGÉES ne sont plus celles d\'UX-DR-42 (3 preloads) : un preload ajouté dispute la bande passante au premier rendu, un preload retiré retarde une face au-dessus de la ligne de flottaison.');
});

it('précharge exactement les faces marquées preload dans les deux layouts (AC5)', function (): void {
    /*
     * Les DEUX, et c'est délibéré : <x-layouts.minimal> charge la même CSS que
     * <x-layouts.public>, donc les mêmes @font-face. Une page d'erreur qui perd
     * la police est une seconde source de vérité visuelle.
     *
     * Vu rouge : en retirant <x-font-preloads /> de minimal.blade.php.
     */
    $preloaded = FontManifest::preloaded();

    expect($preloaded)
        ->not->toBeEmpty('Aucune face n\'est marquée preload : le test ne prouve rien.');

    $layouts = [
        'public' => Blade::render('<x-layouts.public>Contenu</x-layouts.public>'),
        'minimal' => Blade::render('<x-layouts.minimal>Contenu</x-layouts.minimal>'),
    ];

    foreach ($layouts as $name => $html) {
        foreach ($preloaded as $face) {
            $expected = '<link rel="preload" as="font" type="font/woff2" crossorigin href="'
                . asset('fonts/' . $face['target']) . '">';

            expect(str_contains($html, $expected))
                ->toBeTrue("<x-layouts.{$name}> ne précharge pas [{$face['target']}] avec les quatre attributs attendus.");
        }

        // Le compte, et pas seulement la présence : un preload SURNUMÉRAIRE est
        // soit un href orphelin (404 silencieux), soit une face que personne n'a
        // décidé de précharger.
        expect(substr_count($html, 'as="font"'))
            ->toBe(count($preloaded), "<x-layouts.{$name}> ne précharge pas exactement " . count($preloaded) . ' faces.');
    }
});

it('ne précharge JAMAIS une face absente de la table (AC5)', function (): void {
    /*
     * La faute que cet AC existe pour attraper : un `href` qui ne correspond à
     * rien ne casse rien d'observable. Le navigateur télécharge un 404, l'avertit
     * dans une console que personne ne lit, puis charge la police normalement via
     * le @font-face — un peu plus tard. La page est correcte, le preload est mort.
     */
    $targets = array_map(static fn (array $face): string => $face['target'], FontManifest::faces());

    foreach (['public', 'minimal'] as $layout) {
        $html = Blade::render("<x-layouts.{$layout}>Contenu</x-layouts.{$layout}>");

        expect(preg_match_all('/as="font"[^>]*href="(?<href>[^"]+)"/', $html, $matches))
            ->toBeGreaterThan(0, "Aucun preload de police lu dans <x-layouts.{$layout}> : le test ne prouve rien.");

        /** @var list<non-empty-string> $hrefs */
        $hrefs = $matches['href'];

        foreach ($hrefs as $href) {
            expect(in_array(basename($href), $targets, true))
                ->toBeTrue("<x-layouts.{$layout}> précharge [{$href}], qui n'est décrit par aucune entrée de la table.");
        }
    }
});

it('rend les preloads AVANT les assets Vite, dans le <head> (AC5)', function (): void {
    /*
     * Un preload déclaré après le script qui déclenche le chargement de la CSS
     * arrive trop tard pour avancer quoi que ce soit : il reste vrai, visible
     * dans le HTML, testable par présence — et parfaitement inutile. La Story
     * 1.13 avait déjà posé cette contrainte d'ordre sur la pile head ; elle vaut
     * ici pour un balisage rendu directement.
     */
    foreach (['public', 'minimal'] as $layout) {
        $html = Blade::render("<x-layouts.{$layout}>Contenu</x-layouts.{$layout}>");

        $lastPreload = mb_strrpos($html, 'as="font"');
        $vite = mb_strpos($html, '/build/assets/app-');
        $headEnd = mb_strpos($html, '</head>');

        expect($lastPreload)
            ->not->toBeFalse("<x-layouts.{$layout}> ne rend aucun preload de police.");
        expect($vite)
            ->not->toBeFalse("<x-layouts.{$layout}> ne rend aucun asset Vite : la comparaison d'ordre serait vide.");
        expect($headEnd)
            ->not->toBeFalse("<x-layouts.{$layout}> n'a pas de </head>.");

        expect(is_int($lastPreload) ? $lastPreload : PHP_INT_MAX)
            ->toBeLessThan(is_int($vite) ? $vite : 0, "<x-layouts.{$layout}> précharge APRÈS @vite : le preload arrive trop tard.");

        expect(is_int($lastPreload) ? $lastPreload : PHP_INT_MAX)
            ->toBeLessThan(is_int($headEnd) ? $headEnd : 0, "<x-layouts.{$layout}> précharge hors du <head>.");
    }
});

it('n\'écrit le balisage de preload qu\'à UN seul endroit (AC5)', function () use ($stripComments): void {
    /*
     * Deux copies d'un même fragment de <head> divergent : l'une gagne un
     * attribut que l'autre n'a pas, et la page d'erreur télécharge ses polices
     * deux fois pendant que la page publique va bien. Les layouts INCLUENT, ils
     * ne recopient pas.
     */
    foreach (['public', 'minimal'] as $layout) {
        $source = $stripComments((string) file_get_contents(
            base_path("resources/views/components/layouts/{$layout}.blade.php"),
        ));

        expect(str_contains($source, 'rel="preload"'))
            ->toBeFalse("{$layout}.blade.php écrit un <link rel=\"preload\"> en dur : il doit inclure <x-font-preloads />.");

        expect(str_contains($source, '<x-font-preloads'))
            ->toBeTrue("{$layout}.blade.php n'inclut pas <x-font-preloads />.");
    }
});

it('fait inclure <x-font-preloads /> par TOUT template qui charge app.css (AC5)', function () use ($stripComments): void {
    /*
     * ⚠️ CE SCAN REMPLACE UNE LISTE LITTÉRALE DE DEUX LAYOUTS, ET C'EST LE
     * CORRECTIF LE PLUS LOURD DE LA SECONDE PASSE DE REVUE DU 2026-08-09.
     *
     * Sortir les @font-face d'`app.css` pour les rendre par un composant a
     * transformé UN point de déclaration global en N points d'inclusion. Avant,
     * toute page qui chargeait la feuille héritait des faces ; maintenant, chaque
     * page doit y penser. Or les tests AC5 énuméraient `['public', 'minimal']` en
     * dur — donc `welcome.blade.php`, LA SEULE ROUTE ATTEIGNABLE HORS
     * `local`/`testing`, n'était gardée par rien :
     *
     *   - supprimer son `<x-font-preloads />` laissait la suite ENTIÈREMENT verte,
     *     et recréait exactement le défaut pour lequel la décision de l'y ajouter
     *     avait été prise à la première passe (« les preloads livrés sur zéro page
     *     réelle ») ;
     *   - son propre commentaire annonçait « un test rougit sur un preload en
     *     double » le jour où elle passerait sur <x-layouts.public> — ce test
     *     n'existait pas davantage.
     *
     * Un garde-fou dont le périmètre est une liste écrite à la main est un
     * garde-fou qui rate le fichier suivant. Le périmètre est donc DÉRIVÉ : si un
     * template charge `resources/css/app.css`, il rend du texte avec nos familles,
     * donc il lui faut les faces. La règle n'a plus besoin d'être re-décidée.
     *
     * ⛔ ET LE SENS INVERSE EST GARDÉ AUSSI : exactement UNE inclusion par
     * template. Deux (un layout qui inclut + une page qui inclut encore) rendraient
     * les preloads et les @font-face en double — le navigateur téléchargerait deux
     * fois, sans erreur. C'est la moitié que le commentaire de welcome.blade.php
     * promettait et que personne n'avait écrite.
     */
    $consumers = [];

    foreach (BladeTemplates::all() as $template) {
        $name = BladeTemplates::relative($template);
        $raw = file_get_contents($template);

        if ($raw === false) {
            throw new RuntimeException("{$name} n'a pas pu être lu : le scan aurait conclu au vert sans rien lire.");
        }

        $source = $stripComments($raw);

        if (! str_contains($source, "'resources/css/app.css'")) {
            continue;
        }

        $consumers[] = $name;

        expect(mb_substr_count($source, '<x-font-preloads'))
            ->toBe(1, "{$name} charge app.css mais n'inclut pas <x-font-preloads /> exactement une fois : zéro, et la page rend en fonte système sans une erreur ; deux, et chaque police est téléchargée deux fois.");
    }

    /*
     * L'anti-vacuité : sans lui, un renommage d'`app.css` viderait le scan et le
     * laisserait vert sur zéro fichier. `welcome.blade.php` est nommé parce que
     * c'est LA page de production — la perdre de vue est le défaut d'origine.
     */
    expect($consumers)
        ->not->toBeEmpty('Aucun template ne charge app.css : le scan est vide, donc vert par vacuité.');

    expect(in_array('resources/views/welcome.blade.php', $consumers, true))
        ->toBeTrue('welcome.blade.php ne charge plus app.css : la seule route atteignable en production est sortie du périmètre de ce garde-fou.');
});

/*
|--------------------------------------------------------------------------
| AC9 — toute graisse employée par le code résout vers une face servie
|--------------------------------------------------------------------------
*/

it('signale les graisses non servies et les italiques, et SEULEMENT elles (auto-contrôle du scanner)', function () use (
    $findUnservedTypography
): void {
    /*
     * Leçon de la Story 1.8, re-signalée par la 1.13 : un scanner qui parcourt des
     * fichiers peut être vert par vacuité, ou vert par ignorance d'une forme
     * d'écriture. On l'exerce donc sur des fixtures synthétiques — celles qui
     * DOIVENT être signalées et celles qui ne DOIVENT PAS l'être — avant de le
     * lâcher sur le vrai code.
     */
    expect($findUnservedTypography('<p class="font-light">x</p>'))
        ->not->toBeEmpty('Le scanner laisse passer font-light (graisse 300, non servie).');
    expect($findUnservedTypography('<p class="font-bold">x</p>'))
        ->not->toBeEmpty('Le scanner laisse passer font-bold (graisse 700, non servie).');
    expect($findUnservedTypography('<p class="italic">x</p>'))
        ->not->toBeEmpty('Le scanner laisse passer `italic` : aucune face italique n\'est servie.');

    // Les VARIANTES produisent la même graisse, sous condition. Un scanner qui ne
    // verrait que la forme nue serait vert sur la moitié du code réel.
    expect($findUnservedTypography('<p class="lg:font-bold">x</p>'))
        ->not->toBeEmpty('Le scanner ignore les variantes de point de rupture.');
    expect($findUnservedTypography('<p class="hover:font-thin">x</p>'))
        ->not->toBeEmpty('Le scanner ignore les variantes d\'état.');
    expect($findUnservedTypography('<p class="md:italic">x</p>'))
        ->not->toBeEmpty('Le scanner ignore `italic` sous variante.');

    // Faux positifs à ne pas produire.
    expect($findUnservedTypography('<p class="font-normal font-medium font-semibold">x</p>'))
        ->toBeEmpty('Le scanner signale des graisses pourtant servies (400/500/600).');
    expect($findUnservedTypography('<p class="font-sans font-mono">x</p>'))
        ->toBeEmpty('Le scanner confond les utilities de FAMILLE avec des graisses.');
    expect($findUnservedTypography('<p class="not-italic">x</p>'))
        ->toBeEmpty('Le scanner confond `not-italic` (font-style: normal) avec `italic`.');
    expect($findUnservedTypography('<p class="font-boldish font-lightbox">x</p>'))
        ->toBeEmpty('Le scanner signale des classes qui ne font que COMMENCER comme une utility.');

    /*
     * ⚠️ LES QUATRE FORMES NON-UTILITY, AJOUTÉES À LA REVUE DU 2026-08-09. Elles
     * produisent exactement la même graisse et échappaient toutes les quatre à un
     * scan qui ne connaissait que les neuf noms de classe. Une graisse
     * intermédiaire manquante est résolue SANS synthèse : le rendu est
     * indiscernable, quelle que soit la manière dont la graisse a été demandée.
     */
    expect($findUnservedTypography('<p class="font-[350]">x</p>'))
        ->not->toBeEmpty('Le scanner ignore les valeurs arbitraires numériques (font-[350]).');
    expect($findUnservedTypography('<p class="font-(--poids)">x</p>'))
        ->not->toBeEmpty('Le scanner laisse passer une graisse pilotée par propriété personnalisée : elle est INDÉTERMINABLE, donc invérifiable.');
    expect($findUnservedTypography('<p style="font-weight: 300">x</p>'))
        ->not->toBeEmpty('Le scanner ignore un font-weight écrit en CSS inline.');
    expect($findUnservedTypography('<p style="font-weight: bold">x</p>'))
        ->not->toBeEmpty('Le scanner ignore le mot-clé `bold` (graisse 700, non servie).');
    expect($findUnservedTypography('<p>du <strong>gras</strong></p>'))
        ->not->toBeEmpty('Le scanner ignore la préflight Tailwind : <strong> demande 700, non servi, donc un faux-gras synthétisé.');
    expect($findUnservedTypography('<p>du <b>gras</b></p>'))
        ->not->toBeEmpty('Le scanner ignore <b>, qui porte la même règle de préflight que <strong>.');
    expect($findUnservedTypography('<p style="font-style: italic">x</p>'))
        ->not->toBeEmpty('Le scanner ignore un font-style: italic écrit en CSS.');

    // Faux positifs à ne pas produire sur ces mêmes formes.
    expect($findUnservedTypography('<p class="font-[500]" style="font-weight: 600">x</p>'))
        ->toBeEmpty('Le scanner signale des graisses arbitraires pourtant servies (500/600).');
    expect($findUnservedTypography('<br><body><button>x</button>'))
        ->toBeEmpty('Le scanner confond <br>, <body> ou <button> avec la balise <b>.');
    expect($findUnservedTypography('<p>Un texte en italique, façon note.</p>'))
        ->toBeEmpty('Le scanner signale le mot « italic » hors d\'un attribut class : un faux positif bruyant finit par désarmer le garde-fou.');
    expect($findUnservedTypography('<p>font-weight: {{ $face[\'weight\'] }};</p>'))
        ->toBeEmpty('Le scanner signale un font-weight interpolé, dont la valeur n\'est pas un littéral.');
});

it('signale une graisse non servie POSÉE SUR font-mono, et seulement elle (auto-contrôle du scanner)', function () use (
    $findMonoWeightMismatches
): void {
    /*
     * Le cas silencieux par excellence : la table sert du mono en 400 seulement.
     * Un `font-medium` sur du `font-mono` résout vers 400 SANS synthèse — rendu
     * strictement identique, aucune erreur, aucun test rouge.
     */
    expect($findMonoWeightMismatches('<p class="font-mono font-medium">x</p>'))
        ->not->toBeEmpty('Le scanner laisse passer une graisse 500 sur du mono.');
    expect($findMonoWeightMismatches("<p class='font-mono font-semibold'>x</p>"))
        ->not->toBeEmpty('Le scanner ne connaît que les guillemets doubles.');

    expect($findMonoWeightMismatches('<p class="font-mono font-normal">x</p>'))
        ->toBeEmpty('Le scanner signale la graisse 400, pourtant servie en mono.');
    expect($findMonoWeightMismatches('<p class="font-mono">x</p><p class="font-medium">y</p>'))
        ->toBeEmpty('Le scanner rapproche deux attributs class DISTINCTS.');

    /*
     * ⚠️ LA FORME DU CODE RÉEL, ET LE SCANNER NE LA CONNAISSAIT PAS. Les quatre
     * `<x-time-*>` n'écrivent aucun `class="…"` littéral : ils passent par
     * `$attributes->merge(['class' => 'font-mono …'])`. Mesuré à la revue du
     * 2026-08-09 : 0 attribut capturé sur les 4, alors que chacun emploie
     * `font-mono`. Le garde-fou était vide sur 100 % de sa cible — et son
     * auto-contrôle ne pouvait pas l'attraper, faute d'une fixture de cette forme.
     * C'est la leçon de la 1.13 (les guillemets doubles) une case plus loin.
     */
    expect($findMonoWeightMismatches("\$attributes->merge(['class' => 'font-mono font-medium'])"))
        ->not->toBeEmpty('Le scanner ne connaît que les attributs HTML littéraux : il ne voit AUCUN des composants qui emploient réellement font-mono.');
    expect($findMonoWeightMismatches('$attributes->merge(["class" => "font-mono font-semibold"])'))
        ->not->toBeEmpty('Le scanner ne connaît la forme tableau qu\'en guillemets simples.');
    expect($findMonoWeightMismatches("\$attributes->merge(['class' => 'font-mono text-sm'])"))
        ->toBeEmpty('Le scanner signale un font-mono sans graisse dans la forme tableau.');
});

it('n\'emploie dans aucun template une graisse ou un style sans face servie (AC9)', function () use (
    $stripComments,
    $findUnservedTypography,
    $findMonoWeightMismatches
): void {
    /*
     * Vu rouge : en introduisant un `font-light` dans un composant, puis en le
     * retirant.
     *
     * ⚠️ Ce scan est la contrepartie de l'arbitrage PO du 2026-08-09 (4 faces
     * servies, 3 préchargées). Il rend impossible qu'un écart entre l'échelle
     * typographique de l'UX et les faces réellement servies reste TACITE : une
     * graisse employée sans face fait rougir, quelle que soit la table retenue.
     */
    /*
     * ⚠️ `all()` ET PAS `scanned()`. L'AC9 dit « l'ensemble des templates Blade
     * de l'application » ; `scanned()` en couvrait 18 sur 20, et son compteur ne
     * raidissait qu'à l'INTÉRIEUR de son propre périmètre — `welcome.blade.php`
     * (la page servie par `/`) et `vendor/pulse/dashboard.blade.php` en étaient
     * absents, donc invisibles au scan ET au compteur. Relevé à la revue du
     * 2026-08-09. Le défaut de périmètre était déjà inscrit dans
     * `deferred-work.md` depuis la 1.12 ; cette story avait écrit un AC plus
     * large que lui sans le rouvrir.
     */
    $templates = BladeTemplates::all();

    expect($templates)
        ->not->toBeEmpty('Le scan des graisses n\'a trouvé aucun template à inspecter.');

    expect($templates)
        ->toHaveCount(BladeTemplates::ALL_COUNT, 'Un template a été ajouté ou retiré sans mettre ce garde-fou à jour.');

    foreach ($templates as $template) {
        $name = BladeTemplates::relative($template);
        $raw = file_get_contents($template);

        /*
         * ⚠️ UN FICHIER ILLISIBLE N'EST PAS UN FICHIER PROPRE. Relevé à la seconde
         * passe de revue du 2026-08-09 : `(string) file_get_contents()` vaut `''`
         * quand la lecture échoue, et tous les scans ci-dessous passent alors à
         * vide — vert, sur un template que personne n'a lu. `ALL_COUNT` garantit
         * que le fichier EXISTE, jamais qu'il a été LU : l'auto-contrôle de l'AC9
         * ne couvrait pas cette forme.
         */
        if ($raw === false) {
            throw new RuntimeException("{$name} n'a pas pu être lu : le scan des graisses aurait conclu au vert sans rien lire.");
        }

        $code = $stripComments($raw);

        expect($findUnservedTypography($code))
            ->toBeEmpty("{$name} emploie une graisse ou un style sans face self-hostée correspondante.");

        expect($findMonoWeightMismatches($code))
            ->toBeEmpty("{$name} pose une graisse sur du font-mono sans face mono correspondante.");
    }
});

/*
|--------------------------------------------------------------------------
| T8 — la page de démonstration ne doit pas exister en production
|--------------------------------------------------------------------------
*/

it('répond 200 sur la page de démonstration des polices (T8)', function (): void {
    /*
     * Elle passe par le groupe `web`, donc par SetCurrentStreamer. Sans
     * streamer semé, il lève NoStreamerConfiguredException et elle répond 500 —
     * et les tests navigateur rougiraient pour une raison étrangère aux
     * polices. (Avant le 2026-08-10 c'était un 404 : voir l'entrée fermée de
     * deferred-work.md.)
     */
    App\Core\Models\Streamer::factory()->create();

    $response = app(Kernel::class)->handle(Request::create(route('fonts.demo')));

    expect($response->getStatusCode())
        ->toBe(200, 'La page de démonstration des polices ne répond pas 200.');
});

it('n\'enregistre la page de démonstration des polices qu\'en local et testing (T8)', function (): void {
    /*
     * Première des deux gardes. Vu rouge : en retirant le
     * `if (app()->environment([...]))` de routes/web.php.
     */
    foreach (['local', 'testing'] as $environment) {
        expect(RouteTable::registeredIn($environment)->getByName('fonts.demo'))
            ->not->toBeNull("La page [fonts.demo] devrait être disponible en [{$environment}].");
    }

    $production = RouteTable::registeredIn('production');

    // Anti-vacuité : si le fichier de routes n'avait pas été rejoué, la route
    // serait absente pour une mauvaise raison et ce test serait vert sans rien
    // prouver.
    expect(count($production->getRoutes()))
        ->toBeGreaterThan(0, 'routes/web.php n\'a pas été rejoué : le test ne prouve rien.');

    expect($production->getByName('fonts.demo'))
        ->toBeNull('La page [fonts.demo] est exposée en production : surface inutile, non gardée.');
});

it('refuse la page de démonstration des polices à la requête, même si la route existe (T8)', function (): void {
    /*
     * Le second verrou, celui qui survit à `php artisan route:cache` — un cache
     * construit en local puis déployé embarquerait la route malgré la première
     * garde, et aucun test ne pourrait le voir.
     *
     * La Story 1.11 ne testait qu'une des deux gardes ; la 1.13 a corrigé. Ne pas
     * régresser.
     *
     * Vu rouge : en retirant l'abort_unless() de la route /_fonts.
     */
    App\Core\Models\Streamer::factory()->create();

    $previous = app()
        ->environment();
    $previousEnvironment = is_string($previous) ? $previous : 'testing';

    app()
        ->detectEnvironment(static fn (): string => 'production');

    try {
        $response = app(Kernel::class)->handle(Request::create('/_fonts'));

        expect($response->getStatusCode())
            ->toBe(404, '[/_fonts] a servi une page de démonstration en production.');
    } finally {
        app()->detectEnvironment(static fn (): string => $previousEnvironment);
    }
});

it('emploie CHAQUE face de la table dans la page de démonstration (T8)', function () use ($stripComments): void {
    /*
     * Sans usage, pas de chargement : `font-display: swap` ne déclenche le
     * téléchargement qu'au premier élément qui demande la face, et le preload
     * seul laisse le statut à `unloaded`. Une face qu'aucun élément n'emploie
     * rendrait l'assertion navigateur de l'AC6 vide de sens pour cette face — et
     * elle serait vide EN SILENCE.
     *
     * Ce test garde donc la page de démonstration elle-même : ajouter une face à
     * la table sans lui donner un élément fait rougir ICI, avant que la suite
     * navigateur ne mesure une absence sans savoir pourquoi.
     */
    /*
     * ⚠️ TROIS DÉFAUTS CORRIGÉS À LA REVUE DU 2026-08-09, ET LES TROIS FAISAIENT
     * QUE CE TEST NE POUVAIT PAS ÉCHOUER LÀ OÙ IL LE PRÉTENDAIT.
     *
     *  1. Le témoin de la graisse 400 était `leading-prose` — une utility de
     *     HAUTEUR DE LIGNE, présente dans les quatre sections. Elle ne disait
     *     rien de la graisse : l'assertion était satisfaite par n'importe quelle
     *     section de la page. Le témoin doit être la chose observée.
     *  2. Les faces mono sautaient le contrôle d'utility (`if (! $isMono …)`) :
     *     une section #face-mono-400 qui aurait perdu son `font-mono` restait
     *     verte ici, et l'AC6 échouait plus tard sans explication — le scénario
     *     obscur que ce test dit exister pour éviter.
     *  3. Une graisse hors de la table de témoins ne recevait AUCUN contrôle, en
     *     silence : une face sans-700 ajoutée avec une section vide passait. Le
     *     témoin manquant est désormais un ÉCHEC, pas un saut.
     *
     * ⚠️ QUATRIÈME DÉFAUT, RELEVÉ À LA SECONDE PASSE DU 2026-08-09 : LE MARQUEUR
     * EST BINAIRE, DONC UNE TROISIÈME FAMILLE ENTRE EN COLLISION EN SILENCE.
     * `$marker` se dérive en `face-mono-<poids>` OU `face-sans-<poids>` — tout ce
     * qui n'est pas mono est « sans ». Ajouter `IBM Plex Serif 400` à la table
     * produit donc `face-sans-400`, un marqueur QUI EXISTE DÉJÀ, et un témoin
     * (`font-normal`) que cette section porte déjà : l'assertion passe sur la
     * section d'UNE AUTRE FACE, la nouvelle n'est jamais exercée par /_fonts, et
     * l'AC6 la rapporte `unloaded` plus tard sans explication. C'est exactement
     * la forme de MR-4 — deux côtés d'un garde-fou qui se satisfont l'un l'autre
     * — une branche plus loin.
     *
     * L'unicité des marqueurs est donc contrôlée AVANT la boucle. Ce que ce
     * contrôle ne peut PAS faire, et qui est écrit plutôt que tu : le témoin de
     * graisse (`font-normal`…) ne distingue pas deux familles qui partagent un
     * poids. C'est l'unicité du marqueur qui convertit ce cas en rouge nommé —
     * « donne à cette famille son propre marqueur » — au lieu d'un vert muet.
     */
    $utilityFor = [
        400 => 'font-normal',
        500 => 'font-medium',
        600 => 'font-semibold',
    ];

    $markerFor = static function (string $family, int $weight): string {
        return (str_contains(mb_strtolower($family), 'mono') ? 'face-mono-' : 'face-sans-') . $weight;
    };

    $markers = array_map(
        static fn (array $face): string => $markerFor($face['family'], $face['weight']),
        FontManifest::faces(),
    );

    expect(array_unique($markers))
        ->toHaveCount(count($markers), 'Deux faces de la table dérivent le MÊME marqueur de section : le témoin de l\'une serait satisfait par la section de l\'autre, et la face en trop ne serait jamais exercée. Marqueurs : ' . implode(', ', $markers) . '.');

    // Commentaires retirés : la page a le droit d'EXPLIQUER une utility qu'elle
    // n'emploie pas, et c'est exactement ce que fait sa note sur `leading-prose`.
    $html = $stripComments((string) file_get_contents(base_path('resources/views/_fonts-demo.blade.php')));

    foreach (FontManifest::faces() as $face) {
        $isMono = str_contains(mb_strtolower($face['family']), 'mono');
        $marker = $markerFor($face['family'], $face['weight']);

        expect(str_contains($html, $marker))
            ->toBeTrue("La page de démonstration n'a pas de section [#{$marker}] : la face {$face['family']} {$face['weight']} ne sera jamais chargée, et l'AC6 mesurera une absence sans raison.");

        expect(isset($utilityFor[$face['weight']]))
            ->toBeTrue("Aucune utility témoin n'est connue pour la graisse {$face['weight']} : la face serait ajoutée à la table sans que rien ne vérifie qu'un élément l'exerce.");

        /*
         * Le témoin est cherché DANS LE CORPS DE LA SECTION de la face, pas dans
         * la page entière : `font-medium` écrit ailleurs suffisait sinon à valider
         * la face 500, même si sa propre section ne l'employait pas.
         *
         * ⚠️ LA FENÊTRE COMMENCE APRÈS LE `</h2>`, ET C'EST UNE MUTATION QUI L'A
         * IMPOSÉ. Avec la section entière, retirer `font-mono` du paragraphe de
         * #face-mono-400 laissait le test VERT : chaque section titre son exemple
         * avec un `<h2 class="font-mono …">`, donc le témoin de la face mono était
         * satisfait par le libellé de la section plutôt que par son contenu.
         * Mutation MR-4, rejouée à la revue du 2026-08-09 — survivante d'abord,
         * rouge ensuite.
         *
         * La borne haute est le `</section>` suivant, jamais un nombre de
         * caractères : une fenêtre fixe se fait déborder par le premier
         * commentaire un peu long, et le rouge qui s'ensuit n'a rien à voir avec
         * la faute.
         */
        $start = mb_strpos($html, $marker);
        $bodyStart = is_int($start) ? mb_strpos($html, '</h2>', $start) : false;
        $end = is_int($bodyStart) ? mb_strpos($html, '</section>', $bodyStart) : false;
        $section = is_int($bodyStart) && is_int($end) ? mb_substr($html, $bodyStart, $end - $bodyStart) : '';
        $witness = $isMono ? 'font-mono' : ($utilityFor[$face['weight']] ?? '');

        expect($section)
            ->not->toBe('', "La section [#{$marker}] n'a pas la forme attendue (<h2> puis un corps, dans une <section>) : le témoin serait cherché dans une chaîne vide.");

        expect(str_contains($section, $witness))
            ->toBeTrue("La section [#{$marker}] n'emploie pas [{$witness}] : la face n'est pas exercée, donc jamais chargée.");
    }
});
