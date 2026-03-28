<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;
use Rector\Set\ValueObject\LevelSetList;
use Rector\Set\ValueObject\SetList;
use RectorLaravel\Set\LaravelSetList;
use Rector\TypeDeclaration\Rector\ClassMethod\AddVoidReturnTypeWhereNoReturnRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddReturnTypeDeclarationRector;

return static function (RectorConfig $rectorConfig): void {
    $rectorConfig->paths([
        __DIR__ . '/app',
        __DIR__ . '/config',
        __DIR__ . '/database',
        __DIR__ . '/routes',
        __DIR__ . '/tests',
    ]);

    // Règles spécifiquement utiles pour PHPStan niveau 8+
    $rectorConfig->rules([
        AddVoidReturnTypeWhereNoReturnRector::class,
        AddReturnTypeDeclarationRector::class,
    ]);

    // Sets optimisés pour PHPStan
    $rectorConfig->sets([
        LevelSetList::UP_TO_PHP_84,
        LaravelSetList::LARAVEL_120,
        LaravelSetList::LARAVEL_CODE_QUALITY,
        SetList::CODE_QUALITY,
        SetList::TYPE_DECLARATION,
        SetList::DEAD_CODE,
    ]);

    $rectorConfig->skip([
        __DIR__ . '/bootstrap',
        __DIR__ . '/storage',
        __DIR__ . '/vendor',
        __DIR__ . '/node_modules',
        __DIR__ . '/database/migrations',
    ]);

    $rectorConfig->importNames();
    $rectorConfig->parallel();
    
    // Lien avec PHPStan config si elle existe
    if (file_exists(__DIR__ . '/phpstan.neon')) {
        $rectorConfig->phpstanConfig(__DIR__ . '/phpstan.neon');
    }
};
