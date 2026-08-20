<?php

declare(strict_types=1);

namespace App\Core\Models;

use Database\Factories\StreamerFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * Tenant-root model — tenancy v1 mono-streamer (ADR-0002, architecture §3.4).
 *
 * Single source of truth for streamer-configurable data (tagline, bilingual bios,
 * CTAs, social handles) consumed by tenant-aware components (Press Kit Epic 8,
 * CTAs Epic 5). A fork-streamer overrides these via a Filament SettingsResource
 * — never hardcode a streamer's data in views (ADR-0001).
 *
 * ⚠️ CETTE RESSOURCE N'EXISTE PAS ENCORE, et la référence a été corrigée le
 * 2026-08-09 (Story 1.10a). Le renvoi disait « Story 1.10 » ; la 1.10 a été
 * scindée, et la moitié qui porte la SettingsResource (1.10b) est partie en
 * **Epic 5** — un back-office qui édite des champs que rien n'affiche est un
 * vrai-vert inutile. La Story 1.10a livre le panel `/admin` vide, authentifié
 * et gaté ; elle n'y met aucune ressource.
 *
 * Aujourd'hui, ces colonnes se modifient donc en base ou par un seeder. C'est
 * un état transitoire assumé, pas un oubli.
 *
 * Invariants:
 *  - NO `streamer_id` column: this model IS the streamer.
 *  - Does NOT use the BelongsToStreamer trait (that is for business models).
 *
 * @property int $id
 * @property string $name
 * @property string|null $tagline
 * @property string|null $bio_fr
 * @property string|null $bio_en
 * @property string|null $photo_url
 * @property string|null $cta_text
 * @property string|null $cta_url
 * @property string|null $twitter_handle
 * @property string|null $discord_url
 * @property array<array-key, mixed>|null $social_links
 */
final class Streamer extends Model
{
    /** @use HasFactory<StreamerFactory> */
    use HasFactory;

    /**
     * @var list<string>
     */
    protected $fillable = [
        'name',
        'tagline',
        'bio_fr',
        'bio_en',
        'photo_url',
        'cta_text',
        'cta_url',
        'twitter_handle',
        'discord_url',
        'social_links',
    ];

    /**
     * Outbound social profiles, ordered, as the UI must consume them (ADR-0012).
     *
     * Four invariants live here rather than in a view, so every consumer gets
     * them for free:
     *
     *  1. ZERO hardcoded network. The list is whatever the streamer configured;
     *     a fork with no TikTok never edits code (ADR-0001).
     *  2. Discord is EXCLUDED, even when a streamer pastes it into the list.
     *     Discord is a RETURN channel, ranked with the CTA; letting it appear
     *     among the outbound profiles is exactly the dilution ADR-0012
     *     §"sortie ≠ retour" forbids. The match is on HOST, not on the raw
     *     string: a code review found the first cut compared bytes, so a
     *     trailing slash, an `http://` scheme or a second invite to the same
     *     server walked straight through the guard meant to stop them.
     *  3. Only `http`/`https` survive. A `javascript:` or `data:` URL in an
     *     `href` executes on click, and Blade escaping stops attribute
     *     breakout, not scheme abuse. Today only the streamer writes this
     *     column, directly in the database: la Story 1.10a livre un panel
     *     `/admin` VIDE, et le formulaire Filament qui éditera cette colonne
     *     appartient à la 1.10b, déplacée en Epic 5. Le contrôle ci-dessus est
     *     donc la seule barrière, et il le restera plus longtemps que prévu.
     *  4. Malformed entries are dropped, not rendered half-empty: a link with no
     *     URL is a dead end pretending to be a destination.
     *
     * Values come back TRIMMED: the string that was validated must be the
     * string that reaches the `href`, or they are not the same URL.
     *
     * Ordering is by the optional `order` key, ascending; entries without one
     * fall to the end in their declared order (PHP's sort is stable).
     *
     * @return list<array{label: string, url: string}>
     */
    public function orderedSocialLinks(): array
    {
        $raw = $this->social_links;

        if (! is_array($raw)) {
            return [];
        }

        $discordHost = self::hostOf($this->discord_url);

        /** @var list<array{label: string, url: string, order: int}> $links */
        $links = [];

        foreach ($raw as $entry) {
            if (! is_array($entry)) {
                continue;
            }

            $label = $entry['label'] ?? null;
            $url = $entry['url'] ?? null;
            $order = $entry['order'] ?? null;

            if (! is_string($label) || ! is_string($url)) {
                continue;
            }

            $label = trim($label);
            $url = trim($url);

            if ($label === '' || $url === '') {
                continue;
            }

            $host = self::hostOf($url);

            if ($host === null || ($discordHost !== null && $host === $discordHost)) {
                continue;
            }

            $links[] = [
                'label' => $label,
                'url' => $url,
                // is_numeric, pas is_int : un `order` fait l'aller-retour JSON
                // en "1" ou en 2.0 selon qui l'a écrit, et chacun de ces cas
                // retombait sur PHP_INT_MAX — l'ordre configuré par le streamer
                // était silencieusement ignoré.
                'order' => is_numeric($order) ? (int) $order : PHP_INT_MAX,
            ];
        }

        usort($links, static fn (array $a, array $b): int => $a['order'] <=> $b['order']);

        return array_map(
            static fn (array $link): array => [
                'label' => $link['label'],
                'url' => $link['url'],
            ],
            $links,
        );
    }

    /**
     * Normalised host of an http(s) URL, or null if it is neither.
     *
     * Doubles as the scheme allowlist: anything that is not http/https — a
     * `javascript:` URL, a relative path, a malformed string — has no host here
     * and is therefore dropped by every caller.
     */
    private static function hostOf(?string $url): ?string
    {
        if ($url === null || trim($url) === '') {
            return null;
        }

        $parts = parse_url(trim($url));

        if (! is_array($parts)) {
            return null;
        }

        $scheme = $parts['scheme'] ?? null;
        $host = $parts['host'] ?? null;

        if (! is_string($scheme) || ! in_array(mb_strtolower($scheme), ['http', 'https'], true)) {
            return null;
        }

        if (! is_string($host) || $host === '') {
            return null;
        }

        return mb_strtolower($host);
    }

    /**
     * Explicit factory wiring: the model lives in App\Core\Models\, outside
     * Laravel's default App\Models\ factory-resolution path, so automatic
     * discovery would fail. See StreamerFactory.
     */
    protected static function newFactory(): StreamerFactory
    {
        return StreamerFactory::new();
    }

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'social_links' => 'array',
        ];
    }
}
