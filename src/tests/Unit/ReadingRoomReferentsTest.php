<?php

declare(strict_types=1);

use Tests\Support\RepoFile;

/**
 * Garde-fou sur les référents de la reading room.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CE TEST EXISTE
 *
 * `docs/reading-room/index.html` est une page écrite À LA MAIN qui décrit le
 * projet, son avancée, ses risques et ses décisions. Elle n'a AUCUNE autorité —
 * la hiérarchie du projet reste ADR > epics.md + sprint-status.yaml > ETAT.md,
 * et cette page se range dessous. Elle le dit sur elle-même, en tête.
 *
 * Une page écrite à la main dérive. C'est acquis, et ce test ne prétend pas
 * l'empêcher. Ce qu'il empêche est plus étroit et plus important : que la page
 * cite des fichiers qui n'existent pas.
 *
 * C'est exactement le motif dominant du dépôt — « l'affirmation précède son
 * référent » — dont dix-huit instances ont été recensées. Un document qui
 * renvoie vers `docs/adr/ADR-0009-…` après un renommage n'affiche pas d'erreur :
 * il continue de se lire normalement, et sa fausseté ne se découvre qu'au clic,
 * par quelqu'un qui n'osera pas conclure que le document a tort.
 *
 * D'où la forme retenue pour la page : TOUTE citation de fichier y est un lien
 * relatif cliquable. Un seul mécanisme sert deux fins — le lecteur ouvre la
 * source, et ce test vérifie qu'elle est là.
 *
 * ⚠️ CE QUE CE TEST NE COUVRE PAS, et il faut le savoir avant de s'y fier :
 *
 *   1. Les NOMBRES. « 224 tests », « 12 stories », « 0/0/0 » ne sont vérifiés
 *      par rien ici et dériveront. La page les affiche donc avec leur
 *      provenance et une date de lecture, et répète qu'elle ne vaut pas preuve.
 *   2. Les chemins écrits en PROSE sans être des liens (`<span class="mono">`).
 *      Ils sont volontairement employés pour ce qui n'est pas un fichier du
 *      dépôt (`_bmad-output/` est gitignoré) ou pour des chemins illustratifs.
 *      Un chemin réel qu'on veut voir gardé doit être écrit comme un LIEN.
 *   3. Les ANCRES (`#risks`) et les URL absolues : hors périmètre, la page
 *      n'en porte pas vers l'extérieur (elle s'ouvre hors ligne).
 *
 * ⚠️ Les TROIS assertions ont été OBSERVÉES ROUGES avant d'être déclarées
 * opérantes (2026-08-20) : la première en injectant un lien vers un fichier
 * absent, la deuxième en cassant l'extraction, la troisième en posant un ADR
 * sur disque sans le citer. Aucune n'est écrite après coup sur du vert.
 *
 * ⚠️ Et une MUTATION A SURVÉCU au premier jet (M3) : dé-baliser 25 liens d'un
 * coup laissait la page au-dessus d'un plancher fixé à 20, donc verte. Le
 * plancher est passé à 30 et la troisième assertion a été ajoutée. La campagne
 * a été REJOUÉE intégralement après ce correctif — règle de la boucle qualité
 * depuis la Story 1.10a.
 *
 * @see docs/reading-room/index.html
 * @see src/tests/Unit/BoostGuidelinesTest.php  (même forme, même motif)
 */
const READING_ROOM = 'docs/reading-room/index.html';

