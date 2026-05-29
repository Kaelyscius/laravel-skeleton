<?php

declare(strict_types=1);

namespace App\Core\Support;

use App\Core\Models\Streamer;

/**
 * Request-scoped tenant context — tenancy v1 mono-streamer (Pattern C, ADR-0002).
 *
 * Resolved per HTTP request by the SetCurrentStreamer middleware, which binds a
 * concrete instance into the container via app()->instance(). Outside a request
 * (console, or a route missing the middleware) the container's default binding
 * is fail-loud: resolving CurrentStreamer throws (see CoreServiceProvider).
 *
 * Consumed by BelongsToStreamerScope (injects WHERE streamer_id = id()) and by
 * tenant-aware components (Press Kit Epic 8, CTAs Epic 5) which read streamer().
 */
final class CurrentStreamer
{
    public function __construct(
        private readonly Streamer $streamer
    ) {
    }

    public function id(): int
    {
        return $this->streamer->id;
    }

    public function streamer(): Streamer
    {
        return $this->streamer;
    }
}
