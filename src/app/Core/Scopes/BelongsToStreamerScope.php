<?php

declare(strict_types=1);

namespace App\Core\Scopes;

use App\Core\Support\CurrentStreamer;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

/**
 * Global scope that confines every query on a business model to the current
 * streamer (tenancy v1 mono-streamer, Pattern C — ADR-0002, architecture §3.4).
 *
 * Registered automatically by the BelongsToStreamer trait. The column is
 * table-qualified to stay unambiguous once joins appear (Epic 6 archive).
 * Resolving CurrentStreamer is fail-loud: a query built without the tenant
 * middleware having run throws rather than leaking every row.
 *
 * @implements Scope<Model>
 */
class BelongsToStreamerScope implements Scope
{
    /**
     * @param  Builder<Model>  $builder
     */
    public function apply(Builder $builder, Model $model): void
    {
        $builder->where(
            $model->getTable() . '.streamer_id',
            app(CurrentStreamer::class)->id(),
        );
    }
}
