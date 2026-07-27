<?php

declare(strict_types=1);

use Symplify\EasyCodingStandard\Config\ECSConfig;

// Migré vers l'API fluide `ECSConfig::configure()`. L'ancien format
// `return function (ECSConfig $ecsConfig): void {}` émettait un avertissement de
// dépréciation à chaque exécution, qui polluait notamment la sortie JSON
// consommée par le ratchet qualité (scripts/quality-ratchet.sh).
//
// Jeu de règles strictement équivalent à la version précédente :
// SPACES + ARRAY + DOCBLOCK + NAMESPACES + COMMENTS + PSR_12.
return ECSConfig::configure()
    ->withPaths([
        __DIR__ . '/app',
        __DIR__ . '/config',
        __DIR__ . '/database',
        __DIR__ . '/routes',
        __DIR__ . '/tests',
    ])
    ->withSkip([
        __DIR__ . '/bootstrap',
        __DIR__ . '/storage',
        __DIR__ . '/vendor',
        __DIR__ . '/node_modules',
    ])
    ->withPreparedSets(
        psr12: true,
        arrays: true,
        comments: true,
        docblocks: true,
        spaces: true,
        namespaces: true,
    );
