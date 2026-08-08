<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Story 1.11 — `social_links` sur la table tenant-root `streamers`.
 *
 * ADR-0012 : les réseaux sociaux sont de la SORTIE (des profils vers lesquels on
 * envoie), configurés par le streamer, jamais codés en dur — un fork-streamer
 * qui n'a pas de TikTok ne doit pas avoir à toucher au code (ADR-0001).
 *
 * `discord_url` reste une colonne séparée, et c'est délibéré : c'est un canal de
 * RETOUR, au rang du CTA. Le mélanger à la liste de sortie diluerait le seul
 * endroit où l'audience revient. Voir Streamer::orderedSocialLinks().
 *
 * Colonne JSON et non table dédiée : v1 mono-streamer (Pattern C, ADR-0002),
 * une poignée de liens ordonnés, aucune requête ne les filtre. Une table serait
 * de la normalisation sans consommateur.
 *
 * `jsonb` et non `json` : sur PostgreSQL, `json` conserve le texte brut tandis
 * que `jsonb` stocke une forme analysée, indexable et déduplicquée. Aucune
 * requête n'en dépend aujourd'hui, mais choisir le type dégradé sur une table
 * neuve coûterait une migration le jour où l'une en dépendra.
 *
 * ⚠️ PAS de `->after('discord_url')` : `modifyAfter` n'existe que dans la
 * grammaire MySQL. Sur PostgreSQL — le seul moteur de ce projet (ADR-0007) —
 * l'appel est ignoré en silence. Écrire une intention que la base n'honore pas,
 * c'est fabriquer un garde-fou décoratif de plus.
 *
 * `cta_text` / `cta_url` existent déjà (migration de la Story 1.3) : rien à
 * ajouter pour eux ici.
 */
return new class() extends Migration {
    public function up(): void
    {
        Schema::table('streamers', function (Blueprint $table): void {
            $table->jsonb('social_links')
                ->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('streamers', function (Blueprint $table): void {
            $table->dropColumn('social_links');
        });
    }
};
