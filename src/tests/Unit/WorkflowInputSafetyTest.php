<?php

declare(strict_types=1);

use Tests\Support\RepoFile;
use Tests\Support\ShellProbe;

/*
|------------------------------------------------------------------------------
| Injection de script dans les workflows — Story 2.4, revue 2
|------------------------------------------------------------------------------
|
| 🔴 CE GARDE EXISTE PARCE QUE LE MÊME DÉFAUT A ÉTÉ CORRIGÉ DEUX FOIS SUR TROIS.
|
| `${{ github.event.… }}` interpolé DANS un corps de `run:` est substitué par le
| moteur de workflow AVANT que le shell ne voie la ligne : la valeur devient du
| CODE. La revue 1 avait relevé le cas de `window_limit_seconds` ; deux des trois
| sites ont été corrigés, et le troisième — un step en `if: always()`, donc rendu
| MÊME QUAND LA VALIDATION D'ENTRÉE A DÉJÀ ÉCHOUÉ — est passé au travers.
|
| ⚖️ Le remède est toujours le même : passer par `env:`, où la valeur est une
| variable d'environnement que le shell traite comme une DONNÉE.
|
| ⛔ ET LE GARDE PORTE SUR TOUS LES WORKFLOWS, PAS SUR UNE LISTE ÉNUMÉRÉE :
| c'est la leçon de `COMPOSITE_INSTALL_TARGETS` (story 2.3) — une énumération ne
| peut pas garder ce qu'elle ne connaît pas. Le répertoire est balayé.
|
*/

/**
 * Corps de `run:` d'un workflow, indexés par « job → step ».
 *
 * @return array<string, string>
 */
function workflowRunBodies(string $relative): array
{
    $document = RepoFile::yaml($relative);
    $jobs = $document['jobs'] ?? null;

    if (! is_array($jobs)) {
        return [];
    }

    $bodies = [];

    foreach ($jobs as $jobName => $job) {
        $steps = is_array($job) ? ($job['steps'] ?? null) : null;

        if (! is_array($steps)) {
            continue;
        }

        foreach ($steps as $index => $step) {
            $run = is_array($step) ? ($step['run'] ?? null) : null;

            if (is_string($run)) {
                $label = is_array($step) && is_string($step['name'] ?? null)
                    ? $step['name']
                    : ('step #' . (is_int($index) ? $index : 0));
                $bodies[(string) $jobName . ' → ' . $label] = $run;
            }
        }
    }

    return $bodies;
}

/**
 * @return array<int, string>
 */
function workflowFiles(): array
{
    // ⛔ LES DEUX EXTENSIONS. GitHub accepte `.yaml` autant que `.yml` : ne
    // globber que `.yml` laissait un workflow entier échapper à TOUS les gardes
    // de ce fichier — et aux `paths:` de `ci.yml`, donc sans même un run pour
    // le dire (relevé en 2ᵉ revue).
    $files = array_merge(
        glob(RepoFile::root() . '/.github/workflows/*.yml') ?: [],
        glob(RepoFile::root() . '/.github/workflows/*.yaml') ?: [],
    );

    sort($files);

    return array_map(
        static fn (string $path): string => '.github/workflows/' . basename($path),
        $files,
    );
}

it('aucun workflow `.yaml` n’échappe aux `paths:` de la CI', function (): void {
    /*
     * ⚖️ CE GARDE EST UN AIGUILLAGE, PAS UN INTERDIT. `workflowFiles()` balaye
     * désormais les deux extensions, donc un `.yaml` serait bien inspecté ici.
     * Mais les `paths:` de `ci.yml` énumèrent des FICHIERS (`ci.yml`,
     * `nightly.yml`) : un workflow `.yaml` ne déclencherait aucun run, et ce
     * fichier-ci ne serait jamais rejoué sur sa modification. Tant qu'il n'en
     * existe aucun, le dire suffit ; le jour où quelqu'un en ajoute un, ce test
     * rougit et NOMME le geste à faire.
     */
    $yaml = glob(RepoFile::root() . '/.github/workflows/*.yaml') ?: [];

    expect(array_map('basename', $yaml))
        ->toBe([], 'Workflow en `.yaml` : ajoutez-le aux `paths:` de ci.yml, sinon ses gardes ne sont jamais rejoués.');

    // Anti-vacuité : il y a bien des workflows, et ils sont en `.yml`.
    expect(count(workflowFiles()))
        ->toBeGreaterThanOrEqual(4);
});

it('balaye TOUS les workflows du dépôt, pas une liste écrite à la main', function (): void {
    // Anti-vacuité : sans workflow trouvé, tout le fichier serait vert pour la
    // pire des raisons.
    expect(workflowFiles())
        ->toContain('.github/workflows/ci.yml')
        ->toContain('.github/workflows/nightly.yml');
    expect(count(workflowFiles()))
        ->toBeGreaterThanOrEqual(4);
});

it('trouve bien des corps de `run:` à inspecter', function (): void {
    // Second anti-vacuité : si l'extraction rendait toujours un tableau vide,
    // le garde ci-dessous ne garderait rien.
    $total = 0;

    foreach (workflowFiles() as $file) {
        $total += count(workflowRunBodies($file));
    }

    expect($total)
        ->toBeGreaterThan(20);
});

it('n’interpole JAMAIS une donnée d’évènement dans un corps de `run:`', function (): void {
    $offenders = [];

    foreach (workflowFiles() as $file) {
        foreach (workflowRunBodies($file) as $where => $body) {
            // `github.event.` couvre les entrées de `workflow_dispatch`, mais
            // aussi les titres de PR, noms de branche et corps de commit —
            // toute la famille « donnée contrôlée par un tiers ».
            if (preg_match('/\$\{\{\s*github\.event\./', $body) === 1) {
                $offenders[] = $file . ' :: ' . $where;
            }
        }
    }

    expect($offenders)
        ->toBe([]);
});

/*
|------------------------------------------------------------------------------
| Le job d'alerte du nightly — Story 2.4, revue 2
|------------------------------------------------------------------------------
|
| 🔴 IL ÉTAIT MORT À SON PREMIER APPEL, ET RIEN NE POUVAIT LE DIRE.
| `gh issue list --json number --jq '.[0].number'` imprime le LITTÉRAL « null »
| sur un ensemble vide : `[ -n "null" ]` est VRAI, donc `gh issue comment null`
| échouait — sous `bash -e`, le job s'arrêtait là et l'issue n'était JAMAIS
| créée. Le mécanisme même censé rendre un nightly rouge visible ne se
| déclenchait pas la première fois, c'est-à-dire toujours.
|
| ⚖️ Ces assertions gardent une FORMULATION de shell, et c'est dit : le job ne
| peut pas être exécuté ici (il lui faut l'API GitHub). C'est le même arbitrage
| que pour le gabarit de route du module 10 — un garde sur un texte vaut mieux
| qu'aucun garde sur un chemin que personne ne rejoue.
|
*/

it('ne lit JAMAIS un premier élément `--jq` sans `// empty`', function (): void {
    /*
     * 🔴 LE DÉFAUT GARDÉ : `--jq '.[0].number'` imprime le LITTÉRAL « null » sur
     * un ensemble vide. `[ -n "null" ]` est VRAI, donc `gh issue comment null`
     * échouait — et sous `bash -e` le job mourait à son PREMIER appel.
     *
     * ⛔ ET LE BALAYAGE PORTE SUR TOUS LES WORKFLOWS, plus sur `nightly.yml`
     * seul. Ce n'est pas un élargissement de confort : la déduplication d'issue
     * a quitté `--jq` pour du `python3` exécutable, si bien que `nightly.yml`
     * n'a plus de lecture de ce genre. Un garde dont le seul sujet a déménagé
     * doit suivre le sujet — pas être détendu, ni rester braqué sur un fichier
     * qui ne le concerne plus. `ci.yml` en porte deux (`nightly-freshness`).
     */
    $lectures = [];

    foreach (workflowFiles() as $file) {
        $corps = implode("\n", workflowRunBodies($file));

        preg_match_all('/--jq\s+\'([^\']*)\'/', $corps, $matches);

        foreach ($matches[1] as $expression) {
            // Toute forme d'extraction d'un PREMIER élément, quelle que soit sa
            // rédaction — la version précédente cherchait la sous-chaîne
            // `.[0].`, c'est-à-dire exactement la forme alors en place.
            if (preg_match('/\[0\]|\bfirst\b/', $expression) === 1) {
                $lectures[] = $file . ' :: ' . $expression;
            }
        }
    }

    // Anti-vacuité : il y a bien au moins une lecture de ce genre à garder,
    // quelque part dans le dépôt.
    expect($lectures)
        ->not->toBe([]);

    foreach ($lectures as $lecture) {
        expect($lecture)
            ->toContain('// empty');
    }
});

it('la déduplication d’issue ne repose plus sur un filtre que rien ne peut exécuter', function (): void {
    /*
     * ⚖️ CE TEST DIT CE QUI A CHANGÉ, ET POURQUOI. La comparaison de titre
     * vivait dans un programme `jq` : aucun test ne pouvait l'exécuter (ni le
     * conteneur `laravel-app_php` ni l'hôte n'ont `jq`, mesuré le 2026-08-24 —
     * seule la CLI `gh` l'embarque), donc les gardes n'en relisaient que le
     * TEXTE. Démontré : `env.ISSUE_TITLE` remplacé par `"$ISSUE_TITLE"` —
     * comparaison qui ne peut jamais matcher — laissait tout vert.
     *
     * ⛔ Le titre reste une DONNÉE lue dans l'ENVIRONNEMENT, jamais interpolée
     * dans le programme qui compare : c'est l'invariant, et il survit au
     * changement d'outil.
     */
    $etape = corpsEtapeAlerte();

    expect($etape)
        ->toContain('python3');
    expect($etape)
        ->toContain('os.environ["ISSUE_TITLE"]');

    // ⛔ ET SURTOUT PAS L'INVERSE : une interpolation shell du titre DANS le
    // programme de comparaison est précisément la mutation démontrée.
    expect($etape)
        ->not->toContain('== "$ISSUE_TITLE"');
    expect($etape)
        ->not->toContain("== '\$ISSUE_TITLE'");
});

/*
|------------------------------------------------------------------------------
| Résolution du dépôt pour `gh` — Story 2.4 (clôture)
|------------------------------------------------------------------------------
|
| 🔴 LE JOB D'ALERTE ÉTAIT MORT À SON PREMIER APPEL, POUR LA SECONDE FOIS, ET
| PAR UNE AUTRE CAUSE. La revue 2 avait corrigé le `null` littéral ; restait que
| ce job n'a AUCUN `actions/checkout`. Le répertoire de travail d'un runner nu
| n'est pas un dépôt git : `gh issue list` y sort sur « fatal: not a git
| repository » (mesuré le 2026-08-24, hôte WSL2, `gh` 2.x, dans un répertoire
| non-git — et `GH_REPO=<owner>/<repo>` la fait sortir en 0). Les deux nightlies
| rouges des 22 et 23/08 n'ont donc ouvert AUCUNE issue, et le label `nightly`
| n'existait toujours pas sur le dépôt.
|
| ⚖️ LE GARDE PORTE SUR LES SOUS-COMMANDES QUI ONT BESOIN D'UN DÉPÔT, pas sur
| « le mot gh ». `gh api repos/<owner>/<repo>/…` porte le dépôt DANS son chemin
| et n'a besoin de rien : c'est le cas de `nightly-freshness` dans `ci.yml`, qui
| est correct. Un garde qui le déclarerait fautif serait détendu le lendemain.
|
*/

