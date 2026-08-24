<?php

declare(strict_types=1);

use Tests\Support\RepoFile;

/**
 * Garde-fou sur les référents de la reading room.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CE TEST EXISTE
 *
 * `docs/reading-room/` est un jeu de pages écrites À LA MAIN qui décrivent le
 * projet : le produit, le plan, les exigences, l'architecture, les décisions, la
 * doctrine de qualité et l'état réel. Elles n'ont AUCUNE autorité — la
 * hiérarchie du projet reste ADR > epics.md + sprint-status.yaml > ETAT.md, et
 * ces pages se rangent dessous. Elles le disent sur elles-mêmes, en tête.
 *
 * Une page écrite à la main dérive. C'est acquis, et ce test ne prétend pas
 * l'empêcher. Ce qu'il empêche est plus étroit et plus important : que les pages
 * citent des fichiers — ou des ancres — qui n'existent pas.
 *
 * C'est exactement le motif dominant du dépôt — « l'affirmation précède son
 * référent ». Un document qui renvoie vers `docs/adr/ADR-0009-…` après un
 * renommage n'affiche pas d'erreur : il continue de se lire normalement, et sa
 * fausseté ne se découvre qu'au clic, par quelqu'un qui n'osera pas conclure que
 * le document a tort.
 *
 * D'où la forme retenue : TOUTE citation de fichier y est un lien relatif
 * cliquable. Un seul mécanisme sert deux fins — le lecteur ouvre la source, et
 * ce test vérifie qu'elle est là.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * 🔄 ÉLARGI le 2026-08-24 — la reading room est passée d'une page à huit.
 *
 * L'ancienne version ne connaissait que `index.html`. Trois conséquences, toutes
 * mesurées avant réécriture :
 *
 *   1. Sept pages sur huit n'étaient gardées par RIEN. Le garde-fou aurait été
 *      vert pendant qu'une page entière citait des chemins morts.
 *   2. L'assertion d'exhaustivité des ADR portait sur `index.html`, où la table
 *      ne vit plus : elle vit dans `decisions.html`. Laisser le test tel quel
 *      l'aurait fait rougir pour un déplacement légitime — c'est-à-dire punir la
 *      réorganisation au lieu de garder l'invariant.
 *   3. Les liens INTER-PAGES portent des ancres (`qualite.html#principe`). Le
 *      motif d'extraction d'origine les prenait pour des noms de fichier et
 *      cherchait un fichier littéralement nommé `qualite.html#principe` :
 *      8 faux positifs au premier passage. D'où `splitTarget()`.
 *
 * ⚠️ CE QUE CE TEST NE COUVRE PAS, et il faut le savoir avant de s'y fier :
 *
 *   1. Les NOMBRES. « 423 tests », « 78,8 % », « 4 / 13 » ne sont vérifiés par
 *      rien ici et dériveront. Les pages les affichent donc avec leur provenance
 *      et une date de lecture, et répètent qu'elles ne valent pas preuve.
 *   2. Les chemins écrits en PROSE sans être des liens (`<code>`). Ils sont
 *      volontairement employés pour ce qui n'est pas un fichier versionné
 *      (`_bmad-output/` est gitignoré) ou pour des chemins illustratifs. Un
 *      chemin réel qu'on veut voir gardé doit être écrit comme un LIEN.
 *   3. Le CONTENU de `data/plan.js`. Le fichier doit exister — c'est tout. Sa
 *      fraîcheur est un instantané daté, régénérable par `make reading-room`.
 *   4. Les URL absolues : hors périmètre, les pages n'en portent pas vers
 *      l'extérieur (elles s'ouvrent hors ligne).
 *
 * ⚠️ Les QUATRE assertions ont été OBSERVÉES ROUGES avant d'être déclarées
 * opérantes (2026-08-24) : la première en injectant un lien vers un fichier
 * absent, la deuxième en cassant l'extraction, la troisième en posant un ADR sur
 * disque sans le citer, la quatrième en pointant vers une ancre inexistante.
 * Aucune n'est écrite après coup sur du vert.
 *
 * ⚠️ Et une MUTATION AVAIT SURVÉCU à la version d'origine (M3) : dé-baliser 25
 * liens d'un coup laissait la page au-dessus d'un plancher fixé à 20, donc
 * verte. Un plancher très au-dessous du contenu réel n'attrape que
 * l'effondrement total, jamais l'érosion — et l'érosion est le mode de défaut
 * d'un document. Le plancher est donc DOUBLE ici : un plancher global, ET un
 * plancher PAR PAGE, pour qu'une page vidée ne se cache pas derrière les sept
 * autres.
 *
 * @see docs/reading-room/index.html
 * @see src/tests/Unit/BoostGuidelinesTest.php  (même forme, même motif)
 */
