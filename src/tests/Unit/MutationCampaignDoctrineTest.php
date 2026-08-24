<?php

declare(strict_types=1);

use Tests\Support\RepoFile;

/*
|------------------------------------------------------------------------------
| La doctrine de la campagne de mutation — Story 2.4 (clôture)
|------------------------------------------------------------------------------
|
| 🔴 DEUX RÈGLES ÉTAIENT PRATIQUÉES ET N'ÉTAIENT ÉCRITES NULLE PART.
| « Nommer l'environnement de la mesure » et « inclure un témoin neutre » ne
| vivaient que dans `docs/ETAT.md` — un journal — et dans `ADR-0013` — une
| décision. Ni l'un ni l'autre n'est le document qu'on ouvre pour FAIRE le
| travail : `docs/process/03-boucle-qualite.md` §Étape 5 l'est, et il ne les
| portait pas. Une pratique non écrite se perd au premier contributeur suivant,
| et ces deux-là ont chacune été payées par une story :
|   • l'environnement, par un garde rouge sous GNU coreutils et VERT sous
|     BusyBox `cp` (2.3), puis par un test vert en local et rouge en CI ;
|   • le témoin neutre, parce qu'une campagne sans lui ne distingue pas un
|     garde-fou d'un détecteur de diff.
|
| ⚖️ CE GARDE EST TEXTUEL, ET C'EST DIT. Il ne peut pas vérifier qu'une campagne
| a réellement nommé son environnement — il empêche que la CONSIGNE disparaisse
| en silence du seul document qui la prescrit. C'est le même arbitrage que pour
| les garde-fous de prose de la story 2.3 : un garde sur un texte vaut mieux
| qu'aucun garde sur une règle que plus personne ne lit.
|
*/

/**
 * Le corps de l'Étape 5, isolé de ses voisines.
 */
function etapeCinq(): string
{
    $doc = RepoFile::read('docs/process/03-boucle-qualite.md');

    $debut = strpos($doc, '### Étape 5');
    $fin = strpos($doc, '### Étape 6');

    expect($debut)
        ->not->toBeFalse('L’Étape 5 a disparu de la boucle qualité.');
    expect($fin)
        ->not->toBeFalse('L’Étape 6 a disparu : l’extraction lirait tout le reste du document.');

    return substr($doc, (int) $debut, (int) $fin - (int) $debut);
}

it('prescrit de NOMMER l’environnement de la mesure', function (): void {
    $etape = etapeCinq();

    expect($etape)
        ->toContain('ENVIRONNEMENT de la mesure');

    // La règle est inutile si elle ne dit pas ce qu'un environnement est : les
    // trois que ce dépôt distingue réellement sont nommés.
    expect($etape)
        ->toContain('laravel-app_php');
    expect($etape)
        ->toContain('ubuntu-latest');
    expect($etape)
        ->toContain('BusyBox');
});

it('prescrit un TÉMOIN NEUTRE attendu vert', function (): void {
    $etape = etapeCinq();

    expect($etape)
        ->toContain('TÉMOIN NEUTRE');
    expect($etape)
        ->toContain('attendu VERT');

    // ⛔ ET IL DIT CE QU'UN TÉMOIN ROUGE SIGNIFIE. Sans cette moitié, la règle
    // se lit comme une formalité : c'est le témoin ROUGE qui est la trouvaille.
    expect($etape)
        ->toContain("S'il rougit");
});

it('n’a pas perdu les trois règles antérieures de la campagne', function (): void {
    // Anti-vacuité de l'extraction : si `etapeCinq()` rendait un fragment vide
    // ou tronqué, les deux tests ci-dessus seraient rouges — mais ceux-ci
    // vérifient en plus que l'ajout n'a rien ÉCRASÉ.
    $etape = etapeCinq();

    expect($etape)
        ->toContain('Une mutation à la fois');
    expect($etape)
        ->toContain("Compter ce qu'on rejoue vraiment");
    expect($etape)
        ->toContain('Rejouer la campagne après toute réécriture des tests');
});