it('tout appel `gh`, SANS EXCEPTION, porte de quoi s’AUTHENTIFIER', function (): void {
    /*
     * 🔴 LE TROU JUMEAU DE CELUI QU'ON VIENT DE FERMER (2ᵉ revue). Le garde
     * voisin vérifie que `gh` sait quel DÉPÔT viser ; personne ne vérifiait
     * qu'il sait QUI IL EST. Or « mort au premier appel » a deux causes, et
     * l'authentification est la seconde : GitHub Actions n'injecte PAS
     * `GH_TOKEN` tout seul, un step `gh issue …` sans lui passe ce garde-ci et
     * meurt en production exactement comme le job d'alerte a mis deux nuits à
     * révéler qu'il mourait.
     *
     * ⛔ ET CE GARDE PORTE SUR **TOUT** `gh`, `gh api` COMPRIS — contrairement à
     * celui du dépôt, qui ne concerne que les sous-commandes ayant besoin d'un
     * contexte de dépôt. `gh api repos/<o>/<r>/…` porte son dépôt dans son
     * chemin, mais il lui faut un jeton comme aux autres.
     */
    $offenders = [];
    $gardes = 0;

    foreach (workflowFiles() as $file) {
        $document = RepoFile::yaml($file);
        $workflowEnv = is_array($document['env'] ?? null) ? $document['env'] : [];
        $jobs = $document['jobs'] ?? null;

        if (! is_array($jobs)) {
            continue;
        }

        foreach ($jobs as $jobName => $job) {
            $steps = is_array($job) ? ($job['steps'] ?? null) : null;

            if (! is_array($steps)) {
                continue;
            }

            $jobEnv = is_array($job) && is_array($job['env'] ?? null) ? $job['env'] : [];
            $jobEnv = array_merge($workflowEnv, $jobEnv);

            foreach ($steps as $step) {
                if (! is_array($step)) {
                    continue;
                }

                $run = is_string($step['run'] ?? null) ? $step['run'] : '';

                if ($run === '') {
                    continue;
                }

                foreach (explode("\n", $run) as $ligne) {
                    if (str_starts_with(ltrim($ligne), '#')) {
                        continue;
                    }

                    if (preg_match('/(^|[^\w-])gh\s+[a-z]/', $ligne) !== 1) {
                        continue;
                    }

                    $gardes++;

                    $stepEnv = is_array($step['env'] ?? null) ? $step['env'] : [];
                    $env = array_merge($jobEnv, $stepEnv);

                    // `GH_TOKEN` est ce que lit la CLI ; `GITHUB_TOKEN` est
                    // accepté par `gh` en repli et employé par beaucoup de
                    // workflows. L'un ou l'autre, non vide.
                    $jeton = null;

                    foreach (['GH_TOKEN', 'GITHUB_TOKEN'] as $nom) {
                        $valeur = $env[$nom] ?? null;

                        if (is_string($valeur) && trim($valeur) !== '') {
                            $jeton = $valeur;
                        }
                    }

                    if ($jeton === null) {
                        $offenders[] = $file . ' :: ' . $jobName . ' :: ' . trim($ligne);
                    }
                }
            }
        }
    }

    // Anti-vacuité : le balayage a bien trouvé des appels `gh`. Sans ce compte,
    // un garde vert prouverait seulement que la détection ne détecte rien.
    expect($gardes)
        ->toBeGreaterThanOrEqual(5);

    expect($offenders)
        ->toBe([], 'Appel `gh` sans jeton : il mourra sur « gh: To use GitHub CLI in a GitHub Actions workflow, set the GH_TOKEN environment variable ».');
});

it('tout job qui invoque une commande `gh` liée au dépôt sait le résoudre', function (): void {
    // Sous-commandes qui exigent un contexte de dépôt (`gh` le déduit sinon du
    // remote git du répertoire courant).
    $sousCommandes = ['issue', 'pr', 'label', 'release', 'run', 'workflow', 'browse', 'repo'];

    $offenders = [];
    $gardes = 0;

    foreach (workflowFiles() as $file) {
        $document = RepoFile::yaml($file);
        $workflowEnv = is_array($document['env'] ?? null) ? $document['env'] : [];
        $jobs = $document['jobs'] ?? null;

        if (! is_array($jobs)) {
            continue;
        }

        foreach ($jobs as $jobName => $job) {
            $steps = is_array($job) ? ($job['steps'] ?? null) : null;

            if (! is_array($steps)) {
                continue;
            }

            /*
             * 🔴 DEUX TROUS, RELEVÉS EN AUDIT.
             * (a) L'`env` du WORKFLOW n'était pas fusionné : un `GH_REPO`
             *     déclaré au niveau du fichier faisait accuser un workflow
             *     parfaitement correct — et le réflexe aurait été de détendre le
             *     garde, pas de le corriger.
             * (b) Un `actions/checkout` placé APRÈS l'appel `gh`, ou porteur
             *     d'un `if:` faux, satisfaisait la garde alors que `gh` tourne
             *     hors dépôt. On compare donc les INDICES d'étapes, et un
             *     checkout conditionnel ne compte pas.
             */
            $jobEnv = is_array($job) && is_array($job['env'] ?? null) ? $job['env'] : [];
            $jobEnv = array_merge($workflowEnv, $jobEnv);
            $rangCheckout = null;
            $sitesGh = [];

            foreach ($steps as $rang => $step) {
                if (! is_array($step)) {
                    continue;
                }

                $uses = is_string($step['uses'] ?? null) ? $step['uses'] : '';

                if (str_starts_with($uses, 'actions/checkout') && ! array_key_exists('if', $step)) {
                    $rangCheckout ??= (int) $rang;
                }

                $run = is_string($step['run'] ?? null) ? $step['run'] : '';

                if ($run === '') {
                    continue;
                }

                foreach (explode("\n", $run) as $ligne) {
                    // Les COMMENTAIRES citent les commandes fautives : ce
                    // fichier-ci en est la preuve vivante.
                    if (str_starts_with(ltrim($ligne), '#')) {
                        continue;
                    }

                    foreach ($sousCommandes as $sousCommande) {
                        if (preg_match('/(^|[^\w-])gh\s+' . $sousCommande . '\b/', $ligne) === 1) {
                            $stepEnv = is_array($step['env'] ?? null) ? $step['env'] : [];
                            $sitesGh[] = [
                                'ligne' => trim($ligne),
                                'env' => array_merge($jobEnv, $stepEnv),
                                'rang' => (int) $rang,
                            ];

                            break;
                        }
                    }
                }
            }

            foreach ($sitesGh as $site) {
                $gardes++;

                // ⛔ PRÉSENCE **ET** UTILITÉ (2ᵉ revue). `array_key_exists`
                // acceptait `GH_REPO: ${{ env.INEXISTANT }}`, c'est-à-dire une
                // chaîne VIDE : le garde attestait d'une déclaration, pas d'une
                // résolution.
                $repo = $site['env']['GH_REPO'] ?? null;

                if (is_string($repo) && trim($repo) !== '') {
                    continue;
                }

                // Le checkout ne résout le dépôt que s'il a DÉJÀ eu lieu.
                if ($rangCheckout !== null && $rangCheckout < $site['rang']) {
                    continue;
                }

                $offenders[] = $file . ' :: ' . $jobName . ' :: ' . $site['ligne'];
            }
        }
    }

    // Anti-vacuité : le balayage a bien trouvé des appels `gh` à garder. Sans
    // cela, un garde vert prouverait seulement que la détection ne détecte rien.
    expect($gardes)
        ->toBeGreaterThanOrEqual(3);

    expect($offenders)
        ->toBe([]);
});

/*
|------------------------------------------------------------------------------
| L'alerte doit rester ÉPROUVABLE — Story 2.4 (clôture), constat d'audit
|------------------------------------------------------------------------------
|
| 🔴 CE QUI S'EST RÉELLEMENT PASSÉ, ET QUE RIEN N'EMPÊCHAIT DE RECOMMENCER.
| Le job `alert` a été livré par la story 2.4 avec `if: … && github.event_name ==
| 'schedule'`. Deux nightlies ont rougi — runs 32654512271 et 32688766596 — et
| **aucun des deux n'a ouvert la moindre issue** ; le label `nightly` n'existait
| toujours pas sur le dépôt. La cause (pas de `GH_REPO`, donc « fatal: not a git
| repository ») est corrigée ailleurs dans ce fichier. Mais elle avait pu vivre
| DEUX NUITS parce que **personne ne pouvait éprouver ce job sans attendre
| 03:17** : un `Run workflow` ne le déclenchait pas.
|
| ⛔ LE RETRAIT DE CETTE RESTRICTION N'ÉTAIT VERROUILLÉ PAR RIEN. Le remettre —
| ou le réintroduire au fil d'une réécriture du workflow — ne faisait rougir
| aucun test, et on retombait dans un correctif d'alerte invalidable autrement
| qu'en perdant une nuit. C'est le motif du garde-fou silencieux, appliqué au
| correctif qui vient d'être fait.
|
| ⚖️ LE GARDE PORTE SUR L'INTENTION, PAS SUR LE TEXTE DE LA CONDITION.
| Recopier `github.event_name == 'schedule' || github.event_name ==
| 'workflow_dispatch'` en aurait fait une PHOTOGRAPHIE : toute reformulation
| équivalente l'aurait fait rougir à tort, et surtout il n'aurait rien dit de ce
| qui compte. La question posée ici est celle qu'un humain se pose :
| **« si je lance ce workflow à la main et que l'installation échoue, l'alerte
| part-elle ? »** On ÉVALUE donc la condition, pour un contexte donné, au lieu
| de la comparer à une chaîne.
|
| ⚠️ ET L'ÉVALUATEUR REFUSE CE QU'IL NE SAIT PAS LIRE. Une syntaxe hors de sa
| grammaire lève une exception au lieu de rendre `true` : « je ne sais pas
| prouver l'intention » doit faire ÉCHOUER le test, jamais le laisser vert.
|
*/

/**
 * Découpe une condition `if:` de workflow en jetons.
 *
 * @return list<string>
 */
function jetonsCondition(string $expression): array
{
    $jetons = [];
    $offset = 0;
    $longueur = strlen($expression);

    while ($offset < $longueur) {
        if (preg_match('/\s+/A', $expression, $blanc, 0, $offset) === 1) {
            $offset += strlen($blanc[0]);

            continue;
        }

        /*
         * ⚠️ LE TIRET EST DANS LA CLASSE, ET CE N'EST PAS UN RELÂCHEMENT DE
         * CONFORT. Un identifiant de job GitHub peut porter un tiret, et
         * `needs.nightly-freshness.result` est précisément l'expression que la
         * condition d'échec du résumé référence depuis la bascule du
         * 2026-08-24. Sans lui, `jetonsCondition()` levait « jeton inattendu »
         * et le garde du verdict global n'aurait jamais pu être écrit.
         *
         * ⛔ CE QUI BORNE LE RELÂCHEMENT : le test « l'évaluateur REFUSE ce
         * qu'il ne sait pas lire ». Un identifiant bien formé mais absent du
         * contexte lève toujours — c'est le tiret qui entre dans la grammaire,
         * pas la tolérance.
         */
        $motif = '/(\|\||&&|==|!=|!|\(|\)|\'[^\']*\'|[A-Za-z_][A-Za-z0-9_.-]*(?:\(\))?)/A';

        if (preg_match($motif, $expression, $jeton, 0, $offset) === 1) {
            $jetons[] = $jeton[0];
            $offset += strlen($jeton[0]);

            continue;
        }

        throw new RuntimeException(
            "Condition non évaluable (jeton inattendu à l’offset {$offset}) : « {$expression} ».",
        );
    }

    return $jetons;
}

/**
 * Évalue une condition `if:` de workflow dans un CONTEXTE donné.
 *
 * Grammaire volontairement étroite — littéraux, `github.*`, `needs.*.result`,
 * `always()`/`success()`/`failure()`/`cancelled()`, `==`, `!=`, `&&`, `||`,
 * `!`, parenthèses. Tout le reste lève, plutôt que de rendre un verdict que
 * l'évaluateur n'a pas les moyens de rendre.
 *
 * @param  array<string, string|null>  $contexte
 */