const READING_ROOM_DIR = 'docs/reading-room';

/**
 * Les pages de la reading room, chemins relatifs à la racine du dépôt.
 *
 * ⚠️ La liste est LUE SUR LE DISQUE, jamais écrite en dur. Une page ajoutée est
 * gardée sans qu'on y pense ; une liste en dur aurait le défaut exact que ce
 * test traque — elle serait juste le jour où on l'écrit.
 *
 * @return list<string>
 */
function readingRoomPages(): array
{
    $paths = glob(RepoFile::root() . '/' . READING_ROOM_DIR . '/*.html') ?: [];

    sort($paths);

    return array_values(array_map(
        static fn (string $absolute): string => READING_ROOM_DIR . '/' . basename($absolute),
        $paths,
    ));
}

/**
 * Les cibles de liens relatifs d'une page, dans l'ordre du document.
 *
 * On écarte les ancres internes, les URL absolues et les `mailto:` — seuls
 * restent les chemins de fichiers, qui sont précisément ce qu'on garde.
 *
 * @return list<string>
 */
function readingRoomLinkTargets(string $html): array
{
    // ⚠️ L'ancrage `(?<![\w-])` n'est pas décoratif : sans lui, le motif matche
    // AUSSI à l'intérieur de `data-href="…"`, `x-href="…"`, etc. C'est ce qui a
    // fait SURVIVRE la mutation M3 au premier jet — renommer les attributs
    // `href` en `data-href` laissait les cibles distinctes intactes aux yeux du
    // test. Le défaut était dans le garde-fou, pas dans la page.
    preg_match_all('/(?<![\w-])href="([^"]+)"/', $html, $matches);

    /** @var list<string> $targets */
    $targets = array_values(array_unique(array_filter(
        $matches[1],
        // Le motif `[^"]+` garantit déjà le non-vide : ne reste à écarter que
        // les ancres purement internes et tout ce qui porte un schéma.
        static fn (string $href): bool => ! str_starts_with($href, '#')
            && ! preg_match('#^[a-z][a-z0-9+.-]*:#i', $href),
    )));

    return $targets;
}

/**
 * Sépare un lien en sa partie fichier, sa requête et son ancre éventuelle.
 *
 * `qualite.html#principe` doit être vérifié en DEUX temps : le fichier existe,
 * puis l'ancre y existe. Les traiter comme un seul chemin donnait 8 faux
 * positifs — et les avoir « corrigés » en retirant les ancres aurait appauvri la
 * navigation pour faire taire un test.
 *
 * ⚠️ La requête (`epics.html?epic=5`) est écartée de la même façon, et pour une
 * raison qui vaut d'être écrite : les renvois vers un epic emploient cette forme
 * PRÉCISÉMENT parce que `#epic-5` est une ancre produite au rendu par
 * `assets/rr.js`. Une ancre qu'aucun garde-fou statique ne peut vérifier est une
 * cible qui pourrit en silence ; une requête, non.
 *
 * @return array{0: string, 1: string} [chemin, ancre sans le `#`]
 */
function splitTarget(string $href): array
{
    $anchor = '';
    $hash = strpos($href, '#');

    if ($hash !== false) {
        $anchor = substr($href, $hash + 1);
        $href = substr($href, 0, $hash);
    }

    $query = strpos($href, '?');

    if ($query !== false) {
        $href = substr($href, 0, $query);
    }

    return [$href, $anchor];
}

/**
 * Résout un chemin contenant des `..` sans toucher au disque.
 *
 * `realpath()` ne convient pas : il renvoie `false` pour une cible absente,
 * c'est-à-dire exactement le cas que ce test doit SIGNALER. On veut le chemin
 * résolu même quand il ne mène nulle part, pour pouvoir le nommer dans le
 * message d'échec.
 */
