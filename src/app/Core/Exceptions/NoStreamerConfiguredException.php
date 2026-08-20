<?php

declare(strict_types=1);

namespace App\Core\Exceptions;

use RuntimeException;

/**
 * Levée quand la table `streamers` est vide alors qu'une requête a besoin du
 * contexte tenant (Pattern C — ADR-0002).
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CETTE CLASSE EXISTE PLUTÔT QU'UN `firstOrFail()`
 *
 * `SetCurrentStreamer` faisait `Streamer::query()->orderBy('id')->firstOrFail()`
 * et son docblock annonçait un échec « fail-loud ». C'était faux :
 * `ModelNotFoundException` est convertie par le handler Laravel en **404**,
 * strictement indiscernable de « cette page n'existe pas ».
 *
 * Constaté le 2026-07-30 sur la stack réelle : base de dev non semée → `/`
 * répondait 404, `/up` répondait 200 (hors groupe `web`). Le diagnostic coûtait
 * cher précisément parce que le symptôme ressemblait à un problème de routage,
 * et rien dans les logs ne disait le contraire. Entrée OUVERTE de
 * `deferred-work.md` depuis cette date.
 *
 * Ce qui a rendu la correction urgente (revue de la Story 1.10a, 2026-08-10) :
 * le panel `/admin` en dépend désormais. Ses pages s'affichent hors du groupe
 * `web`, mais toute INTERACTION passe par l'endpoint de mise à jour de
 * Livewire, qui, lui, est dans `web`. Sur une base migrée non semée, la page de
 * connexion s'affichait donc en 200 et la connexion échouait en 404 : une
 * impasse de déploiement, sur la seule surface d'authentification du produit.
 *
 * ⚠️ Un 500 anonyme ne vaudrait guère mieux qu'un 404. Ce qui rend l'échec
 * exploitable, c'est que le message nomme la commande qui répare — et un test
 * le garde (`TenancyPatternCTest`).
 *
 * @see docs/adr/ADR-0002-rls-not-enabled-v1.md
 */
final class NoStreamerConfiguredException extends RuntimeException
{
    /**
     * The table itself is missing — migrations were never run.
     *
     * Without this branch the resolver hands out a bare `QueryException`: a 500
     * with no remedy in it, which is the exact diagnosis cost this class exists
     * to remove. « Table vide » and « pas migré » look identical from a browser
     * and need different commands. Review finding Q23, 2026-08-20.
     */
    public static function migrationsMissing(): self
    {
        return new self(
            'La table `streamers` n\'existe pas : les migrations n\'ont jamais été exécutées, '
            . "donc le contexte tenant (ADR-0002, Pattern C) ne peut pas être résolu.\n"
            . 'Réparer : `php artisan migrate --seed` (ou `make fresh` en développement).',
        );
    }

    public static function make(): self
    {
        return new self(
            'Aucun streamer en base : le contexte tenant (ADR-0002, Pattern C) ne peut pas être '
            . 'résolu, et toute route du groupe `web` est donc hors service — y compris les '
            . "interactions du panel /admin.\n"
            . 'Réparer : `php artisan db:seed` (ou `make fresh` en développement), qui sème le '
            . 'streamer par `StreamerSeeder`.',
        );
    }
}