function conditionEstVraie(string $expression, array $contexte): bool
{
    $jetons = jetonsCondition($expression);
    $curseur = 0;

    $valeurDe = static function (string $jeton) use ($contexte): bool|string {
        if (str_starts_with($jeton, "'")) {
            return trim($jeton, "'");
        }

        if ($jeton === 'true') {
            return true;
        }

        if ($jeton === 'false') {
            return false;
        }

        /*
         * ⛔ `null` EST UNE VALEUR, ET GITHUB LA COERCE VERS LA CHAÎNE VIDE.
         * Une entrée de `workflow_dispatch` non fournie — le cas d'un run
         * `schedule` — vaut `null` chez GitHub, pas `''` ; et `null == ''` y est
         * VRAI. Le contexte de sonde fournissait toujours `''`, donc il ne
         * modélisait pas le cas réel : l'égalité tenait par coïncidence de
         * fixture. On modélise la coercition plutôt que de la supposer.
         */
        if ($jeton === 'null') {
            return '';
        }

        if (array_key_exists($jeton, $contexte)) {
            // ⛔ `null` DU CONTEXTE = ABSENCE, ET GITHUB LA COERCE VERS `''`.
            // C'est ce qui rend `github.event.inputs.X == ''` vrai sur un run
            // `schedule`, où l'entrée n'est pas fournie.
            return $contexte[$jeton] ?? '';
        }

        throw new RuntimeException(
            "Condition non évaluable : « {$jeton} » n’est ni un littéral ni une clé du contexte de sonde.",
        );
    };

    $ou = static function () use (&$ou, &$jetons, &$curseur, $valeurDe): bool|string {
        $et = static function () use (&$ou, &$jetons, &$curseur, $valeurDe): bool|string {
            $unaire = static function () use (&$ou, &$unaire, &$jetons, &$curseur, $valeurDe): bool|string {
                $jeton = $jetons[$curseur] ?? null;

                if ($jeton === null) {
                    throw new RuntimeException('Condition non évaluable : expression tronquée.');
                }

                if ($jeton === '!') {
                    $curseur++;

                    return ! estVrai($unaire());
                }

                if ($jeton === '(') {
                    $curseur++;
                    $valeur = $ou();

                    if (($jetons[$curseur] ?? null) !== ')') {
                        throw new RuntimeException('Condition non évaluable : parenthèse non refermée.');
                    }

                    $curseur++;

                    return $valeur;
                }

                $curseur++;
                $gauche = $valeurDe($jeton);

                $operateur = $jetons[$curseur] ?? null;

                if ($operateur === '==' || $operateur === '!=') {
                    $curseur++;
                    $droite = $valeurDe($jetons[$curseur] ?? '');
                    $curseur++;

                    return $operateur === '==' ? $gauche === $droite : $gauche !== $droite;
                }

                return $gauche;
            };

            $valeur = $unaire();

            while (($jetons[$curseur] ?? null) === '&&') {
                $curseur++;
                // ⛔ LE MEMBRE DROIT EST ÉVALUÉ AVANT D'ÊTRE COMBINÉ, ET C'EST
                // UN CORRECTIF. `estVrai($valeur) && estVrai($unaire())` laisse
                // PHP court-circuiter : sur un membre gauche faux, `$unaire()`
                // n'est jamais appelé, le curseur n'avance pas, et l'expression
                // meurt en « jetons résiduels ». Un analyseur doit CONSOMMER ce
                // qu'il lit, que le résultat soit déjà décidé ou non.
                $droite = estVrai($unaire());
                $valeur = estVrai($valeur) && $droite;
            }

            return $valeur;
        };

        $valeur = $et();

        while (($jetons[$curseur] ?? null) === '||') {
            $curseur++;
            // Même raison qu'au-dessus : on consomme, puis on combine.
            $droite = estVrai($et());
            $valeur = estVrai($valeur) || $droite;
        }

        return $valeur;
    };

    $resultat = $ou();

    if ($curseur !== count($jetons)) {
        throw new RuntimeException('Condition non évaluable : jetons résiduels après l’expression.');
    }

    return estVrai($resultat);
}

/**
 * Vérité d'une valeur de condition, à la manière du moteur de workflow.
 */
function estVrai(bool|string $valeur): bool
{
    return is_bool($valeur) ? $valeur : ($valeur !== '' && $valeur !== 'false');
}

/**
 * Contexte de sonde pour un évènement et un verdict d'installation donnés.
 *
 * `$mutation` vaut `null` pour modéliser une entrée NON FOURNIE — le cas d'un
 * run `schedule` chez GitHub, où elle n'est pas la chaîne vide mais `null`.
 *
 * @return array<string, string|null>
 */
function contexteNightly(string $evenement, string $resultatInstall, ?string $mutation = ''): array
{
    return [
        'github.event_name' => $evenement,
        'needs.install.result' => $resultatInstall,
        // Entrée du déclenchement manuel : un rouge VOLONTAIRE n'est pas une
        // panne, et la condition doit savoir les distinguer.
        // ⚠️ Sur un run `schedule`, GitHub rend `null` — pas `''`. Le contexte
        // le dit littéralement, et l'évaluateur applique la coercition.
        'github.event.inputs.mutate_module' => $mutation,
        'always()' => 'true',
        'success()' => $resultatInstall === 'success' ? 'true' : 'false',
        'failure()' => $resultatInstall === 'failure' ? 'true' : 'false',
        'cancelled()' => $resultatInstall === 'cancelled' ? 'true' : 'false',
    ];
}

/**
 * La condition `if:` du job `alert` du nightly, lue sur disque.
 */
function conditionAlerteNightly(): string
{
    $document = RepoFile::yaml('.github/workflows/nightly.yml');
    $jobs = $document['jobs'] ?? null;
    $alerte = is_array($jobs) ? ($jobs['alert'] ?? null) : null;

    expect(is_array($alerte))
        ->toBeTrue('Le job `alert` du nightly a disparu : plus rien ne signale un nightly rouge.');

    /** @var array<string, mixed> $alerte */
    $condition = $alerte['if'] ?? null;

    // Pas de `if:` du tout = le job tourne toujours : l'intention est
    // satisfaite, et l'expression neutre le dit sans cas particulier.
    return is_string($condition) ? $condition : 'true';
}

it('rend l’alerte du nightly ÉPROUVABLE sans attendre le cron', function (): void {
    // Anti-vacuité n°1 : le déclencheur manuel existe. Sans lui, la question
    // « l'alerte part-elle sur un dispatch ? » n'aurait aucun sens.
    $document = RepoFile::yaml('.github/workflows/nightly.yml');
    /** @var array<string, mixed> $declencheurs */
    $declencheurs = is_array($document['on'] ?? null)
        ? $document['on']
        : (is_array($document[1] ?? null) ? $document[1] : []);

    // ⚠️ `toContain` prend des AIGUILLES, pas un message : un second argument y
    // devient une seconde aiguille recherchée. Le message passe donc par
    // `toBeTrue`, qui, lui, en accepte un.
    expect(in_array('workflow_dispatch', array_keys($declencheurs), true))
        ->toBeTrue('Le nightly n’est plus déclenchable à la main.');

    $condition = conditionAlerteNightly();

    // ⛔ LA QUESTION, TELLE QU'UN HUMAIN SE LA POSE : je lance le workflow à la
    // main, l'installation échoue — l'alerte part-elle ?
    expect(conditionEstVraie($condition, contexteNightly('workflow_dispatch', 'failure')))
        ->toBeTrue(
            'Le job `alert` ne se déclenche pas sur un `Run workflow` : son correctif ne peut être '
            . 'éprouvé qu’en attendant 03:17. C’est ainsi que deux nightlies rouges (32654512271, '
            . '32688766596) n’ont ouvert AUCUNE issue sans que personne puisse le constater.',
        );
});

it('ne confond pas un run ANNULÉ ou SAUTÉ avec un échec', function (): void {
    /*
     * 🔴 `needs.install.result != 'success'` est VRAI pour `cancelled` et
     * `skipped` : annuler un run manuel ouvrait une issue « nightly rouge »
     * alors que RIEN n'avait échoué. Une issue qu'on apprend à ignorer est une
     * alerte désarmée — le mécanisme exact que ce job existe pour éviter.
     */
    $condition = conditionAlerteNightly();

    foreach (['cancelled', 'skipped'] as $verdict) {
        expect(conditionEstVraie($condition, contexteNightly('workflow_dispatch', $verdict)))
            ->toBeFalse("Un run « {$verdict} » ouvre une issue de nightly rouge.");
    }
});

it('un run PLANIFIÉ, où l’entrée vaut `null`, déclenche bien l’alerte', function (): void {
    /*
     * 🔴 LE CONTEXTE DE SONDE MENTAIT UN PEU (2ᵉ revue) : il fournissait `''`
     * pour `mutate_module` même sur `schedule`, où GitHub rend en réalité
     * `null`. L'égalité `== ''` tenait donc par coïncidence de fixture. La
     * coercition `null == ''` est celle de GitHub, et elle est désormais
     * MODÉLISÉE — si la condition cessait de la tolérer, le nightly PLANIFIÉ,
     * le seul qui compte, n'ouvrirait plus aucune issue.
     */
    $condition = conditionAlerteNightly();

    expect(conditionEstVraie($condition, contexteNightly('schedule', 'failure', null)))
        ->toBeTrue('Un nightly PLANIFIÉ rouge n’ouvre plus d’issue : l’entrée absente y vaut `null`.');
});

it('ne dépose PAS d’issue sur un rouge VOLONTAIRE (`mutate_module`)', function (): void {
    /*
     * 🔴 UN ROUGE DEMANDÉ N'EST PAS UNE PANNE. Lancer le workflow avec
     * `mutate_module` est la PROCÉDURE DE VALIDATION écrite dans
     * `docs/ETAT.md` : ce run DOIT être rouge. Y déposer une vraie issue de
     * nightly rouge à chaque vérification du garde-fou, c'est fabriquer le bruit
     * qui fera ignorer les vraies.
     */
    $condition = conditionAlerteNightly();

    expect(conditionEstVraie($condition, contexteNightly('workflow_dispatch', 'failure', '20-database')))
        ->toBeFalse('Un rouge volontaire (mutate_module) dépose une issue de nightly rouge.');

    // …et sans mutation, le même run rouge la dépose bien : anti-vacuité.
    expect(conditionEstVraie($condition, contexteNightly('workflow_dispatch', 'failure')))
        ->toBeTrue();
});

it('le job d’alerte DÉPEND toujours du job qu’il commente', function (): void {
    /*
     * ⛔ SANS `needs: [install]`, LA CONDITION RÉFÉRENCE UN CONTEXTE ABSENT.
     * `needs.install.result` deviendrait vide, la condition serait fausse en
     * permanence, et les deux gardes ci-dessus resteraient VERTS — ils
     * évaluent la condition, pas le graphe de jobs qui la nourrit.
     */
    $document = RepoFile::yaml('.github/workflows/nightly.yml');
    $jobs = $document['jobs'] ?? null;
    $alerte = is_array($jobs) ? ($jobs['alert'] ?? null) : null;

    expect(is_array($alerte))
        ->toBeTrue('Le job `alert` a disparu.');

    /** @var array<string, mixed> $alerte */
    $needs = $alerte['needs'] ?? null;
    $needs = is_string($needs) ? [$needs] : $needs;

    // ⚠️ `toContain` prend des AIGUILLES, pas un message. Quatrième rencontre de
    // ce piège dans cette story : le message passe par `toBeTrue`.
    expect(in_array('install', is_array($needs) ? $needs : [], true))
        ->toBeTrue('Le job `alert` ne dépend plus d’`install` : sa condition lit un contexte inexistant.');

    // Et le job dont il dépend existe réellement.
    expect(array_keys(is_array($jobs) ? $jobs : []))
        ->toContain('install');
});

it('n’a pas rendu l’alerte bavarde pour autant', function (): void {
    /*
     * ⛔ ANTI-VACUITÉ N°2, ET C'EST ELLE QUI DONNE SA VALEUR AU TEST PRÉCÉDENT.
     * Un évaluateur qui rendrait `true` en toute circonstance — ou une condition
     * supprimée à la légère — satisferait le garde ci-dessus tout en ouvrant une
     * issue à CHAQUE run, y compris les verts. Les deux moitiés se tiennent :
     * l'alerte part quand l'installation échoue, et se tait quand elle réussit.
     */
    $condition = conditionAlerteNightly();

    foreach (['schedule', 'workflow_dispatch'] as $evenement) {
        expect(conditionEstVraie($condition, contexteNightly($evenement, 'success')))
            ->toBeFalse("Une installation RÉUSSIE déclenche l’alerte sur « {$evenement} ».");

        expect(conditionEstVraie($condition, contexteNightly($evenement, 'failure')))
            ->toBeTrue("Une installation en ÉCHEC ne déclenche PAS l’alerte sur « {$evenement} ».");
    }
});