function resolveRelative(string $base, string $relative): string
{
    $segments = [];

    foreach (explode('/', $base . '/' . $relative) as $segment) {
        if ($segment === '' || $segment === '.') {
            continue;
        }

        if ($segment === '..') {
            array_pop($segments);

            continue;
        }

        $segments[] = $segment;
    }

    return '/' . implode('/', $segments);
}

it('ne laisse AUCUN lien de la reading room pointer vers un fichier absent', function (): void {
    $pages = readingRoomPages();

    // Anti-vacuité du glob lui-même : si le répertoire était vide ou déplacé,
    // la boucle ci-dessous ne tournerait pas et l'assertion serait verte en
    // n'ayant rien vérifié.
    expect($pages)
        ->not->toBeEmpty('Aucune page trouvée dans ' . READING_ROOM_DIR . ' : le glob est cassé.');

    $unresolved = [];

    foreach ($pages as $page) {
        $base = dirname(RepoFile::root() . '/' . $page);

        foreach (readingRoomLinkTargets(RepoFile::read($page)) as $target) {
            [$file] = splitTarget($target);

            // Un lien purement local (`#ancre`) est déjà écarté à l'extraction ;
            // ce cas-ci est `page.html#ancre` réduit à une chaîne vide, qui ne
            // peut pas se produire, mais coûte une ligne à écarter proprement.
            if ($file === '') {
                continue;
            }

            $path = resolveRelative($base, $file);

            if (! file_exists($path)) {
                $unresolved[] = "{$page} → {$target}  (cherché : {$path})";
            }
        }
    }

    expect($unresolved)
        ->toBe([], sprintf(
            "La reading room cite %d fichier(s) qui n'existe(nt) pas :\n  - %s\n\n"
                . 'Un document qui renvoie vers un chemin absent est une affirmation sans '
                . 'référent — le motif dominant de ce dépôt. Deux issues, pas trois : '
                . 'corriger le lien, ou retirer la phrase qui en dépend. Ne pas transformer '
                . 'le lien en texte brut pour faire taire ce test : la phrase resterait fausse, '
                . 'sans plus rien pour le dire.',
            count($unresolved),
            implode("\n  - ", $unresolved),
        ));
});

it('vérifie effectivement quelque chose — chaque page cite des fichiers, et le total est élevé', function (): void {
    $pages = readingRoomPages();
    $perPage = [];

    foreach ($pages as $page) {
        $perPage[$page] = count(readingRoomLinkTargets(RepoFile::read($page)));
    }

    // Anti-vacuité. Sans ce contrôle, casser l'extraction (une regex qui ne
    // matche plus, une page réécrite sans liens) rendrait l'assertion
    // précédente VERTE en n'ayant rien vérifié — la forme la plus pure du
    // garde-fou silencieux, dans le test censé le traquer.
    //
    // ⚠️ Le plancher est DOUBLE, et ce n'est pas du zèle. Un plancher
    // uniquement global laisserait une page se vider entièrement pendant que
    // les sept autres portent le total : c'est la mutation M3 (2026-08-20)
    // rejouée à l'échelle du répertoire. Chaque page doit donc tenir seule.
    $anemic = array_filter($perPage, static fn (int $count): bool => $count < 8);

    expect($anemic)
        ->toBe([], sprintf(
            "Page(s) de la reading room devenue(s) pauvre(s) en référents : %s.\n"
                . "Soit la page a perdu ses liens, soit l'extraction est cassée — dans les "
                . "deux cas l'assertion de résolution ne garde plus cette page.",
            implode(', ', array_map(
                static fn (string $p, int $n): string => "{$p} ({$n})",
                array_keys($anemic),
                $anemic,
            )) ?: '—',
        ));

    expect(array_sum($perPage))
        ->toBeGreaterThanOrEqual(90, sprintf(
            'Seulement %d lien(s) de fichier détecté(s) sur %d page(s). '
                . "L'érosion est le mode de défaut d'un document : ce plancher existe pour "
                . "l'attraper avant l'effondrement.",
            array_sum($perPage),
            count($pages),
        ));
});

