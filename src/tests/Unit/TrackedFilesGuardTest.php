<?php

declare(strict_types=1);

use Tests\Support\RepoFile;

/*
|------------------------------------------------------------------------------
| `scripts/assert-tracked-files.sh` — son propre périmètre est-il gardé ?
|------------------------------------------------------------------------------
|
| 🔴 RELEVÉ EN REVUE 2 : retirer `"tests"` du tableau `GUARDED` était INVISIBLE
| pour la suite entière. Or ce répertoire est celui que la story 2.4 vient
| d'ajouter — les tests Bats du E2E vivent hors de `src/`, parce qu'ils pilotent
| Docker et l'hôte, que le conteneur php ne voit pas. Un `.gitignore` trop large
| les retirerait d'un clone sans que rien ne le dise, ce qui est LITTÉRALEMENT le
| mode de défaillance que ce script existe pour attraper.
|
| ⚖️ Le script lui-même ne peut pas être exécuté depuis le conteneur : il
| interroge l'index git, et `/var/www/html` n'est pas un dépôt (mesuré :
| `git check-ignore` y rend 128). On garde donc sa CONFIGURATION, qui est la
| partie qu'un éditeur distrait peut casser sans le savoir.
|
*/

it('protège les répertoires dont TOUT le contenu doit se retrouver dans un clone', function (): void {
    $script = RepoFile::read('scripts/assert-tracked-files.sh');

    /*
     * Le tableau `GUARDED=( … )`, isolé pour ne pas confondre avec la prose.
     *
     * ⚠️ La parenthèse fermante est cherchée EN DÉBUT DE LIGNE, et ce n'est pas
     * du zèle : les commentaires du tableau contiennent eux-mêmes des
     * parenthèses. Un `strpos($script, ')')` naïf tronquait le bloc AVANT la
     * dernière entrée — donc juste avant « tests », celle que ce test existe
     * pour garder. Vu rouge en écrivant ce test.
     */
    expect(preg_match('/GUARDED=\((.*?)\n\)/s', $script, $matches))
        ->toBe(1);

    $block = $matches[1] ?? '';

    // Anti-vacuité : un bloc vide satisferait toutes les assertions par
    // absence de sujet.
    expect($block)
        ->not->toBe('');

    foreach ([
        '.github',
        'docs',
        'scripts',
        'src/app',
        'src/config',
        'src/database',
        'src/resources',
        'src/routes',
        'src/tests',
        // Story 2.4 : les tests shell du E2E d'installation.
        'tests',
    ] as $guarded) {
        expect($block)
            ->toContain('"' . $guarded . '"');
    }
});

it('n’affaiblit son garde-fou que par la liste d’exceptions PRÉVUE pour ça', function (): void {
    // Anti-vacuité du test précédent : si le script n'avait plus de motif
    // d'exception, on pourrait croire le périmètre intact alors qu'il serait
    // contourné ailleurs.
    expect(RepoFile::read('scripts/assert-tracked-files.sh'))
        ->toContain('ALLOWED_REGEX=');
});