it('l’évaluateur de conditions REFUSE ce qu’il ne sait pas lire', function (): void {
    // 🔴 Sans ce test, une syntaxe hors grammaire pourrait rendre un verdict par
    // défaut, et les deux gardes ci-dessus deviendraient verts en ne mesurant
    // rien. « Je ne sais pas prouver l'intention » doit faire ÉCHOUER.
    expect(static fn (): bool => conditionEstVraie(
        "contains(fromJSON('[]'), github.event_name)",
        contexteNightly('workflow_dispatch', 'failure'),
    ))->toThrow(RuntimeException::class);

    expect(static fn (): bool => conditionEstVraie(
        'github.event_name == ',
        contexteNightly('workflow_dispatch', 'failure'),
    ))->toThrow(RuntimeException::class);

    /*
     * 🔴 CE CAS-CI A ÉTÉ AJOUTÉ PAR LA CAMPAGNE DE MUTATION, ET IL FAUT LE DIRE.
     * La mutation « l'évaluateur rend `true` par défaut au lieu de refuser un
     * identifiant inconnu » est d'abord restée **VERTE** : les deux cas
     * ci-dessus mouraient tous les deux dans le DÉCOUPAGE (une virgule et une
     * expression tronquée), donc jamais dans la résolution d'identifiant. Le
     * refus que ce test prétendait garder n'était atteint par aucune assertion.
     * Voici une expression parfaitement bien formée dont le seul défaut est de
     * nommer un contexte que la sonde ne fournit pas — c'est le SEUL chemin qui
     * atteint ce refus-là.
     */
    expect(static fn (): bool => conditionEstVraie(
        "github.actor == 'quelquun'",
        contexteNightly('workflow_dispatch', 'failure'),
    ))->toThrow(RuntimeException::class);

    // …et il sait lire ce qu'il prétend lire : anti-vacuité de ce test-ci.
    expect(conditionEstVraie(
        "always() && needs.install.result != 'success' && (github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')",
        contexteNightly('workflow_dispatch', 'failure'),
    ))->toBeTrue();
    expect(conditionEstVraie(
        "github.event_name == 'schedule'",
        contexteNightly('workflow_dispatch', 'failure'),
    ))->toBeFalse();
});

/*
|------------------------------------------------------------------------------
| La déduplication d'issue, EXÉCUTÉE — clôture 2.4, constat d'audit
|------------------------------------------------------------------------------
|
| 🔴 ELLE N'ÉTAIT ASSERTÉE QUE COMME DU TEXTE, ET C'EST DÉMONTRÉ. Remplacer
| `env.ISSUE_TITLE` par `"$ISSUE_TITLE"` dans le filtre jq — une comparaison qui
| ne peut JAMAIS matcher, le programme jq étant en quotes simples — laissait 9/9
| verts. Cela réintroduisait exactement ce que le commentaire du workflow
| affirmait avoir corrigé : une issue neuve à chaque nuit rouge, indéfiniment.
|
| ⚖️ LA COMPARAISON A DONC QUITTÉ `--jq`. Non pour contourner le test, mais
| parce qu'aucun test ne POUVAIT l'exécuter : `jq` n'existe ni dans le conteneur
| `laravel-app_php` ni sur l'hôte (mesuré le 2026-08-24), et seule la CLI `gh`
| l'embarque. Le filtre est désormais un `python3` — la décision déjà écrite et
| justifiée dans `tests/bats/lib/e2e.bash` pour la même raison — ce qui rend
| l'étape exécutable sous un `gh` stubé.
|
| ⛔ CE QUI EST MESURÉ ICI, C'EST LE CHOIX FINAL : `gh issue comment <n>` contre
| `gh issue create`. Pas la forme du filtre.
|
*/

/**
 * Le corps du step d'alerte, tel que le workflow le porte.
 */
function corpsEtapeAlerte(): string
{
    $document = RepoFile::yaml('.github/workflows/nightly.yml');
    $jobs = $document['jobs'] ?? null;
    $alerte = is_array($jobs) ? ($jobs['alert'] ?? null) : null;
    $steps = is_array($alerte) ? ($alerte['steps'] ?? null) : null;
    $premier = is_array($steps) ? ($steps[0] ?? null) : null;
    $run = is_array($premier) && is_string($premier['run'] ?? null) ? $premier['run'] : null;

    expect($run)
        ->not->toBeNull('Le step d’alerte du nightly n’a plus de corps `run:`.');

    return (string) $run;
}

/**
 * Exécute le VRAI corps du step d'alerte contre un `gh` stubé.
 *
 * `$fixture` est ce que `gh issue list --json` rendra. Le journal du stub est
 * la mesure : c'est lui qui dit si l'étape a commenté ou créé.
 */
function sondeAlerteNightly(string $fixture): string
{
    $etape = corpsEtapeAlerte();

    return <<<BASH
        set -e
        bac="\$(mktemp -d)"
        case "\$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
        esac

        mkdir -p "\$bac/bin"
        printf '%s' {$fixture} > "\$bac/fixture"

        printf '%s\\n' \\
            '#!/bin/sh' \\
            'echo "\$*" >> "\$JOURNAL_GH"' \\
            'if [ "\$1" = "issue" ] && [ "\$2" = "list" ]; then cat "\$FIXTURE"; fi' \\
            'exit 0' \\
            > "\$bac/bin/gh"
        chmod +x "\$bac/bin/gh"

        JOURNAL_GH="\$bac/journal"; export JOURNAL_GH
        FIXTURE="\$bac/fixture"; export FIXTURE
        : > "\$JOURNAL_GH"

        PATH="\$bac/bin:\$PATH"; export PATH
        GH_TOKEN=jeton; export GH_TOKEN
        GH_REPO=proprietaire/depot; export GH_REPO
        RUN_URL=https://exemple.invalid/run/1; export RUN_URL
        ISSUE_TITLE='🌙 Nightly E2E rouge'; export ISSUE_TITLE

        cp "\$ETAPE" "\$bac/etape.sh"

        statut=0
        bash "\$bac/etape.sh" > "\$bac/sortie" 2>&1 || statut=\$?

        echo "STATUT=\$statut"
        echo "=== APPELS_GH ==="
        cat "\$JOURNAL_GH"
        echo "=== FIN ==="

        rm -rf "\$bac"
        BASH;
}

/**
 * Les appels `gh` journalisés par le stub.
 *
 * @return list<string>
 */
function appelsGh(string $sortie): array
{
    if (preg_match('/=== APPELS_GH ===\n(.*)=== FIN ===/s', $sortie, $bloc) !== 1) {
        throw new RuntimeException("Bloc APPELS_GH absent de la sortie de sonde :\n" . $sortie);
    }

    return array_values(array_filter(
        array_map('trim', explode("\n", $bloc[1])),
        static fn (string $ligne): bool => $ligne !== '',
    ));
}

/**
 * Écrit le corps du step dans un fichier, et rend l'environnement de sonde.
 *
 * @return array<string, string>
 */
function environnementSondeAlerte(): array
{
    // ⛔ MÊME DÉFAUT QUE LA SONDE DE FRAÎCHEUR, CORRIGÉ DU MÊME GESTE :
    // `tempnam()` crée un fichier, `. '.sh'` en désigne un autre, et seul le
    // second était supprimé. En laisser un corrigé à côté de son jumeau
    // défectueux est exactement le motif « trois sur cinq » que ce dépôt punit.
    $chemin = tempnam(sys_get_temp_dir(), 'alerte-');

    if ($chemin === false || file_put_contents($chemin, corpsEtapeAlerte()) === false) {
        throw new RuntimeException('Corps du step d’alerte non écrit dans la sonde.');
    }

    return [
        'ETAPE' => $chemin,
    ];
}

it('EXÉCUTÉE : une issue existante est COMMENTÉE, jamais dupliquée', function (): void {
    $env = environnementSondeAlerte();

    try {
        $result = ShellProbe::run(
            sondeAlerteNightly("'[{\"number\":42,\"title\":\"🌙 Nightly E2E rouge\"}]'"),
            $env,
            60,
        );

        $appels = appelsGh($result['output']);
        $commentaires = array_values(array_filter($appels, static fn (string $l): bool => str_starts_with($l, 'issue comment')));
        $creations = array_values(array_filter($appels, static fn (string $l): bool => str_starts_with($l, 'issue create')));

        expect($commentaires)
            ->toHaveCount(1, "L’issue existante n’a pas été commentée :\n" . $result['output']);
        expect($commentaires[0])
            ->toStartWith('issue comment 42');
        expect($creations)
            ->toBe([], 'Une SECONDE issue est créée alors qu’une issue ouverte porte déjà ce titre.');
    } finally {
        @unlink($env['ETAPE']);
    }
});

it('EXÉCUTÉE : sans issue ouverte, une issue est CRÉÉE, avec son label', function (): void {
    // ⛔ ANTI-VACUITÉ DU TEST PRÉCÉDENT : une étape qui ne créerait JAMAIS rien
    // le satisferait — et le nightly rouge resterait invisible, ce qui est le
    // défaut d'origine.
    $env = environnementSondeAlerte();

    try {
        $result = ShellProbe::run(sondeAlerteNightly("'[]'"), $env, 60);

        $appels = appelsGh($result['output']);
        $creations = array_values(array_filter($appels, static fn (string $l): bool => str_starts_with($l, 'issue create')));

        expect($creations)
            ->toHaveCount(1, "Aucune issue créée sur un ensemble vide :\n" . $result['output']);
        expect($creations[0])
            ->toContain('--label nightly');
        expect(array_filter($appels, static fn (string $l): bool => str_starts_with($l, 'issue comment')))
            ->toBe([]);
    } finally {
        @unlink($env['ETAPE']);
    }
});

it('EXÉCUTÉE : une issue au titre DIFFÉRENT ne vaut pas déduplication', function (): void {
    // Sinon n'importe quelle issue ouverte portant le label ferait taire
    // l'alerte — la déduplication porte sur le titre, pas sur le label seul.
    $env = environnementSondeAlerte();

    try {
        $result = ShellProbe::run(
            sondeAlerteNightly("'[{\"number\":7,\"title\":\"autre chose\"}]'"),
            $env,
            60,
        );

        $appels = appelsGh($result['output']);

        expect(array_filter($appels, static fn (string $l): bool => str_starts_with($l, 'issue create')))
            ->toHaveCount(1);
        expect(array_filter($appels, static fn (string $l): bool => str_starts_with($l, 'issue comment')))
            ->toBe([]);
    } finally {
        @unlink($env['ETAPE']);
    }
});

it('EXÉCUTÉE : une sortie ILLISIBLE crée une issue plutôt que de commenter au hasard', function (): void {
    // ⚖️ Le refus explicite : « je ne sais pas lire » ne doit pas devenir
    // « il n'y a rien », ni faire commenter un numéro inventé.
    $env = environnementSondeAlerte();

    try {
        $result = ShellProbe::run(sondeAlerteNightly("'ceci nest pas du JSON'"), $env, 60);

        $appels = appelsGh($result['output']);

        expect(array_filter($appels, static fn (string $l): bool => str_starts_with($l, 'issue comment')))
            ->toBe([]);
        expect(array_filter($appels, static fn (string $l): bool => str_starts_with($l, 'issue create')))
            ->toHaveCount(1);
    } finally {
        @unlink($env['ETAPE']);
    }
});

it('crée le label `nightly` avant de s’en servir', function (): void {
    // 🔴 Sans le label, `gh issue create --label nightly` échoue ; le repli
    // créait alors une issue SANS label, que la recherche filtrée ne retrouve
    // jamais — une issue neuve chaque nuit, indéfiniment. Relevé en revue 2.
    $corps = implode("\n", workflowRunBodies('.github/workflows/nightly.yml'));

    expect($corps)
        ->toContain('gh label create nightly');

    /*
     * ⛔ ET IL N'EXISTE PLUS DE REPLI SANS LABEL. La rédaction précédente
     * faisait `gh issue create --label nightly … || gh issue create …` : quand
     * le label manquait, la seconde branche créait une issue ORPHELINE, que la
     * recherche filtrée du lendemain ne retrouvait pas. Toute création doit
     * donc porter le label.
     *
     * ⚠️ Les COMMENTAIRES sont écartés : ce step explique précisément ce
     * défaut, donc il cite la commande fautive.
     */
    $creations = array_values(array_filter(
        explode("\n", $corps),
        static fn (string $line): bool => str_contains($line, 'gh issue create')
            && ! str_starts_with(ltrim($line), '#'),
    ));

    expect($creations)
        ->toHaveCount(1);
    expect($creations[0])
        ->toContain('--label nightly');
});

