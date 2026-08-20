<?php

declare(strict_types=1);

use App\Core\Models\Streamer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\HttpProbe;

uses(RefreshDatabase::class);

/**
 * Story 1.10a — AC7 : la CSP sur le panel — on MESURE, puis on met le
 * commentaire d'accord avec la mesure.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⚠️ POURQUOI CES TESTS FORCENT `csp.enabled` À `true`
 *
 * Le dépôt porte `CSP_ENABLED=false` (`src/.env:117` et `.env.example:142`) —
 * arbitrage PO du 2026-08-09, reconduit : cette story MESURE la CSP, elle ne
 * l'allume pas. Un test écrit sans forcer le drapeau serait donc vert PAR
 * EXTINCTION : « /admin ne porte pas d'en-tête CSP » serait vrai parce que
 * PERSONNE n'en porte, pas parce que le panel échappe au groupe `web`.
 *
 * C'est littéralement la leçon de la Story 1.9 (« un test qui n'active pas ce
 * qu'il observe est vert par extinction »), appliquée à l'endroit où le piège
 * était armé.
 *
 * Forcer par `config()->set()` est fidèle ici, et ce n'est pas un raccourci :
 * `Spatie\Csp\AddCspHeaders::handle()` lit `config('csp.enabled')` À CHAQUE
 * REQUÊTE (vérifié dans `vendor/`, pas supposé). Le drapeau est donc réellement
 * consulté sur le chemin qu'on exerce.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * LA MESURE (2026-08-09)
 *
 * `bootstrap/app.php` appende `AddCspHeaders` au groupe `web` — et à lui seul.
 * Filament construit sa propre pile de middleware et ne traverse pas ce groupe.
 * Résultat observé, CSP allumée :
 *
 *   GET /_layouts   (route `web`)  → Content-Security-Policy : PRÉSENT
 *   GET /admin/login (panel)       → Content-Security-Policy : ABSENT
 *
 * La mise en garde portée par `bootstrap/app.php` — « Future story wiring
 * Filament admin (Story 1.10) must either customize the policy or exclude admin
 * routes from CSP » — N'EST PAS SANS OBJET, et la rédaction précédente de ce
 * fichier se trompait en l'affirmant. Elle généralisait depuis `GET /admin/login`,
 * c'est-à-dire depuis la seule route du panel qui ne porte pas son trafic. Les
 * PAGES du panel sont hors du groupe `web` ; les INTERACTIONS, elles, passent par
 * l'endpoint de mise à jour de Livewire, qui y est. Finding Q3, revue du
 * 2026-08-20. Le commentaire de `bootstrap/app.php` est corrigé dans le même
 * commit (hygiène documentaire, `03-boucle-qualite.md` §Étape 6).
 *
 * ⚠️ Ce que ces tests figent est un CONSTAT, pas un souhait. Le jour où la CSP
 * sera allumée (hors périmètre ici), il faudra décider si le panel doit en
 * porter une — et ce sera une décision, pas un effet de bord. Le second test
 * ci-dessous rougira si quelqu'un ajoute `AddCspHeaders` à la pile du panel
 * sans passer par cette décision.
 */

/**
 * Force la CSP pour la durée d'un test, et rend la valeur de l'en-tête observée.
 */
function cspHeaderOn(string $uri): ?string
{
    config()->set('csp.enabled', true);

    return HttpProbe::get($uri)->headers->get('Content-Security-Policy');
}

