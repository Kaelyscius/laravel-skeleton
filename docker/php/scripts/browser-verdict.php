<?php

declare(strict_types=1);

/*
|------------------------------------------------------------------------------
| Verdict des tests navigateur, lu dans le rapport JUnit
|------------------------------------------------------------------------------
|
| POURQUOI CE FICHIER EXISTE
|
| Le plugin `pest-plugin-browser` rend le bon verdict puis, environ une fois sur
| deux, ne rend pas la main : le processus reste vivant jusqu'à ce qu'une borne
| dure le tue. Mesuré le 2026-08-06 sur 10 exécutions : 6 blocages, verdict
| correct à chaque fois. Voir ADR-0013.
|
| Le code de sortie de `pest` est donc inutilisable : un run VERT bloqué sort en
| 137, indiscernable d'un échec. Le rapport JUnit, lui, est écrit par PHPUnit
| AVANT le teardown qui se bloque — complet, balise de clôture comprise, dans
| 10 cas sur 10, blocages inclus. C'est la seule source de vérité disponible.
|
| CE QUI COMPTE ICI : L'ABSENCE DE PREUVE N'EST PAS UNE PREUVE DE SUCCÈS.
|
| Ce script sort en échec dès qu'il ne peut pas AFFIRMER le succès :
|   - rapport absent, illisible ou tronqué  -> échec
|   - zéro test exécuté                     -> échec (une suite vide n'est pas verte)
|   - la moindre failure ou error           -> échec
| C'est la règle d'admission du projet : un garde-fou qui ne peut pas rougir
| n'est pas un garde-fou.
|
| Usage : php browser-verdict.php <chemin-junit.xml> <code-sortie-de-pest>
| Sortie : 0 si et seulement si le succès est démontré.
*/

$reportPath = $argv[1] ?? '';
$pestExitCode = isset($argv[2]) ? (int) $argv[2] : -1;

/**
 * Échoue bruyamment : le message part sur STDERR et le code de sortie est non nul.
 */
function refuse(string $reason): never
{
    fwrite(STDERR, "\n❌ Tests navigateur : verdict NON ÉTABLI.\n   {$reason}\n");
    exit(1);
}

if ($reportPath === '' || ! is_file($reportPath)) {
    refuse("Rapport JUnit absent ({$reportPath}). Pest n'a rien produit : c'est une panne du runner, pas un succès.");
}

$xml = file_get_contents($reportPath);

if ($xml === false || trim($xml) === '') {
    refuse("Rapport JUnit vide ({$reportPath}).");
}

// Un rapport tronqué signalerait que PHPUnit est mort en cours d'écriture.
if (! str_contains($xml, '</testsuites>')) {
    refuse('Rapport JUnit tronqué : la balise de clôture manque. Le run a été interrompu avant la fin.');
}

$previous = libxml_use_internal_errors(true);
$document = simplexml_load_string($xml);
libxml_use_internal_errors($previous);

if ($document === false) {
    refuse('Rapport JUnit illisible : XML invalide.');
}

$totals = ['tests' => 0, 'assertions' => 0, 'failures' => 0, 'errors' => 0];

// Les <testsuite> s'imbriquent ; ne compter que le premier niveau évite de
// additionner deux fois les mêmes tests.
foreach ($document->testsuite as $suite) {
    foreach (array_keys($totals) as $key) {
        $totals[$key] += (int) ($suite[$key] ?? 0);
    }
}

if ($totals['tests'] === 0) {
    refuse('Zéro test exécuté. Une suite vide sort au vert sans rien prouver — c\'est refusé ici.');
}

$summary = sprintf(
    '%d test(s), %d assertion(s), %d échec(s), %d erreur(s)',
    $totals['tests'],
    $totals['assertions'],
    $totals['failures'],
    $totals['errors'],
);

if ($totals['failures'] > 0 || $totals['errors'] > 0) {
    fwrite(STDERR, "\n❌ Tests navigateur en échec — {$summary}.\n");
    exit(1);
}

// Succès démontré. On signale quand même le défaut amont, sinon il devient
// invisible et donc permanent.
if ($pestExitCode !== 0) {
    fwrite(
        STDOUT,
        "\n⚠️  Le runner n'a pas rendu la main (code {$pestExitCode}) et a été tué par la borne.\n"
        ."   Les tests sont VERTS — {$summary} — verdict lu dans le rapport JUnit.\n"
        ."   Défaut amont connu : pestphp/pest-plugin-browser, voir ADR-0013.\n",
    );
} else {
    fwrite(STDOUT, "\n✅ Tests navigateur verts — {$summary}.\n");
}

exit(0);