/*
|------------------------------------------------------------------------------
| Le verdict global DÉPEND du nightly — clôture 2.4, la bascule
|------------------------------------------------------------------------------
|
| 🔴 CE QUE CES TROIS TESTS EXISTENT POUR EMPÊCHER.
| `nightly-freshness` a vécu HORS des `needs:` de `CI Summary` — délibérément,
| tant qu'il rougissait par construction. Il y est rentré le 2026-08-24, après
| le premier nightly réellement vert (run `32750543638`). Livrée seule, cette
| bascule n'aurait été gardée par RIEN : la retirer — d'un `needs:`, d'une
| condition `if:` — n'aurait fait rougir aucun test, et le garde-fou
| anti-désarmement se serait éteint exactement comme les garde-fous qu'il
| surveille. C'est le motif de tête de ce dépôt, appliqué à sa propre clôture.
|
| ⚖️ MÊME PATRON QUE LE JOB `alert`, ET C'EST VOULU : on ÉVALUE la condition
| dans un contexte simulé plutôt que d'en comparer le TEXTE. Une reformulation
| équivalente doit rester verte ; c'est ce qui distingue un garde d'une
| photographie. `conditionEstVraie()` / `jetonsCondition()` sont réutilisés tels
| quels — une implémentation partagée, jamais une copie.
|
| ⛔ ET LE CONTEXTE EST DÉRIVÉ DES `needs:` RÉELS, pas énuméré ici. C'est ce qui
| fait rougir le retrait de `nightly-freshness` des `needs:` : la condition
| référence alors un identifiant que le contexte ne fournit plus, et
| l'évaluateur REFUSE au lieu de rendre un verdict.
|
*/

/**
 * Le job `summary` de la CI, lu sur disque.
 *
 * @return array<string, mixed>
 */
function jobResumeCi(): array
{
    $document = RepoFile::yaml('.github/workflows/ci.yml');
    $jobs = $document['jobs'] ?? null;
    $resume = is_array($jobs) ? ($jobs['summary'] ?? null) : null;

    expect(is_array($resume))
        ->toBeTrue('Le job `summary` de la CI a disparu : plus rien ne rend de verdict global.');

    /** @var array<string, mixed> $resume */
    return $resume;
}

/**
 * Les jobs dont dépend le verdict global, lus sur disque.
 *
 * @return list<string>
 */
function besoinsResumeCi(): array
{
    $needs = jobResumeCi()['needs'] ?? null;
    $needs = is_string($needs) ? [$needs] : $needs;

    return array_values(array_filter(
        is_array($needs) ? $needs : [],
        static fn (mixed $job): bool => is_string($job),
    ));
}

/**
 * La condition `if:` de l'étape qui fait ÉCHOUER le verdict global.
 *
 * ⚠️ L'étape est trouvée par son EFFET (`exit 1`), pas par son nom : un libellé
 * peut être retouché sans rien changer, et un garde qui suit le libellé
 * cesserait de mesurer sur une reformulation anodine.
 */
function conditionVerdictSummary(): string
{
    $steps = jobResumeCi()['steps'] ?? null;

    foreach (is_array($steps) ? $steps : [] as $step) {
        $run = is_array($step) ? ($step['run'] ?? null) : null;

        if (! is_string($run) || ! str_contains($run, 'exit 1')) {
            continue;
        }

        $condition = is_array($step) ? ($step['if'] ?? null) : null;

        // ⛔ PAS DE REPLI SUR UNE EXPRESSION NEUTRE ICI. Une étape `exit 1`
        // SANS `if:` ferait échouer la CI à chaque run : ce n'est pas un
        // « verdict toujours vrai » anodin, c'est un dépôt qui ne peut plus
        // rien merger. On le dit, plutôt que de l'évaluer.
        expect(is_string($condition))
            ->toBeTrue('L’étape bloquante du résumé n’a plus de condition `if:` : la CI échouerait à chaque run.');

        return is_string($condition) ? $condition : '';
    }

    throw new RuntimeException('Aucune étape `exit 1` dans le job `summary` : le verdict global ne bloque plus rien.');
}

/**
 * Contexte de sonde du verdict global, DÉRIVÉ des `needs:` réels.
 *
 * Tous les jobs sont `success` sauf ceux que `$echecs` nomme.
 *
 * @param  array<string, string>  $echecs
 * @return array<string, string|null>
 */
function contexteVerdict(array $echecs = []): array
{
    $contexte = [
        'always()' => 'true',
        'success()' => 'true',
        'failure()' => 'false',
        'cancelled()' => 'false',
        'github.event_name' => 'push',
    ];

    foreach (besoinsResumeCi() as $job) {
        $contexte['needs.' . $job . '.result'] = $echecs[$job] ?? 'success';
    }

    return $contexte;
}

it('le verdict global ROUGIT quand le garde-fou du nightly rougit', function (): void {
    /*
     * ⛔ L'INTENTION, TELLE QU'UN HUMAIN SE LA POSE : le nightly est périmé,
     * désactivé, ou son dernier run a échoué sur un vrai défaut d'installeur —
     * est-ce que la CI le dit ? Avant le 2026-08-24, la réponse était NON, et
     * c'était assumé : le nightly n'avait jamais tourné. Elle est OUI depuis.
     */
    $condition = conditionVerdictSummary();

    foreach (['failure', 'cancelled', 'skipped'] as $verdict) {
        expect(conditionEstVraie($condition, contexteVerdict([
            'nightly-freshness' => $verdict,
        ])))
            ->toBeTrue(
                "Un `nightly-freshness` « {$verdict} » laisse le verdict global VERT : le garde-fou "
                . 'anti-désarmement est lui-même désarmé.',
            );
    }
});

it('n’a pas rendu le verdict global aveugle pour autant', function (): void {
    /*
     * ⛔ ANTI-VACUITÉ, ET C'EST ELLE QUI DONNE SA VALEUR AU TEST PRÉCÉDENT.
     * Une condition toujours vraie — ou un évaluateur qui rendrait `true` en
     * toute circonstance — satisferait le garde ci-dessus tout en rendant la
     * CI rouge en permanence, donc illisible.
     *
     * La seconde moitié est la ligne « régression réelle » de la matrice : le
     * verdict ne doit pas dépendre du SEUL nightly. Un `tests` rouge le rougit,
     * nightly vert ou non.
     */
    $condition = conditionVerdictSummary();

    expect(conditionEstVraie($condition, contexteVerdict()))
        ->toBeFalse('Tout au vert, le verdict global échoue quand même : la CI ne peut plus rien merger.');

    foreach (besoinsResumeCi() as $job) {
        expect(conditionEstVraie($condition, contexteVerdict([
            $job => 'failure',
        ])))
            ->toBeTrue("Le job « {$job} » peut échouer sans rougir le verdict global.");
    }
});

it('le verdict global DÉPEND toujours du job qu’il lit', function (): void {
    /*
     * ⛔ SANS `needs: […, nightly-freshness]`, LA CONDITION LIT UN CONTEXTE
     * ABSENT. `needs.nightly-freshness.result` deviendrait vide chez GitHub,
     * `!= 'success'` serait VRAI en permanence, et la CI rougirait toujours —
     * ou, selon la rédaction, jamais. Les deux gardes ci-dessus évaluent la
     * condition ; ils ne voient pas le graphe de jobs qui la nourrit. C'est le
     * même piège que pour le job `alert` du nightly, et il se garde pareil.
     */
    expect(besoinsResumeCi())
        ->toContain('nightly-freshness');

    $document = RepoFile::yaml('.github/workflows/ci.yml');
    $jobs = $document['jobs'] ?? null;

    expect(array_keys(is_array($jobs) ? $jobs : []))
        ->toContain('nightly-freshness');

    // …et le résumé le RAPPORTE, plutôt que de le lire en silence.
    $steps = jobResumeCi()['steps'] ?? null;
    $corps = '';

    foreach (is_array($steps) ? $steps : [] as $step) {
        $run = is_array($step) ? ($step['run'] ?? null) : null;
        $corps .= is_string($run) ? $run : '';
    }

    expect($corps)
        ->toContain('needs.nightly-freshness.result');
});

/*
|------------------------------------------------------------------------------
| `nightly-freshness`, EXÉCUTÉ — clôture 2.4
|------------------------------------------------------------------------------
|
| 🔴 POURQUOI L'EXÉCUTER PLUTÔT QUE LE RELIRE. La tolérance ajoutée le
| 2026-08-24 — « un dernier run rouge de cause AMONT est toléré si un vert
| existe dans la fenêtre » — est la seule partie de cette story qui peut, si
| elle est trop large, ÉTEINDRE le garde-fou qu'on vient de rendre bloquant. Un
| test qui en relirait le texte serait vert sur une condition inversée.
|
| ⚠️ ENVIRONNEMENT DE MESURE, NOMMÉ. Le corps est exécuté sous `bash`, avec un
| `gh` stubé (`tests/Fixtures/shell/gh-api-stub.sh`) et un `date` épinglé
| (`tests/Fixtures/shell/gnu-date-shim.sh`) : `/bin/date` du conteneur
| `laravel-app_php` est BusyBox et REFUSE l'ISO 8601 de l'API GitHub, là où le
| runner `ubuntu-latest` a GNU coreutils. Sans cet épinglage, la sonde
| mesurerait le binaire de la machine au lieu de la logique du workflow.
|
*/

/**
 * L'étape unique du job `nightly-freshness`, lue sur disque.
 *
 * @return array<string, mixed>
 */
function etapeFraicheurNightly(): array
{
    $document = RepoFile::yaml('.github/workflows/ci.yml');
    $jobs = $document['jobs'] ?? null;
    $job = is_array($jobs) ? ($jobs['nightly-freshness'] ?? null) : null;
    $steps = is_array($job) ? ($job['steps'] ?? null) : null;
    $premier = is_array($steps) ? ($steps[0] ?? null) : null;

    expect(is_array($premier))
        ->toBeTrue('Le job `nightly-freshness` n’a plus d’étape.');

    /** @var array<string, mixed> $premier */
    return $premier;
}

/**
 * Le corps du step de `nightly-freshness`, tel que la CI le porte.
 */
function corpsFraicheurNightly(): string
{
    $run = etapeFraicheurNightly()['run'] ?? null;

    expect(is_string($run))
        ->toBeTrue('Le job `nightly-freshness` n’a plus de corps `run:`.');

    return is_string($run) ? $run : '';
}

/**
 * Le plafond de fraîcheur, LU dans le `env:` du step — jamais recopié.
 */
function plafondFraicheurNightly(): int
{
    $env = etapeFraicheurNightly()['env'] ?? null;
    $plafond = is_array($env) ? ($env['MAX_AGE_DAYS'] ?? null) : null;

    expect(is_numeric($plafond))
        ->toBeTrue('`MAX_AGE_DAYS` a disparu du step `nightly-freshness`.');

    return is_numeric($plafond) ? (int) $plafond : 0;
}

/**
 * L'environnement de la sonde, DÉRIVÉ du bloc `env:` de l'étape.
 *
 * 🔴 POURQUOI DÉRIVÉ, ET PAS ÉCRIT ICI (revue 3). La sonde injectait `REPO` et
 * `GH_TOKEN` de sa propre initiative, alors que la CI les tient de son `env:`.
 * Supprimer `REPO: ${{ github.repository }}` de `ci.yml` laissait donc TOUTES
 * les sondes vertes — et tuait le job en CI, où `$REPO` serait vide. Le harnais
 * fournissait ce que le sujet ne fournissait plus : il masquait le défaut au
 * lieu de le révéler.
 *
 * ⛔ Depuis, une clé retirée du `env:` n'est plus posée par la sonde : le corps
 * tourne sous `set -u`, la variable est non liée, et l'étape meurt. Et une clé
 * AJOUTÉE que ce harnais ne sait pas modéliser lève, plutôt que d'être passée
 * à vide — « je ne sais pas mesurer » doit rougir.
 *
 * @return array<string, string>
 */
function envSondeFraicheur(): array
{
    $declare = etapeFraicheurNightly()['env'] ?? null;

    expect(is_array($declare))
        ->toBeTrue('Le step `nightly-freshness` n’a plus de bloc `env:` : ses entrées ne sont plus déclarées.');

    $fixtures = [
        'GH_TOKEN' => 'jeton',
        'REPO' => 'proprietaire/depot',
        'DEFAULT_BRANCH' => 'main',
        'MAX_AGE_DAYS' => (string) plafondFraicheurNightly(),
    ];

    $env = [];

    foreach (array_keys(is_array($declare) ? $declare : []) as $cle) {
        $cle = (string) $cle;

        if (! array_key_exists($cle, $fixtures)) {
            throw new RuntimeException(
                "Le step `nightly-freshness` déclare « {$cle} » dans son `env:`, que cette sonde ne sait "
                . 'pas modéliser. Ajoutez-lui une valeur de fixture plutôt que de la laisser vide.',
            );
        }

        $env[$cle] = $fixtures[$cle];
    }

    return $env;
}

