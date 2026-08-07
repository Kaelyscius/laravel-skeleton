<?php

declare(strict_types=1);

use App\Core\Models\Streamer;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

/*
|--------------------------------------------------------------------------
| Spike — le token gouverne-t-il réellement la cascade ?
|--------------------------------------------------------------------------
|
| Ce test ne vérifie PAS que la bonne police s'affiche : les IBM Plex ne sont
| pas encore self-hostées (Story 1.9, en fin de séquence). Il vérifie que la
| valeur *calculée par le navigateur* pour `font-family` descend bien du token
| `--font-sans` de `tokens.css`.
|
| C'est exactement le doute nommé par ADR-0011 : `--font-sans` porte le même nom
| que la variable de thème Tailwind qu'il alimente, donc `@theme inline` émet
| `--font-sans: var(--font-sans)`. Ça ne tient que parce que `tokens.css` est
| importé sans `layer()`. Si la cascade n'est pas celle qu'on croit, la valeur
| calculée sera la pile système — et on l'apprend AVANT que la Story 1.9 ne soit
| déclarée verte sur une police système.
|
| `toContain()` est proscrit : il est variadique sur les needles, donc
| `->not->toContain('a', 'message')` passe toujours. Deux garde-fous de la
| Story 1.8 sont morts ainsi.
*/

it('resolves --font-sans through the real browser cascade', function (): void {
    Streamer::factory()->create();

    $family = visit('/')
        ->script('getComputedStyle(document.body).fontFamily');

    expect(is_string($family))
        ->toBeTrue('script() n\'a pas renvoyé une chaîne.');

    expect(str_contains((string) $family, 'IBM Plex Sans'))
        ->toBeTrue("font-family calculée = [{$family}] — le token --font-sans ne gouverne pas la cascade.");
});
