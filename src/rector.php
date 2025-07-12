<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;
use Rector\Set\ValueObject\LevelSetList;
use Rector\Set\ValueObject\SetList;
use Rector\Laravel\Set\LaravelSetList;
use Rector\TypeDeclaration\Rector\ClassMethod\AddVoidReturnTypeWhereNoReturnRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddReturnTypeDeclarationRector;
use Rector\TypeDeclaration\Rector\Property\TypedPropertyFromStrictConstructorRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddMethodCallBasedStrictParamTypeRector;
use Rector\TypeDeclaration\Rector\Property\AddPropertyTypeDeclarationRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ParamTypeByMethodCallTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ParamTypeByParentCallTypeRector;
use Rector\CodeQuality\Rector\Class_\InlineConstructorDefaultToPropertyRector;
use Rector\CodeQuality\Rector\If_\ExplicitBoolCompareRector;
use Rector\CodeQuality\Rector\Identical\SimplifyBoolIdenticalTrueRector;
use Rector\CodeQuality\Rector\BooleanNot\SimplifyDeMorganBinaryRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUnusedPromotedPropertyRector;
use Rector\DeadCode\Rector\Property\RemoveUnusedPrivatePropertyRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUnusedPrivateMethodRector;

return static function (RectorConfig $rectorConfig): void {
    $rectorConfig->paths([
        __DIR__ . '/app',
        __DIR__ . '/config',
        __DIR__ . '/database',
        __DIR__ . '/resources',
        __DIR__ . '/routes',
        __DIR__ . '/tests',
    ]);

    // Règles spécifiquement utiles pour PHPStan niveau 8+
    $rectorConfig->rules([
        // TYPE DECLARATIONS (fixes most PHPStan issues)
        AddVoidReturnTypeWhereNoReturnRector::class,
        AddReturnTypeDeclarationRector::class,
        TypedPropertyFromStrictConstructorRector::class,
        AddMethodCallBasedStrictParamTypeRector::class,
        AddPropertyTypeDeclarationRector::class,
        ParamTypeByMethodCallTypeRector::class,
        ParamTypeByParentCallTypeRector::class,

        // CODE QUALITY (helps with strict analysis)
        InlineConstructorDefaultToPropertyRector::class,
        ExplicitBoolCompareRector::class,
        SimplifyBoolIdenticalTrueRector::class,
        SimplifyDeMorganBinaryRector::class,

        // DEAD CODE REMOVAL
        RemoveUnusedPromotedPropertyRector::class,
        RemoveUnusedPrivatePropertyRector::class,
        RemoveUnusedPrivateMethodRector::class,
    ]);

    // Sets optimisés pour PHPStan
    $rectorConfig->sets([
        LevelSetList::UP_TO_PHP_84,
        RectorLaravel\Set\LaravelSetList::LARAVEL_120,
        LaravelSetList::LARAVEL_CODE_QUALITY,
        SetList::CODE_QUALITY,
        SetList::TYPE_DECLARATION,
        SetList::DEAD_CODE,
        SetList::STRICT_BOOLEANS,
        SetList::PRIVATIZATION,
        SetList::EARLY_RETURN,
        SetList::INSTANCEOF,
    ]);

    $rectorConfig->skip([
        __DIR__ . '/bootstrap',
        __DIR__ . '/storage',
        __DIR__ . '/vendor',
        __DIR__ . '/node_modules',
        __DIR__ . '/database/migrations',
        __DIR__ . '/config/app.php',

        // Skip specific rules that might be too aggressive for Laravel
        AddReturnTypeDeclarationRector::class => [
            __DIR__ . '/app/Http/Controllers',  // Controllers often have complex return types
        ],
    ]);

    // Configuration optimisée
    $rectorConfig->importNames();
    $rectorConfig->importShortClasses();
    $rectorConfig->parallel();

    // Lien avec PHPStan config si elle existe
    if (file_exists(__DIR__ . '/phpstan.neon')) {
        $rectorConfig->phpstanConfig(__DIR__ . '/phpstan.neon');
    }
};