/**
 * Le pilote de sonde : `gh` stubé, `date` épinglé, résumé capturé.
 */
function sondeFraicheurNightly(): string
{
    return <<<'BASH'
        set -e
        bac="$(mktemp -d)"
        mkdir -p "$bac/bin"

        # ⛔ RÉSOLU AVANT DE PRÉFIXER LE `PATH` : le shim délègue au `date` réel,
        # et sans ce relevé préalable il s'appellerait lui-même.
        REAL_DATE="$(command -v date)"; export REAL_DATE

        cp "$STUB_GH" "$bac/bin/gh"
        cp "$SHIM_DATE" "$bac/bin/date"
        chmod +x "$bac/bin/gh" "$bac/bin/date"

        PATH="$bac/bin:$PATH"; export PATH

        GITHUB_STEP_SUMMARY="$bac/resume.md"; export GITHUB_STEP_SUMMARY
        : > "$GITHUB_STEP_SUMMARY"

        statut=0
        bash "$ETAPE" > "$bac/sortie" 2>&1 || statut=$?

        echo "STATUT=$statut"
        echo "=== SORTIE ==="
        cat "$bac/sortie"
        echo "=== RESUME ==="
        cat "$GITHUB_STEP_SUMMARY"
        echo "=== FIN ==="

        rm -rf "$bac"
        BASH;
}

/**
 * Exécute le VRAI corps de `nightly-freshness` contre un `gh` stubé.
 *
 * @param  array<string, string>  $fixtures
 * @return array{status: int, output: string}
 */
function executerFraicheurNightly(array $fixtures): array
{
    /*
     * ⛔ `tempnam()` CRÉE UN FICHIER, ET `. '.sh'` EN DÉSIGNE UN AUTRE.
     * La rédaction précédente écrivait dans le second et ne supprimait que
     * lui : le premier FUYAIT à chaque appel. Et le retour de
     * `file_put_contents()` n'était pas vérifié — une écriture en échec
     * donnait une sonde qui exécute un fichier VIDE, donc un `exit 0`, donc
     * une sonde VERTE qui n'a rien mesuré.
     */
    $chemin = tempnam(sys_get_temp_dir(), 'fraicheur-');

    if ($chemin === false) {
        throw new RuntimeException('Impossible de créer le fichier de sonde de fraîcheur.');
    }

    $ecrit = file_put_contents($chemin, corpsFraicheurNightly());

    if ($ecrit === false || $ecrit === 0) {
        @unlink($chemin);

        throw new RuntimeException("Corps de l’étape non écrit dans la sonde : {$chemin}");
    }

    try {
        $result = ShellProbe::run(
            sondeFraicheurNightly(),
            array_merge(envSondeFraicheur(), [
                'ETAPE' => $chemin,
                'STUB_GH' => ShellProbe::repoRoot() . '/src/tests/Fixtures/shell/gh-api-stub.sh',
                'SHIM_DATE' => ShellProbe::repoRoot() . '/src/tests/Fixtures/shell/gnu-date-shim.sh',
            ], $fixtures),
            60,
        );

        if (preg_match('/STATUT=(\d+)/', $result['output'], $statut) !== 1) {
            throw new RuntimeException("Sonde de fraîcheur illisible :\n" . $result['output']);
        }

        return [
            'status' => (int) $statut[1],
            'output' => $result['output'],
        ];
    } finally {
        @unlink($chemin);
    }
}

/**
 * Un horodatage ISO 8601, tel que l'API GitHub le rend.
 */
function ilYAJours(float $jours): string
{
    return gmdate('Y-m-d\TH:i:s\Z', time() - (int) round($jours * 86400));
}

it('EXÉCUTÉ : un dernier nightly frais et VERT laisse le garde vert', function (): void {
    // Anti-vacuité de tous les tests qui suivent : si le chemin nominal
    // n'aboutissait pas, leurs rouges ne prouveraient rien.
    $sonde = executerFraicheurNightly([
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'success',
        'FIX_RUNID' => '32750543638',
    ]);

    expect($sonde['status'])->toBe(0, $sonde['output']);
    expect($sonde['output'])->toContain('Nightly frais');
});

it('EXÉCUTÉ : un rouge SANS artefact de cause fait échouer le garde', function (): void {
    /*
     * 🔴 LE VRAI DÉFAUT D'INSTALLEUR. Le nightly publie `nightly-install-logs`
     * à tous les coups ; l'étiquette `nightly-cause-infrastructure` n'existe
     * que lorsque le marqueur d'infrastructure a été écrit. La fixture porte
     * donc l'artefact ORDINAIRE — c'est le cas réel, et il doit rougir.
     */
    $sonde = executerFraicheurNightly([
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'failure',
        'FIX_RUNID' => '32743211342',
        'FIX_ARTIFACTS' => 'nightly-install-logs',
        'FIX_GREEN' => ilYAJours(1),
    ]);

    expect($sonde['status'])->toBe(1, $sonde['output']);
    expect($sonde['output'])->toContain('sans artefact de cause amont');
});

it('EXÉCUTÉ : un rouge de cause AMONT est toléré si un vert existe dans la fenêtre', function (): void {
    /*
     * ⚖️ LE CAS MESURÉ (run 32761876936) : `HTTP/2 504` d'`api.github.com`
     * pendant `composer install`, sur un commit dont un autre run était vert
     * (32750543638). Sans cette tolérance, la bascule en bloquant aurait rendu
     * la CI rouge sur TOUS les pushs suivants — le mode de panne exact que la
     * décision de revue 2 voulait éviter, simplement déplacé.
     */
    $sonde = executerFraicheurNightly([
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'failure',
        'FIX_RUNID' => '32761876936',
        'FIX_ARTIFACTS' => "nightly-install-logs\nnightly-cause-infrastructure",
        'FIX_GREEN' => ilYAJours(1),
    ]);

    expect($sonde['status'])->toBe(0, $sonde['output']);
    expect($sonde['output'])->toContain('::warning');
    expect($sonde['output'])->toContain('cause AMONT');

    // ⛔ ET IL NE FAIT PAS SEMBLANT D'ÊTRE VERT : le résumé DIT que le dernier
    // run est rouge. Une tolérance muette serait un désarmement.
    expect($sonde['output'])->toContain('toléré');
});

it('EXÉCUTÉ : une panne amont PERSISTANTE reprend ses dents', function (): void {
    /*
     * ⛔ C'EST LA MOITIÉ QUI EMPÊCHE LA TOLÉRANCE DE DEVENIR UN INTERRUPTEUR
     * D'EXTINCTION. Sans elle, une infrastructure durablement en panne — ou un
     * nightly qui produirait l'étiquette à tort — laisserait le garde vert
     * indéfiniment.
     */
    $plafond = plafondFraicheurNightly();

    $aucunVert = executerFraicheurNightly([
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'failure',
        'FIX_RUNID' => '1',
        'FIX_ARTIFACTS' => 'nightly-cause-infrastructure',
        'FIX_GREEN' => '',
    ]);

    expect($aucunVert['status'])->toBe(1, $aucunVert['output']);
    expect($aucunVert['output'])->toContain('AUCUN run vert');

    $vertTropVieux = executerFraicheurNightly([
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'failure',
        'FIX_RUNID' => '1',
        'FIX_ARTIFACTS' => 'nightly-cause-infrastructure',
        'FIX_GREEN' => ilYAJours($plafond + 2),
    ]);

    expect($vertTropVieux['status'])->toBe(1, $vertTropVieux['output']);
    expect($vertTropVieux['output'])->toContain('redevient bloquant');
});

it('EXÉCUTÉ : les DEUX silences d’origine rougissent encore', function (): void {
    /*
     * ⛔ CE SONT LES DEUX RAISONS D'EXISTER DE CE JOB, ET ELLES SONT ANTÉRIEURES
     * À LA TOLÉRANCE. `ci.yml` les énumère en tête : (1) GitHub DÉSACTIVE un
     * workflow `schedule` après 60 jours sans activité — le nightly s'arrête
     * alors sans un mot ; (2) un nightly qui n'a jamais tourné se lit comme un
     * nightly vert, c'est-à-dire comme une absence de rouge.
     *
     * 🔴 POURQUOI LES ÉPROUVER MAINTENANT. La clôture 2.4 a réécrit le `case`
     * qui décide du verdict, juste en aval de ces deux branches, et les a
     * laissées sans aucun test — alors que le harnais d'exécution construit
     * pour la tolérance (`FIX_STATE`, `FIX_LAST` vide) les couvrait déjà.
     * Une capacité de mesure existante et inemployée, c'est la forme discrète
     * du garde-fou silencieux : la branche n'est pas gardée, et l'outillage
     * qui l'aurait gardée est là, juste à côté.
     *
     * Ces deux chemins précèdent la lecture de la conclusion : ils doivent
     * rougir SANS qu'aucun verdict ni artefact n'entre en jeu.
     */
    $desactive = executerFraicheurNightly([
        'FIX_STATE' => 'disabled_inactivity',
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'success',
    ]);

    expect($desactive['status'])->toBe(1, $desactive['output']);
    expect($desactive['output'])->toContain('disabled_inactivity');

    // ⚠️ Un run VERT et FRAIS est fourni exprès : si le garde regardait la
    // conclusion avant l'état du workflow, il passerait au vert et ce test
    // serait la seule chose à le dire.
    $jamaisLance = executerFraicheurNightly([
        'FIX_STATE' => 'active',
        'FIX_LAST' => '',
        'FIX_VERDICT' => '',
    ]);

    expect($jamaisLance['status'])->toBe(1, $jamaisLance['output']);
    expect($jamaisLance['output'])->toContain('JAMAIS tourné');
});

/**
 * Le nom du FICHIER-MARQUEUR qu'écrit réellement `e2e_infra_fail`.
 *
 * ⛔ LU DANS LA FONCTION, PAS RECOPIÉ. Écrit en dur ici, il resterait juste
 * après un renommage — donc vert sur une chaîne rompue.
 */
function marqueurInfrastructure(): string
{
    $source = RepoFile::read('tests/bats/lib/e2e.bash');

    $debut = strpos($source, 'e2e_infra_fail() {');

    expect($debut)
        ->not->toBeFalse('`e2e_infra_fail` a disparu : plus rien n’écrit le marqueur d’infrastructure.');

    $corps = substr($source, (int) $debut, 600);

    expect(preg_match('#\$E2E_REPORT_DIR/([A-Za-z0-9_]+)"#', $corps, $m))
        ->toBe(1, '`e2e_infra_fail` n’écrit plus de fichier sous `$E2E_REPORT_DIR`.');

    return $m[1] ?? '';
}

