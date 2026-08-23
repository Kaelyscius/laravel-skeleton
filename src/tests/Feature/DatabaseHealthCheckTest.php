<?php

declare(strict_types=1);

use App\HealthChecks\DatabaseHealthCheck;
use Illuminate\Database\Events\QueryExecuted;
use Illuminate\Support\Facades\DB;
use Spatie\Health\Enums\Status;
use Tests\Support\UnreachableBackends;

/*
|------------------------------------------------------------------------------
| `DatabaseHealthCheck` — la classe que la story 2.4 devait réutiliser « telle
| quelle », et qui n'avait AUCUN test propre (relevé en revue 1).
|------------------------------------------------------------------------------
|
| 🔴 LA PREUVE QUE LE TROU ÉTAIT RÉEL : la campagne de mutation du premier jet
| a exécuté « rétablir le `RESET` inconditionnel » et l'a vue **VERTE**. Le
| correctif de coût n'était gardé par rien. Ce fichier le fige DANS LES DEUX
| SENS, et gèle aussi le portillon de joignabilité.
|
| ⚖️ L'OBSERVABLE EST LE NOMBRE DE TENTATIVES D'OUVERTURE DE PDO, pas une
| durée. Une durée serait bruyante et un `DB::listen` ne voit que les requêtes
| RÉUSSIES — donc rien, précisément dans le cas qu'on veut mesurer. Le PDO de
| la connexion est remplacé par une closure qui COMPTE puis lève.
|
| ⚠️ L'exception levée est délibérément une exception que Laravel ne classe PAS
| comme « connexion perdue » (`DetectsLostConnections`) : sinon le framework
| rejouerait la connexion et le compteur cesserait d'être déterministe.
|
*/

/**
 * Remplace le PDO de la connexion par défaut par un compteur qui échoue.
 *
 * @param  int  $attempts  compteur, passé par référence
 */
function databaseHealthCheckCountingPdo(int &$attempts): void
{
    DB::connection()
        ->setPdo(function () use (&$attempts): never {
            $attempts++;

            throw new PDOException('SQLSTATE[42501]: Insufficient privilege');
        });
}

it('émet le RESET quand le SET a abouti', function (): void {
    $statements = [];

    DB::listen(function (QueryExecuted $query) use (&$statements): void {
        $statements[] = $query->sql;
    });

    $result = (new DatabaseHealthCheck())->run();

    expect($result->status->equals(Status::ok()))
        ->toBeTrue();

    // Anti-vacuité : le SET doit avoir été VU, sinon « le RESET suit le SET »
    // serait vrai parce que ni l'un ni l'autre n'a eu lieu.
    expect($statements)
        ->toContain('SET statement_timeout = 2000');
    expect($statements)
        ->toContain('RESET statement_timeout');
});

it('n’émet PAS de RESET quand le SET a échoué — une session sans réglage n’en a pas besoin', function (): void {
    // 🔴 SANS CE TEST, LE CORRECTIF DE COÛT N'EST GARDÉ PAR RIEN. Mesuré sur le
    // premier jet : une base injoignable payait une tempête de reconnexions
    // COMPLÈTE dans le `finally`, pour restaurer une session qui n'a jamais
    // existé — un tiers du coût de la sonde, au moment précis où `/health`
    // doit répondre vite.
    $attempts = 0;
    databaseHealthCheckCountingPdo($attempts);

    $result = (new DatabaseHealthCheck())->run();

    expect($result->status->equals(Status::failed()))
        ->toBeTrue();

    // UNE tentative : le `SET`. Deux signifierait que le `finally` a rejoué.
    expect($attempts)
        ->toBe(1);
});

it('lit le RETOUR de statement() — et cette branche n’est PAS atteignable ici, c’est écrit', function (): void {
    /*
     * ⚠️ CE TEST NE PROUVE PAS CE QU'ON AIMERAIT, ET LE DIRE VAUT MIEUX QUE DE
     * LAISSER CROIRE.
     *
     * `Connection::statement()` rend le booléen de `PDOStatement::execute()`,
     * qui peut valoir `false` SANS lever — c'est pourquoi la sonde lit le
     * RETOUR plutôt que de poser `true` après un appel sans exception.
     *
     * ⛔ Mais dans CETTE pile, la branche est INATTEIGNABLE :
     * `Connector::$options` (framework) impose
     * `PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION`, donc un `execute()` en
     * échec LÈVE au lieu de rendre `false`. Et `pretend()` ne la reproduit pas
     * non plus : en simulation, `statement()` rend `true` sans rien exécuter —
     * mesuré, ce test échouait quand il prétendait le contraire.
     *
     * Ce qui est donc figé ici, c'est la seule chose vraie : sous
     * `ERRMODE_EXCEPTION`, un `SET` qui ABOUTIT rend `true`. La lecture du
     * retour reste une défense écrite pour un pilote configuré autrement — non
     * gardée, et dite comme telle plutôt que comptée dans les mutations rouges.
     */
    expect(DB::connection()->getPdo()->getAttribute(PDO::ATTR_ERRMODE))
        ->toBe(PDO::ERRMODE_EXCEPTION);

    expect(DB::connection()->statement('SET statement_timeout = 2000'))
        ->toBeTrue();
});

it('le PORTILLON coupe AVANT d’ouvrir la moindre connexion', function (): void {
    // ⛔ C'est la borne exigée par la matrice gelée : une seule tentative, et
    // ici même pas une — le portillon refuse sur un port fermé avant que le
    // pilote n'entre en jeu. Retirer le portillon fait repartir le compteur.
    UnreachableBackends::asDefaultDatabase();

    $attempts = 0;
    databaseHealthCheckCountingPdo($attempts);

    $result = (new DatabaseHealthCheck())->run();

    expect($result->status->equals(Status::failed()))
        ->toBeTrue();
    expect($result->getShortSummary())
        ->toContain('portillon');
    expect($attempts)
        ->toBe(0);
});
