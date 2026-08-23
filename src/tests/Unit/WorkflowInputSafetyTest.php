<?php

declare(strict_types=1);

use Tests\Support\RepoFile;

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
    $files = glob(RepoFile::root() . '/.github/workflows/*.yml');

    return array_map(
        static fn (string $path): string => '.github/workflows/' . basename($path),
        $files === false ? [] : $files,
    );
}

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

it('ne lit jamais un identifiant d’issue sans `// empty`', function (): void {
    $alerte = workflowRunBodies('.github/workflows/nightly.yml');
    $corps = implode("\n", $alerte);

    expect($corps)
        ->toContain('--jq');

    // Toute lecture `.[0].…` doit être protégée par `// empty`.
    preg_match_all('/--jq\s+\'([^\']*)\'/', $corps, $matches);

    $lectures = array_values(array_filter(
        $matches[1],
        static fn (string $expression): bool => str_contains($expression, '.[0].'),
    ));

    // Anti-vacuité : il y a bien au moins une lecture de ce genre à garder.
    expect($lectures)
        ->not->toBe([]);

    foreach ($lectures as $expression) {
        expect($expression)
            ->toContain('// empty');
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