it('really emits a CSP header on a web-group route once the flag is forced on', function (): void {
    // ⚠️ LE TÉMOIN, ET IL N'EST PAS DÉCORATIF.
    //
    // Sans lui, le test suivant (« pas d'en-tête sur /admin ») serait satisfait
    // par une CSP simplement éteinte — c'est-à-dire vert par extinction, pour
    // la mauvaise raison. Celui-ci prouve que le drapeau forcé produit vraiment
    // un en-tête quelque part.

    /*
     * ⛔ CE SEMIS N'EST PAS DÉCORATIF NON PLUS — il conditionne tout le témoin.
     *
     * `/_layouts` traverse le groupe `web`, donc `SetCurrentStreamer`, qui lève
     * `NoStreamerConfiguredException` sur une base sans streamer — le correctif
     * « fail-loud » livré par CETTE MÊME STORY le 2026-08-10. La requête part
     * alors en 500, et comme `AddCspHeaders` est APPENDÉ au groupe `web` (donc
     * exécuté après), il ne pose jamais son en-tête : le témoin observait `null`
     * et accusait la CSP d'un échec qui venait de la couche tenancy.
     *
     * `LayoutsTest` sème pour cette raison exacte, en le disant (l. 653-659).
     * Constaté rouge ici le 2026-08-20, avant ce semis.
     */
    Streamer::factory()->create();

    $header = cspHeaderOn('/_layouts');

    expect($header)
        ->not->toBeNull(
            'CSP forcée à true mais aucune route `web` ne porte l\'en-tête : '
                . 'le témoin ne témoigne de rien, et le test du panel serait vert par extinction.',
        );
    expect($header)
        ->not->toBe('');
});

it('emits no CSP header on the panel PAGES, which are served outside the web group', function (): void {
    $header = cspHeaderOn('/admin/login');

    expect($header)
        ->toBeNull(
            'Le panel porte un en-tête Content-Security-Policy : la pile de middleware de Filament '
                . 'a changé, ou AddCspHeaders y a été ajouté. La mise en garde de bootstrap/app.php '
                . 'redevient alors pertinente — et il faut TRANCHER une politique, pas subir celle du groupe web.',
        );
});

it('emits a CSP header on the endpoint that actually carries the panel\'s traffic', function (): void {
    /*
     * 🔴 LA ROUTE QUE LA PREMIÈRE MESURE N'AVAIT PAS REGARDÉE — finding Q3.
     *
     * Conclure « le panel ne porte pas la CSP » depuis `GET /admin/login` revient
     * à mesurer la vitrine et à conclure sur l'atelier. Les pages du panel sont
     * servies par la pile propre de Filament, hors du groupe `web` ; mais toute
     * interaction — à commencer par la soumission du formulaire de connexion —
     * passe par l'endpoint de mise à jour de Livewire, unique pour l'application,
     * qui est dans `web`, donc derrière `AddCspHeaders`.
     *
     * MESURÉ le 2026-08-20, CSP forcée, sur la pile qui tourne :
     *   GET  /admin/login            → ABSENTE
     *   POST /livewire-<hash>/update → PRÉSENTE
     *
     * Ce test fige la mesure. Il rougira le jour où quelqu'un exclura l'endpoint
     * Livewire de la CSP — ce qui est peut-être la bonne décision, mais qui doit
     * être une décision, pas un effet de bord.
     */
    config()
        ->set('csp.enabled', true);
    Streamer::factory()->create();

    $header = HttpProbe::post(
        HttpProbe::livewireUpdateUri(),
        '{"components":[]}',
        [
            'HTTP_X_LIVEWIRE' => '1',
            'CONTENT_TYPE' => 'application/json',
        ],
    )->headers->get('Content-Security-Policy');

    expect($header)
        ->not->toBeNull(
            'L\'endpoint qui porte TOUTES les interactions du panel ne porte pas la CSP : '
                . 'soit la portée a changé, soit quelqu\'un l\'en a exclu sans le décider.',
        );
});

it('keeps the panel reachable with the CSP flag forced on', function (): void {
    // Le pendant utile du test précédent : « pas d'en-tête » ne doit pas
    // vouloir dire « pas de réponse ». Une CSP allumée ne casse pas le panel.
    config()
        ->set('csp.enabled', true);

    expect(HttpProbe::get('/admin/login')->getStatusCode())
        ->toBe(200, 'Le panel ne répond plus une fois la CSP allumée.');
});