it('cite TOUS les ADR du dépôt, parce que sa table se présente comme exhaustive', function (): void {
    // Ce test ne compare pas la reading room à elle-même : le côté « attendu »
    // est le DISQUE (`docs/adr/ADR-*.md`), le côté « constaté » est l'ensemble
    // des pages. C'est la leçon de la mutation survivante MF-D de la Story 1.9 —
    // un composant et son test qui dérivent tous deux de la même table ne
    // gardent rien.
    //
    // ⚠️ Le périmètre est le RÉPERTOIRE, pas une page nommée. La table vit
    // aujourd'hui dans `decisions.html` ; l'épingler par son nom de fichier
    // ferait rougir ce test au prochain déplacement légitime, c'est-à-dire
    // punirait la réorganisation au lieu de garder l'invariant.
    //
    // Il rougit donc dans le seul cas qui compte : un ADR ajouté au dépôt et
    // absent d'une table qui annonce les recenser tous. La reading room a le
    // droit de ne pas être exhaustive — mais alors elle doit cesser de le
    // prétendre, et ce test doit partir avec la prétention.
    $cited = [];

    foreach (readingRoomPages() as $page) {
        foreach (readingRoomLinkTargets(RepoFile::read($page)) as $href) {
            if (str_contains($href, '/adr/ADR-')) {
                [$file] = splitTarget($href);
                $cited[] = basename($file);
            }
        }
    }

    $cited = array_values(array_unique($cited));

    $onDisk = array_map(
        'basename',
        glob(RepoFile::root() . '/docs/adr/ADR-*.md') ?: [],
    );

    sort($cited);
    sort($onDisk);

    expect($onDisk)
        ->not->toBeEmpty('Aucun ADR trouvé sur disque : le glob est cassé.');

    expect(array_values(array_diff($onDisk, $cited)))
        ->toBe([], sprintf(
            "La table des ADR de la reading room n'est plus exhaustive : "
                . '%d ADR sur disque, %d cités. Manquant(s) : %s.',
            count($onDisk),
            count($cited),
            implode(', ', array_diff($onDisk, $cited)) ?: '—',
        ));
});

it('ne laisse AUCUN lien inter-pages pointer vers une ancre inexistante', function (): void {
    // 🆕 Assertion ajoutée le 2026-08-24, avec le passage à huit pages.
    //
    // Une reading room multi-pages se navigue par renvois : « voir la doctrine
    // complète », « le détail est ici ». Ces renvois portent des ancres, et une
    // ancre est EXACTEMENT le genre de référent qui pourrit en silence — on
    // renomme une section, le lien continue d'exister, il atterrit simplement en
    // haut de la page cible. Aucun signal, aucune erreur, et un lecteur qui
    // conclut qu'il n'a pas su chercher.
    //
    // Le périmètre est volontairement étroit : uniquement les ancres qui visent
    // une page de la reading room. Une ancre vers un Markdown de `docs/` dépend
    // du rendu du visualiseur (GitHub translittère, un autre non) — la garder
    // ici serait fragile pour une raison étrangère au sujet.
    $pages = readingRoomPages();

    /** @var array<string, list<string>> $idsByPage */
    $idsByPage = [];

    foreach ($pages as $page) {
        preg_match_all('/\bid="([^"]+)"/', RepoFile::read($page), $matches);
        $idsByPage[basename($page)] = $matches[1];
    }

    // Anti-vacuité : sans identifiants extraits, toute ancre serait déclarée
    // absente — le test rougirait pour la mauvaise raison — ou, si la boucle
    // était vide, il passerait sans rien vérifier.
    expect(array_sum(array_map('count', $idsByPage)))
        ->toBeGreaterThan(40, "Trop peu d'identifiants extraits : l'extraction des `id=` est cassée.");

    $dangling = [];

    foreach ($pages as $page) {
        foreach (readingRoomLinkTargets(RepoFile::read($page)) as $target) {
            [$file, $anchor] = splitTarget($target);

            if ($anchor === '' || ! str_ends_with($file, '.html')) {
                continue;
            }

            $targetPage = basename($file);

            if (! isset($idsByPage[$targetPage])) {
                continue; // Fichier hors reading room : le test précédent s'en charge.
            }

            if (! in_array($anchor, $idsByPage[$targetPage], true)) {
                $dangling[] = "{$page} → {$target}";
            }
        }
    }

    expect($dangling)
        ->toBe([], sprintf(
            "%d renvoi(s) de la reading room vise(nt) une ancre qui n'existe pas :\n  - %s\n\n"
                . "Un lien vers une ancre absente n'échoue pas : il atterrit en haut de la page "
                . 'cible, sans le dire. Le lecteur en conclut qu\'il a mal cherché.',
            count($dangling),
            implode("\n  - ", $dangling),
        ));
});
