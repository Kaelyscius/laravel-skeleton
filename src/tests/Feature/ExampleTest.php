<?php

namespace Tests\Feature;

use App\Core\Models\Streamer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ExampleTest extends TestCase
{
    use RefreshDatabase;

    /**
     * A basic test example.
     *
     * The `/` route is in the `web` group, now gated by the SetCurrentStreamer
     * tenant middleware (Story 1.4), so a streamer must exist for the request to
     * resolve. Infrastructure liveness lives on `/up` (outside the web group).
     */
    public function test_the_application_returns_a_successful_response(): void
    {
        Streamer::factory()->create();

        $response = $this->get('/');

        $response->assertStatus(200);
    }
}
