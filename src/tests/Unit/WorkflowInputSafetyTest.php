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

        $motif = '/(\|\||&&|==|!=|!|\(|\)|\'[^\']*\'|[A-Za-z_][A-Za-z0-9_.]*(?:\(\))?)/A';

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
    $chemin = tempnam(sys_get_temp_dir(), 'alerte-') . '.sh';
    file_put_contents($chemin, corpsEtapeAlerte());

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
