<?php

declare(strict_types=1);

namespace App\Core\Http\Middleware;

use App\Core\Models\Streamer;
use App\Core\Support\CurrentStreamer;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Resolves the current streamer and binds it for the request (Pattern C —
 * ADR-0002, architecture §3.4). Pushed onto the `web` middleware group by
 * CoreServiceProvider.
 *
 * v1 mono-streamer: there is exactly one row (enforced by Story 1.5
 * `tenancy:assert`), so firstOrFail() is correct and fail-loud — an unseeded
 * database surfaces as an explicit error rather than a silent empty tenant.
 *
 * v2+ multi-streamer (Pattern D, ADR-0002) will enrich this with RLS /
 * `SET LOCAL` inside a transaction. NOT implemented here.
 */
class SetCurrentStreamer
{
    /**
     * @param  Closure(Request): Response  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $streamer = Streamer::query()->orderBy('id')->firstOrFail();

        app()
            ->instance(CurrentStreamer::class, new CurrentStreamer($streamer));

        return $next($request);
    }
}