/**
 * Les cibles de liens relatifs de la page, dans l'ordre du document.
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
    // fait SURVIVRE la mutation M3 au premier jet — renommer les 47 attributs
    // `href` en `data-href` laissait les 33 cibles distinctes intactes aux yeux
    // du test. Le défaut était dans le garde-fou, pas dans la page.
    preg_match_all('/(?<![\w-])href="([^"]+)"/', $html, $matches);

    /** @var list<string> $targets */
    $targets = array_values(array_unique(array_filter(
        $matches[1],
        // Le motif `[^"]+` garantit déjà le non-vide : ne reste à écarter que
        // les ancres internes et tout ce qui porte un schéma (http:, mailto:).
        static fn (string $href): bool => ! str_starts_with($href, '#')
            && ! preg_match('#^[a-z][a-z0-9+.-]*:#i', $href),
    )));

    return $targets;
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
    $html = RepoFile::read(READING_ROOM);
    $base = dirname(RepoFile::root() . '/' . READING_ROOM);

    $unresolved = [];

    foreach (readingRoomLinkTargets($html) as $target) {
        $path = resolveRelative($base, $target);

        if (! file_exists($path)) {
            $unresolved[] = "{$target}  (cherché : {$path})";
        }
    }

    expect($unresolved)
        ->toBe([], sprintf(
            "La reading room cite %d fichier(s) qui n'existe(nt) pas :\n  - %s\n\n"
                . 'Un document qui renvoie vers un chemin absent est une affirmation sans '
                . "référent — le motif dominant de ce dépôt. Deux issues, pas trois : "
                . 'corriger le lien, ou retirer la phrase qui en dépend. Ne pas transformer '
                . 'le lien en texte brut pour faire taire ce test : la phrase resterait fausse, '
                . 'sans plus rien pour le dire.',
            count($unresolved),
            implode("\n  - ", $unresolved),
        ));
});

it('vérifie effectivement quelque chose — la page cite des dizaines de fichiers', function (): void {
    $targets = readingRoomLinkTargets(RepoFile::read(READING_ROOM));

    // Anti-vacuité. Sans ce contrôle, casser l'extraction (une regex qui ne
    // matche plus, une page réécrite sans liens) rendrait l'assertion
    // précédente VERTE en n'ayant rien vérifié — la forme la plus pure du
    // garde-fou silencieux, dans le test censé le traquer.
    //
    // ⚠️ Le seuil a été relevé de 20 à 30 après une MUTATION SURVIVANTE
    // (M3, 2026-08-20) : dé-baliser 25 liens d'un coup laissait la page à 20
    // référents, donc au-dessus du plancher, donc VERTE. Un plancher très
    // au-dessous du contenu réel n'attrape que l'effondrement total, jamais
    // l'érosion — et l'érosion est le mode de défaut d'un document.
    expect(count($targets))
        ->toBeGreaterThanOrEqual(30, sprintf(
            'Seulement %d lien(s) de fichier détecté(s) dans %s. Soit la page a perdu '
                . "ses référents, soit l'extraction est cassée — dans les deux cas "
                . "l'assertion de résolution ci-dessus ne garde plus rien.",
            count($targets),
            READING_ROOM,
        ));
});

it('cite TOUS les ADR du dépôt, parce que sa table se présente comme exhaustive', function (): void {
    // Ce test ne compare pas la page à elle-même : le côté « attendu » est le
    // DISQUE (`docs/adr/ADR-*.md`), le côté « constaté » est la page. C'est la
    // leçon de la mutation survivante MF-D de la Story 1.9 — un composant et
    // son test qui dérivent tous deux de la même table ne gardent rien.
    //
    // Il rougit donc dans le seul cas qui compte : un ADR ajouté au dépôt et
    // absent d'une table qui annonce les recenser tous. La page a le droit de
    // ne pas être exhaustive — mais alors elle doit cesser de le prétendre,
    // et ce test doit partir avec la prétention.
    $cited = array_map(
        static fn (string $href): string => basename($href),
        array_filter(
            readingRoomLinkTargets(RepoFile::read(READING_ROOM)),
            static fn (string $href): bool => str_contains($href, '/adr/ADR-'),
        ),
    );

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
            "La table « Les treize ADR » de la reading room n'est plus exhaustive : "
                . "%d ADR sur disque, %d cités. Manquant(s) : %s.",
            count($onDisk),
            count(array_unique($cited)),
            implode(', ', array_diff($onDisk, $cited)) ?: '—',
        ));
});
