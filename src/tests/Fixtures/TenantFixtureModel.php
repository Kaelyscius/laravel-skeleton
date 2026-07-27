<?php

declare(strict_types=1);

namespace Tests\Fixtures;

use App\Core\Concerns\BelongsToStreamer;
use Illuminate\Database\Eloquent\Model;

/**
 * Test-only model standing in for a future business model (e.g. Article, Epic 5)
 * to prove the BelongsToStreamer mechanism without depending on any module. Its
 * table `tenant_fixtures` is built on the fly in the test's beforeEach — there is
 * deliberately no migration for it.
 *
 * @property int $streamer_id
 * @property \App\Core\Models\Streamer|null $streamer
 */
class TenantFixtureModel extends Model
{
    use BelongsToStreamer;

    protected $table = 'tenant_fixtures';

    public $timestamps = false;

    /**
     * @var list<string>
     */
    protected $guarded = [];
}