it('l’étiquette de cause amont : les QUATRE maillons tiennent ensemble', function (): void {
    /*
     * 🔴 QUATRE FICHIERS, DES CHAÎNES DE CARACTÈRES, ET AUCUN COMPILATEUR ENTRE
     * EUX. Trois mutations prouvées VERTES en revue, chacune tuant la tolérance
     * en silence :
     *   • `id: cause` renommé en `id: etiquette` → l'étape de publication ne se
     *     déclenche plus jamais ;
     *   • `marker="…/INFRASTRUCTURE_FAILURE"` renommé en `…/INFRA_FAIL` → la
     *     sortie vaut `installer` même sur une vraie panne amont ;
     *   • `with.path` n'était asserté nulle part, alors que
     *     `if-no-files-found: error` le rend porteur.
     * Le nom de l'artefact était le seul maillon gardé. Les voici tous les
     * quatre, chacun DÉRIVÉ de son voisin plutôt que recopié.
     */
    $corps = corpsFraicheurNightly();

    // ── Maillon 1 : le lecteur (ci.yml) nomme une étiquette ───────────────
    expect(preg_match("/grep -Fx '([^']+)'/", $corps, $lu))
        ->toBe(1, '`nightly-freshness` ne cherche plus aucun nom d’artefact : la tolérance est morte.');

    $etiquette = $lu[1] ?? '';

    // ── Maillon 2 : le publieur (nightly.yml) porte ce nom ────────────────
    $document = RepoFile::yaml('.github/workflows/nightly.yml');
    $jobs = $document['jobs'] ?? null;
    $install = is_array($jobs) ? ($jobs['install'] ?? null) : null;
    $steps = is_array($install) ? ($install['steps'] ?? null) : null;
    $steps = is_array($steps) ? $steps : [];

    $publieur = null;

    foreach ($steps as $step) {
        $with = is_array($step) ? ($step['with'] ?? null) : null;

        if (is_array($with) && ($with['name'] ?? null) === $etiquette) {
            $publieur = $step;
        }
    }

    expect(is_array($publieur))
        ->toBeTrue("Aucune étape du nightly ne publie l’artefact « {$etiquette} », que `nightly-freshness` cherche pourtant.");

    /** @var array<string, mixed> $publieur */
    $condition = is_string($publieur['if'] ?? null) ? (string) $publieur['if'] : '';

    // ── Maillon 3 : l'`id` référencé par sa condition EXISTE ───────────────
    // ⛔ DÉRIVÉ DE LA CONDITION, jamais écrit ici : c'est ce qui fait rougir un
    // `id:` renommé d'un seul côté.
    expect(preg_match('/steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)/', $condition, $ref))
        ->toBe(1, "L’étape qui publie « {$etiquette} » ne dépend plus d’aucune sortie d’étape : elle se déclenche donc à tous les coups, et TOUT échec du nightly serait toléré.");

    $idAttendu = $ref[1] ?? '';
    $sortieAttendue = $ref[2] ?? '';

    $calculatrice = null;

    foreach ($steps as $step) {
        if (is_array($step) && ($step['id'] ?? null) === $idAttendu) {
            $calculatrice = $step;
        }
    }

    expect(is_array($calculatrice))
        ->toBeTrue("La condition de publication lit `steps.{$idAttendu}.outputs.{$sortieAttendue}`, mais AUCUNE étape ne porte `id: {$idAttendu}` — la condition est vide en permanence, et la tolérance morte.");

    /** @var array<string, mixed> $calculatrice */
    $corpsCalculatrice = is_string($calculatrice['run'] ?? null) ? (string) $calculatrice['run'] : '';

    expect($corpsCalculatrice)
        ->toContain($sortieAttendue . '=');
    expect($corpsCalculatrice)
        ->toContain('GITHUB_OUTPUT');

    // ── Maillon 4 : le MARQUEUR, tel que `e2e_infra_fail` l'écrit ──────────
    $marqueur = marqueurInfrastructure();

    expect($corpsCalculatrice)
        ->toContain('/' . $marqueur);

    /** @var array<string, mixed> $with */
    $with = $publieur['with'];
    $chemin = is_string($with['path'] ?? null) ? (string) $with['path'] : '';

    expect(str_ends_with($chemin, '/' . $marqueur))
        ->toBeTrue("L’artefact « {$etiquette} » publie « {$chemin} », qui n’est pas le marqueur « {$marqueur} » qu’écrit `e2e_infra_fail`. Avec `if-no-files-found: error`, l’étape rougirait sur une panne amont RÉELLE.");

    // Une étiquette sans son marqueur serait un mensonge lisible par API.
    expect($with['if-no-files-found'] ?? null)
        ->toBe('error');
});

/*
|------------------------------------------------------------------------------
| Les branches que PERSONNE n'exerçait — revue 3
|------------------------------------------------------------------------------
|
| 🔴 LE HARNAIS LES COUVRAIT GRATUITEMENT, ET AUCUNE N'AVAIT DE SONDE.
| Mutation prouvée VERTE en revue : `[ "$age_days" -gt "$MAX_AGE_DAYS" ]` porté
| à `-gt 99999` laissait 29/29 verts. C'est la raison d'être n°1 de ce job —
| GitHub désactive un `schedule` après 60 jours — et celle que son nom annonce.
| Idem pour « workflow introuvable via l'API » et pour la branche « encore en
| cours », dont on pouvait inverser la sémantique sans faire rougir personne.
|
| ⚖️ L'argument est le même que pour les deux silences déjà corrigés, et il vaut
| ici aussi : une branche que le harnais peut exercer et qu'aucun test
| n'exerce est un garde-fou muet qui s'ignore.
|
*/

it('EXÉCUTÉ : un nightly TROP VIEUX rougit, même vert', function (): void {
    // 🔴 LA MUTATION QUI ÉTAIT RESTÉE VERTE. Le plafond est la raison d'être
    // n°1 du job ; il n'était gardé par rien.
    $plafond = plafondFraicheurNightly();

    $sonde = executerFraicheurNightly([
        'FIX_LAST' => ilYAJours($plafond + 2),
        'FIX_VERDICT' => 'success',
        'FIX_RUNID' => '1',
    ]);

    expect($sonde['status'])->toBe(1, $sonde['output']);
    expect($sonde['output'])->toContain('Le garde-fou ne tourne plus');
});

it('EXÉCUTÉ : un workflow INTROUVABLE via l’API rougit en nommant la cause', function (): void {
    $sonde = executerFraicheurNightly([
        'FIX_STATE' => '__API_DOWN__',
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'success',
    ]);

    expect($sonde['status'])->toBe(1, $sonde['output']);
    expect($sonde['output'])->toContain('nightly.yml » introuvable');
});

it('EXÉCUTÉ : un workflow DÉSACTIVÉ rougit en nommant son état', function (): void {
    // GitHub désactive les `schedule` après 60 jours sans activité : c'est le
    // silence que ce job existe pour transformer en rouge.
    $sonde = executerFraicheurNightly([
        'FIX_STATE' => 'disabled_inactivity',
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'success',
    ]);

    expect($sonde['status'])->toBe(1, $sonde['output']);
    expect($sonde['output'])->toContain('disabled_inactivity');
});

it('EXÉCUTÉ : un nightly qui n’a JAMAIS tourné rougit', function (): void {
    $sonde = executerFraicheurNightly([
        'FIX_LAST' => '',
    ]);

    expect($sonde['status'])->toBe(1, $sonde['output']);
    expect($sonde['output'])->toContain('JAMAIS tourné');
});

it('EXÉCUTÉ : un run ENCORE EN COURS ne rougit pas, et le dit', function (): void {
    /*
     * ⛔ ANTI-VACUITÉ DE LA BRANCHE : inverser sa sémantique — y faire tomber un
     * `failure` — serait resté vert, faute de sonde. Les deux moitiés sont
     * mesurées : « en cours » passe, et l'annotation dit que le verdict n'est
     * pas concluant plutôt que de le maquiller en réussite.
     */
    $sonde = executerFraicheurNightly([
        'FIX_LAST' => ilYAJours(0.1),
        'FIX_VERDICT' => 'in_progress',
        'FIX_RUNID' => '1',
    ]);

    expect($sonde['status'])->toBe(0, $sonde['output']);
    expect($sonde['output'])->toContain('encore en cours');
    // …et il ne prétend PAS que le nightly est vert.
    expect($sonde['output'])->not->toContain('Nightly frais');
});

/*
|------------------------------------------------------------------------------
| Un run ANNULÉ n'est pas un défaut d'installeur — revue 3
|------------------------------------------------------------------------------
|
| 🔴 LE `case *)` ACCUSAIT L'INSTALLEUR POUR TOUT CE QUI N'ÉTAIT PAS `success`.
| Or l'étape d'étiquetage du nightly est en `if: failure()` : un run ANNULÉ ne
| publie aucun artefact de cause. Un nightly annulé à la main rougissait donc
| TOUS les pushs, avec un message nommant le mauvais coupable.
|
| ⚖️ LE PROJET AVAIT DÉJÀ TRANCHÉ CE POINT, pour le job `alert` : `== 'failure'`
| et non `!= 'success'`, motif écrit — « annuler un run manuel ouvrait une issue
| "nightly rouge" alors que RIEN n'avait échoué ». Une alerte qu'on apprend à
| ignorer est une alerte désarmée ; un verdict global qu'on apprend à ignorer
| l'est tout autant. Le raisonnement est transposé, pas réinventé.
|
| ⛔ MAIS IL GARDE SES DENTS : ces conclusions passent par la MÊME exigence d'un
| vert récent que la tolérance amont. Un nightly annulé toutes les nuits finit
| donc par rougir — sans quoi l'annulation deviendrait l'interrupteur
| d'extinction que toute cette story existe pour interdire.
|
*/

it('EXÉCUTÉ : un run ANNULÉ n’accuse pas l’installeur', function (): void {
    foreach (['cancelled', 'skipped', 'neutral', 'stale'] as $verdict) {
        $sonde = executerFraicheurNightly([
            'FIX_LAST' => ilYAJours(0.5),
            'FIX_VERDICT' => $verdict,
            'FIX_RUNID' => '1',
            'FIX_GREEN' => ilYAJours(1),
        ]);

        expect($sonde['status'])->toBe(0, "Un run « {$verdict} » bloque toute la CI :\n" . $sonde['output']);
        expect($sonde['output'])
            ->not->toContain("c'est l'installeur qui est en cause");
        expect($sonde['output'])->toContain('a été prouvé non plus');
    }
});

it('EXÉCUTÉ : une panne d’EXÉCUTION du runner n’accuse pas l’installeur', function (): void {
    foreach (['timed_out', 'startup_failure'] as $verdict) {
        $sonde = executerFraicheurNightly([
            'FIX_LAST' => ilYAJours(0.5),
            'FIX_VERDICT' => $verdict,
            'FIX_RUNID' => '1',
            'FIX_GREEN' => ilYAJours(1),
        ]);

        expect($sonde['status'])->toBe(0, $sonde['output']);
        expect($sonde['output'])->toContain('runner');
    }
});

it('EXÉCUTÉ : des annulations qui DURENT finissent par rougir', function (): void {
    // ⛔ C'est la moitié qui empêche l'annulation de devenir l'interrupteur
    // d'extinction. Sans elle, annuler le nightly chaque nuit suffirait à
    // éteindre le garde-fou pour toujours.
    $sonde = executerFraicheurNightly([
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'cancelled',
        'FIX_RUNID' => '1',
        'FIX_GREEN' => '',
    ]);

    expect($sonde['status'])->toBe(1, $sonde['output']);
    expect($sonde['output'])->toContain('AUCUN run vert');
});

it('EXÉCUTÉ : une conclusion INCONNUE fait rougir plutôt que deviner', function (): void {
    // « Je ne sais pas » doit rougir : c'est la doctrine de l'évaluateur de
    // conditions, appliquée au lecteur de conclusions.
    $sonde = executerFraicheurNightly([
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'conclusion_de_demain',
        'FIX_RUNID' => '1',
        'FIX_GREEN' => ilYAJours(1),
    ]);

    expect($sonde['status'])->toBe(1, $sonde['output']);
    expect($sonde['output'])->toContain('inconnue de ce garde');
});

/*
|------------------------------------------------------------------------------
| Une panne d'API n'est pas une absence — revue 3
|------------------------------------------------------------------------------
|
| 🔴 L'appel aux artefacts portait `|| true` : une API en carafe devenait
| indiscernable d'« aucune étiquette », et le message accusait l'installeur pour
| un code parfaitement sain. Celui du dernier vert n'était pas gardé du tout :
| sous `set -e`, il tuait l'étape sans nommer de cause. Les deux échouent
| désormais en DISANT qu'ils n'ont pas pu établir la cause.
|
*/

it('EXÉCUTÉ : une API en panne ne se fait pas passer pour une absence de cause', function (): void {
    $artefacts = executerFraicheurNightly([
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'failure',
        'FIX_RUNID' => '1',
        'FIX_ARTIFACTS' => '__API_DOWN__',
    ]);

    expect($artefacts['status'])->toBe(1, $artefacts['output']);
    expect($artefacts['output'])->toContain('INDÉTERMINÉE');
    expect($artefacts['output'])
        ->not->toContain("c'est l'installeur qui est en cause");

    $vert = executerFraicheurNightly([
        'FIX_LAST' => ilYAJours(0.5),
        'FIX_VERDICT' => 'failure',
        'FIX_RUNID' => '1',
        'FIX_ARTIFACTS' => 'nightly-cause-infrastructure',
        'FIX_GREEN' => '__API_DOWN__',
    ]);

    expect($vert['status'])->toBe(1, $vert['output']);
    expect($vert['output'])->toContain('INDÉTERMINÉE');
});

