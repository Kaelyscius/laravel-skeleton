<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Core\Models\Streamer;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Streamer>
 */
class StreamerFactory extends Factory
{
    /**
     * @var class-string<Streamer>
     */
    protected $model = Streamer::class;

    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'name' => $this->faker->name(),
            'tagline' => $this->faker->sentence(4),
            'bio_fr' => $this->faker->paragraph(),
            'bio_en' => $this->faker->paragraph(),
            'photo_url' => $this->faker->imageUrl(),
            'cta_text' => 'Suivre sur Twitch',
            'cta_url' => $this->faker->url(),
            'twitter_handle' => $this->faker->userName(),
            'discord_url' => $this->faker->url(),
        ];
    }
}
