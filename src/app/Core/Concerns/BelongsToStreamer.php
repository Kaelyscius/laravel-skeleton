<?php

declare(strict_types=1);

namespace App\Core\Concerns;

use App\Core\Models\Streamer;
use App\Core\Scopes\BelongsToStreamerScope;
use App\Core\Support\CurrentStreamer;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Tenancy trait for business models (Pattern C — ADR-0002, architecture §3.4).
 *
 * Including this trait (a) registers BelongsToStreamerScope so every query is
 * confined to the current streamer, and (b) auto-fills streamer_id on creation
 * from the request-scoped CurrentStreamer when not set explicitly — a guardrail
 * against orphaned rows. NOT used by the Streamer model itself (it IS the tenant
 * root). The streamer_id column lives on each business table's migration (§4.1),
 * not here.
 *
 * @mixin Model
 */
trait BelongsToStreamer
{
    protected static function bootBelongsToStreamer(): void
    {
        static::addGlobalScope(new BelongsToStreamerScope());

        static::creating(function (Model $model): void {
            if ($model->getAttribute('streamer_id') === null) {
                $model->setAttribute('streamer_id', app(CurrentStreamer::class)->id());
            }
        });
    }

    /**
     * @return BelongsTo<Streamer, $this>
     */
    public function streamer(): BelongsTo
    {
        return $this->belongsTo(Streamer::class);
    }
}
