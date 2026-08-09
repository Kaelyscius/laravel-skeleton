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
| ⛔ CE TEST NE VÉRIFIE PAS QUE LA BONNE POLICE S'AFFICHE, ET IL NE LE POURRA
| JAMAIS — MÊME MAINTENANT QUE LES IBM PLEX SONT SELF-HOSTÉES (Story 1.9).
|
| `getComputedStyle` rend la valeur CALCULÉE de `font-family`, c'est-à-dire la
| PILE DÉCLARÉE. Elle contient « IBM Plex Sans » parce que `tokens.css` l'y a
| écrit en Story 1.8 ; elle la contiendrait tout autant si IBM Plex n'existait
| pas au monde. Ce test était VERT du 2026-08-06 au 2026-08-09 sans qu'un seul
| woff2 n'existe dans le dépôt — c'est d'ailleurs cette observation qui a fait
| requalifier l'AC de preuve d'origine de la 1.9, dont l'énoncé demandait
| exactement cette lecture.
|
| ⚠️ NE PAS le « renforcer » pour lui faire garder le self-hosting : la preuve
| que les faces sont CHARGÉES vit dans tests/Browser/FontsTest.php, par
| énumération de `document.fonts`. Ce test-ci garde autre chose, et le garde
| bien : que la valeur *calculée par le navigateur* pour `font-family` descend
| du token `--font-sans` de `tokens.css`.
|
| C'est exactement le doute nommé par ADR-0011 : `--font-sans` porte le même nom
| que la variable de thème Tailwind qu'il alimente, donc `@theme inline` émet
| `--font-sans: var(--font-sans)`. Ça ne tient que parce que `tokens.css` est
| importé sans `layer()`. Si la cascade n'est pas celle qu'on croit, la valeur
| calculée sera la pile système — et layer-ifier `tokens.css` un jour ferait
| tomber typo et motion en « guaranteed-invalid » SANS erreur de build ni erreur
| console. C'est ce que ce test attrape, et lui seul dans un vrai moteur.
|
| `toContain()` est proscrit : il est variadique sur les needles, donc
| `->not->toContain('a', 'message')` passe toujours. Deux garde-fous de la
| Story 1.8 sont morts ainsi.
*/

it('resolves --font-sans through the real browser cascade', function (): void {
    Streamer::factory()->create();

    $evaluated = visit('/')
        ->script('getComputedStyle(document.body).fontFamily');

    // `script()` renvoie `mixed`. On resserre le type ICI plutôt que de caster
    // à chaque usage : si le navigateur ne renvoie pas une chaîne, l'échec doit
    // dire « pas de valeur calculée » et non produire un « (string) null » vide
    // sur lequel le message d'erreur serait illisible.
    expect(is_string($evaluated))
        ->toBeTrue('script() n\'a pas renvoyé une chaîne : aucune valeur calculée à comparer.');

    $family = is_string($evaluated) ? $evaluated : '';

    expect(str_contains($family, 'IBM Plex Sans'))
        ->toBeTrue("font-family calculée = [{$family}] — le token --font-sans ne gouverne pas la cascade.");
});
