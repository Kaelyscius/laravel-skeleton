<?php

declare(strict_types=1);

namespace Tests\Support;

/**
 * Lecture TYPÉE de la réponse de `/health`.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CETTE CLASSE, ET PAS `$this->getJson('/health')`
 *
 * C'est la raison déjà écrite en tête de `HttpProbe` : dans une closure Pest,
 * PHPStan résout `$this` en `Pest\PendingCalls\TestCall`, donc chaque
 * `$this->getJson()` produit deux à trois erreurs au niveau 10 — la Story 1.10a
 * en avait fabriqué 49 d'un coup, et le ratchet du projet est à 0. La première
 * rédaction de `HealthEndpointTest` en a produit 43, mesurées avant d'être
 * réécrites.
 *
 * `HttpProbe::get()` rend une `Response` typée ; il restait le corps JSON, qui
 * arrive en `mixed`. Cette classe le décode UNE fois et n'expose que des
 * accesseurs typés. Aucune annotation de complaisance n'est nécessaire.
 *
 * ⚠️ Ce n'est pas un contournement de typage : la requête traverse le noyau
 * HTTP réel, pile de middleware comprise — c'est précisément ce qu'il faut pour
 * observer que `/health` est servie HORS du groupe `web`.
 */
final class HealthProbe
{
    /**
     * @param  array<string, mixed>  $payload
     */
    private function __construct(
        public readonly int $status,
        public readonly string $body,
        private readonly array $payload,
    ) {
    }

    /**
     * Interroge `/health` et décode sa réponse.
     */
    public static function probe(): self
    {
        $response = HttpProbe::get('/health');
        $body = (string) $response->getContent();
        $decoded = json_decode($body, true);

        /** @var array<string, mixed> $payload */
        $payload = is_array($decoded) ? $decoded : [];

        return new self($response->getStatusCode(), $body, $payload);
    }

    /**
     * Verdict global (`ok` / `error`), ou `null` si le corps n'en porte pas.
     */
    public function overallStatus(): ?string
    {
        $value = $this->payload['status'] ?? null;

        return is_string($value) ? $value : null;
    }

    /**
     * Clés publiques des sondes, DANS L'ORDRE de la réponse.
     *
     * L'ordre fait partie du contrat gelé par `HealthEndpointTest` : il suit
     * l'enregistrement dans `AppServiceProvider`, donc l'ordre d'exécution —
     * ce qui est ce qu'un lecteur du budget de sonde a besoin de savoir.
     *
     * @return array<int, string>
     */
    public function checkKeys(): array
    {
        return array_map(static fn (int|string $key): string => (string) $key, array_keys($this->checks()));
    }

    /**
     * Statut d'une sonde (`ok` / `error`), ou `null` si elle n'est pas rapportée.
     */
    public function checkStatus(string $key): ?string
    {
        $value = $this->checkField($key, 'status');

        return is_string($value) ? $value : null;
    }

    /**
     * Résumé d'une sonde, ou `null`.
     */
    public function checkSummary(string $key): ?string
    {
        $value = $this->checkField($key, 'summary');

        return is_string($value) ? $value : null;
    }

    /**
     * Durée d'une sonde en millisecondes.
     *
     * ⚠️ `null` a DEUX significations distinctes, et le test doit les
     * distinguer : la sonde n'a pas été jouée (le budget cumulé était épuisé),
     * ou la clé n'existe pas du tout. `hasCheck()` tranche.
     */
    public function checkDurationMs(string $key): ?int
    {
        $value = $this->checkField($key, 'duration_ms');

        return is_int($value) ? $value : null;
    }

    public function hasCheck(string $key): bool
    {
        return array_key_exists($key, $this->checks());
    }

    /**
     * @return array<string, mixed>
     */
    private function checks(): array
    {
        $checks = $this->payload['checks'] ?? null;

        if (! is_array($checks)) {
            return [];
        }

        /** @var array<string, mixed> $checks */
        return $checks;
    }

    private function checkField(string $key, string $field): mixed
    {
        $check = $this->checks()[$key] ?? null;

        if (! is_array($check)) {
            return null;
        }

        return $check[$field] ?? null;
    }
}