it('ne lit JAMAIS « le dernier nightly » toutes branches confondues', function (): void {
    /*
     * 🔴 `runs?per_page=1` SANS FILTRE DE BRANCHE. Un `workflow_dispatch` lancé
     * depuis une branche de story devenait « le dernier nightly » et décidait
     * du verdict de `main` ; et `runs?status=success` ouvrait la fenêtre
     * d'assouplissement sur un vert obtenu n'importe où. Le garde du verdict de
     * la branche par défaut doit lire la branche par défaut.
     */
    $corps = corpsFraicheurNightly();

    preg_match_all('#/actions/workflows/nightly\.yml/runs\?([^"]*)"#', $corps, $requetes);

    expect($requetes[1])
        ->not->toBe([], 'Plus aucune requête de runs : le garde ne lit plus rien.');

    foreach ($requetes[1] as $query) {
        // ⚠️ `toContain` prend des AIGUILLES, pas un message — cinquième
        // rencontre de ce piège dans ce fichier, et je viens d'y retomber.
        // Le message passe par `toBeTrue`, qui, lui, en accepte un.
        expect(str_contains($query, 'branch='))
            ->toBeTrue("Requête de runs sans filtre de branche : « {$query} ».");
    }
});

/*
|------------------------------------------------------------------------------
| Références d'image Docker — clôture 2.4 (constat d'après-merge)
|------------------------------------------------------------------------------
|
| 🔴 MESURÉ SUR LA PR DEPENDABOT #27, LE 2026-08-24. Le build Docker échouait sur
| « invalid tag "docker.io//laravel-skeleton-apache:pr-27": invalid reference
| format » — DEUX barres obliques. `secrets.DOCKER_USERNAME` est VIDE dans une PR
| Dependabot (périmètre de secrets distinct), et la référence dégénérait avant
| même que le Dockerfile ne soit lu.
|
| ⚖️ CE QUE ÇA COÛTAIT : toute PR Dependabot rougissait son build, pour une raison
| ÉTRANGÈRE à la dépendance montée. Le rouge nommait le mauvais coupable — la
| même classe de défaut que le 504 amont imputé à l'installeur, corrigé le même
| jour. Un rouge qu'on ne peut pas croire est un rouge qu'on cesse de lire.
|
| ⛔ ET LE CAS ÉTAIT DÉJÀ CONNU DU FICHIER, À DEUX ENDROITS SUR TROIS : l'étape de
| login est gardée par `if [ -n … ]`, et un commentaire explique précisément
| pourquoi un segment propriétaire manquant est fatal. C'est l'endroit qui
| DÉCIDE du tag qui ne l'était pas.
|
| ⚖️ CE GARDE ÉVALUE, IL NE RELIT PAS. Il rend la référence comme le moteur de
| workflow le ferait, secret VIDE, puis vérifie que le résultat est une référence
| Docker valide. Recopier le texte de l'expression n'aurait rien prouvé.
|
*/

/**
 * La valeur d'une clé du bloc `env:` de `docker.yml`.
 */
function envDocker(string $cle): string
{
    $document = RepoFile::yaml('.github/workflows/docker.yml');
    $env = $document['env'] ?? null;
    $valeur = is_array($env) ? ($env[$cle] ?? null) : null;

    // ⚠️ `expect()` ne RESTREINT PAS le type pour l'analyseur statique : la
    // rédaction précédente cassait le ratchet (`Cannot cast mixed to string`).
    // Le refus explicite fait les deux — il nomme la cause et il narrow.
    if (! is_string($valeur) || $valeur === '') {
        throw new RuntimeException(
            "La clé `env.{$cle}` de docker.yml a disparu : la référence d'image ne peut plus être rendue.",
        );
    }

    return $valeur;
}

/**
 * Rend TOUTES les références d'image de `docker.yml` comme le ferait le moteur
 * de workflow, pour une valeur donnée de `secrets.DOCKER_USERNAME`.
 *
 * @return array<int, string>
 */
function referencesImageDocker(string $secret): array
{
    $lignes = explode("\n", RepoFile::read('.github/workflows/docker.yml'));
    $rendus = [];

    foreach ($lignes as $ligne) {
        // ⚠️ LE SLASH FINAL EST LE FILTRE, et il n'est pas décoratif : l'étape de
        // login porte `registry: ${{ env.REGISTRY }}` SANS slash — c'est le nom
        // du registre, pas une référence d'image. Sans cette précision, ce garde
        // rougissait sur `docker.io` seul, c'est-à-dire sur son propre bruit.
        if (! str_contains($ligne, '${{ env.REGISTRY }}/')) {
            continue;
        }

        $rendu = $ligne;

        // Le ternaire d'expression GitHub : `A != '' && A || B`.
        $rendu = preg_replace_callback(
            '/\$\{\{\s*secrets\.DOCKER_USERNAME\s*!=\s*\'\'\s*&&\s*secrets\.DOCKER_USERNAME\s*\|\|\s*env\.FALLBACK_OWNER\s*\}\}/',
            static fn (): string => $secret !== '' ? $secret : envDocker('FALLBACK_OWNER'),
            (string) $rendu,
        ) ?? '';

        $rendu = str_replace(
            ['${{ env.REGISTRY }}', '${{ env.NAMESPACE }}', '${{ env.FALLBACK_OWNER }}',
                '${{ secrets.DOCKER_USERNAME }}', '${{ matrix.service }}', '${{ github.sha }}', '${service}'],
            [envDocker('REGISTRY'), envDocker('NAMESPACE'), envDocker('FALLBACK_OWNER'),
                $secret, 'php', 'cafe1234', 'php'],
            $rendu,
        );

        // On ne garde que le fragment de référence lui-même.
        if (preg_match('#[a-z0-9./:_-]*' . preg_quote(envDocker('REGISTRY'), '#') . '[^"\s]*#', $rendu, $m) === 1) {
            $rendus[] = trim($m[0], '"\'');
        }
    }

    return $rendus;
}

it('la référence d’image Docker reste VALIDE quand le secret est absent', function (): void {
    /*
     * 🔴 LE CAS DEPENDABOT, ET C'EST CELUI QUI A CASSÉ. Secret vide.
     * Une référence valide a TROIS segments : registre / propriétaire / dépôt.
     * Deux barres obliques consécutives = un segment vide = « invalid reference
     * format », et buildx sort avant de lire quoi que ce soit.
     */
    $references = referencesImageDocker('');

    // Anti-vacuité : il y a bien des références à éprouver. Sans elle, supprimer
    // toute construction d'image rendrait ce test vert.
    expect(count($references))
        ->toBeGreaterThanOrEqual(2, 'Aucune référence d’image trouvée dans docker.yml : ce garde ne garde rien.');

    foreach ($references as $reference) {
        expect(str_contains($reference, '//'))
            ->toBeFalse("Segment VIDE dans « {$reference} » — c’est l’échec mesuré sur la PR #27.");

        // Registre / propriétaire / dépôt, en minuscules — Docker refuse les majuscules.
        expect((bool) preg_match(
            '#^[a-z0-9.-]+/[a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._-]*(:[A-Za-z0-9._-]+)?$#',
            $reference,
        ))->toBeTrue("Référence Docker invalide : « {$reference} ».");
    }
});

it('n’a pas rendu le propriétaire constant pour autant', function (): void {
    /*
     * ⛔ ANTI-VACUITÉ, ET C'EST ELLE QUI DONNE SA VALEUR AU TEST PRÉCÉDENT.
     * Un repli qui s'appliquerait TOUJOURS satisferait le garde ci-dessus tout
     * en poussant les images sous un nom qui n'appartient à personne. Quand le
     * secret EST présent, c'est lui qui doit gagner.
     */
    $avecSecret = referencesImageDocker('kaelyscius');
    $repli = envDocker('FALLBACK_OWNER');

    expect(count($avecSecret))
        ->toBeGreaterThanOrEqual(2);

    foreach ($avecSecret as $reference) {
        expect($reference)->toContain('/kaelyscius/');
        expect($reference)
            ->not->toContain('/' . $repli . '/');
    }
});

/**
 * Les règles de tag de l'étape `metadata` de `docker.yml`, lues sur disque.
 *
 * @return array<int, string>
 */
function reglesTagDocker(): array
{
    $lignes = explode("\n", RepoFile::read('.github/workflows/docker.yml'));
    $regles = [];
    $dans = false;

    foreach ($lignes as $ligne) {
        if (preg_match('/^\s*tags:\s*\|\s*$/', $ligne) === 1) {
            $dans = true;

            continue;
        }

        if (! $dans) {
            continue;
        }

        $nue = trim($ligne);

        // Fin du bloc scalaire : une ligne vide ou non indentée.
        if ($nue === '' || preg_match('/^\s{10,}/', $ligne) !== 1) {
            break;
        }

        if (str_starts_with($nue, '#')) {
            continue;
        }

        $regles[] = $nue;
    }

    return $regles;
}

/**
 * Les tags que `metadata-action` produirait pour un évènement donné.
 *
 * `{{branch}}` est rendu VIDE sur une pull request — c'est le cœur du défaut.
 *
 * @return array<int, string>
 */
function tagsRendusDocker(string $evenement, string $branche): array
{
    $sha = 'b7d9f36';
    $tags = [];

    foreach (reglesTagDocker() as $regle) {
        // `enable=${{ … }}` est une expression GitHub : on l'ÉVALUE.
        if (preg_match('/enable=\$\{\{(.+?)\}\}/', $regle, $m) === 1) {
            // ⛔ LA VALEUR DE CONTEXTE EST NUE, JAMAIS QUOTÉE. `valeurDe()` rend
            // la valeur du contexte telle quelle et DÉTOURE le littéral d'en
            // face : `"'pull_request'"` ne serait jamais égal à `pull_request`,
            // donc tout `!=` serait vrai et aucune règle gatée ne serait
            // sautée. Convention du fichier (lignes 699 et 1259) : valeur nue.
            if (! conditionEstVraie(trim($m[1]), [
                'github.event_name' => $evenement,
            ])) {
                continue;
            }
        } elseif (str_contains($regle, 'enable={{is_default_branch}}')) {
            // DSL de metadata-action, hors de portée de l'évaluateur : seule la
            // branche par défaut d'un `push` l'active.
            if ($evenement !== 'push' || $branche !== 'main') {
                continue;
            }

            $tags[] = 'latest';

            continue;
        }

        if (str_starts_with($regle, 'type=sha')) {
            $prefixe = preg_match('/prefix=([^,]*)/', $regle, $p) === 1
                ? str_replace('{{branch}}', $branche, $p[1])
                : 'sha-'; // défaut de metadata-action
            $tags[] = $prefixe . $sha;

            continue;
        }

        if (str_contains($regle, 'type=ref,event=pr')) {
            if ($evenement === 'pull_request') {
                $tags[] = 'pr-27';
            }

            continue;
        }

        if (str_contains($regle, 'type=ref,event=branch')) {
            if ($evenement === 'push' && $branche !== '') {
                $tags[] = $branche;
            }
        }
    }

    return $tags;
}

it('aucune règle de tag ne produit un tag INVALIDE sur une pull request', function (): void {
    /*
     * 🔴 LE SECOND DÉFAUT, ET IL ÉTAIT MASQUÉ PAR LE PREMIER. Une fois le
     * namespace vide corrigé, la PR #27 a rendu `:-b7d9f36` — un tag qui
     * COMMENCE par un tiret, que Docker refuse. Cause : `type=sha,prefix={{branch}}-`
     * et `{{branch}}` est VIDE sur un évènement `pull_request`.
     *
     * ⚖️ Et ce garde-ci existe parce que le précédent ne suffisait pas : il rendait
     * la ligne `images:` et JAMAIS le bloc `tags:`, alors qu'« invalid reference
     * format » frappe les deux moitiés de la référence. Un garde qui ne couvre
     * qu'une moitié de son sujet laisse l'autre moitié muette.
     */
    $tags = tagsRendusDocker('pull_request', '');

    expect(count($tags))
        ->toBeGreaterThanOrEqual(2, 'Aucun tag rendu : ce garde ne garde rien.');

    foreach ($tags as $tag) {
        // Un tag Docker commence par un alphanumérique ou un souligné.
        expect((bool) preg_match('/^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$/', $tag))
            ->toBeTrue("Tag Docker invalide sur une pull request : « {$tag} ».");
    }
});

it('n’a pas désarmé le tag de branche pour autant', function (): void {
    /*
     * ⛔ ANTI-VACUITÉ. Gater la règle sur `pull_request` ne doit pas la faire
     * disparaître d'un `push` : c'est elle qui porte le nom de branche dans le
     * tag. Sans cette moitié, supprimer purement la règle satisferait le test
     * précédent — un tag invalide de moins, et une information de moins.
     */
    $tags = tagsRendusDocker('push', 'main');

    expect($tags)
        ->toContain('main-b7d9f36');
    expect($tags)
        ->toContain('latest');
});
