<?php

declare(strict_types=1);

namespace Tests\Unit;

use PHPUnit\Framework\TestCase;
use ReflectionClass;

/**
 * Garde l'isolation de la couche unitaire.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * CE QUE CE FICHIER CONTENAIT AVANT
 *
 * Le stub de scaffolding `test_that_true_is_true()` : `assertTrue(true)`.
 * PHPStan le signalait au niveau 10 (« will always evaluate to true »), et il
 * tombe sous la règle du projet — un test qui ne peut pas rougir n'est pas un
 * test. Il a été remplacé, pas supprimé : le fichier garde désormais un
 * invariant réel.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * L'INVARIANT
 *
 * `tests/Pest.php` ne lie `Tests\TestCase` qu'aux répertoires Feature et
 * Browser. Les tests unitaires doivent donc étendre le TestCase nu de PHPUnit
 * et ne JAMAIS démarrer Laravel.
 *
 * Si quelqu'un ajoutait `'Unit'` à ce binding, la suite unitaire deviendrait
 * silencieusement une suite d'intégration : toujours verte, mais démarrant
 * l'application, touchant la base, et perdant la propriété qui justifie son
 * existence. Rien ne l'aurait signalé — les tests auraient juste ralenti.
 */
final class ExampleTest extends TestCase
{
    public function test_unit_tests_never_boot_the_laravel_application(): void
    {
        $parents = class_parents(new ReflectionClass(self::class)->getName());

        $this->assertNotFalse($parents, 'Impossible de résoudre la chaîne d\'héritage.');
        $this->assertArrayNotHasKey(
            \Tests\TestCase::class,
            $parents,
            'Un test unitaire hérite de Tests\TestCase : la couche unitaire démarre désormais Laravel. '
            . 'Vérifier le binding de tests/Pest.php — il ne doit couvrir que Feature et Browser.',
        );
    }
}
