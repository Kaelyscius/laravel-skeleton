<?php

declare(strict_types=1);

use Tests\Support\ComposeFile;

/**
 * Smoke test des profils Docker Compose (Story 1.2).
 *
 * Il garde contre la dérive accidentelle : un service qui perd son profil se
 * met à démarrer en production, un service qui en gagne un disparaît du socle.
 *
 * Les anciennes fonctions globales `repoRoot()` / `composeYaml()` ont été
 * remplacées par Tests\Support\{RepoFile, ComposeFile} : elles renvoyaient du
 * `mixed`, ce qui coûtait 17 erreurs PHPStan au niveau 10 dans ce seul fichier,
 * et surtout noyait l'intention sous la plomberie de parsing.
 */
it('declares the 5 essential prod services (no profile) in docker-compose.yml', function (): void {
    expect(ComposeFile::withoutProfile(ComposeFile::services('docker-compose.yml')))
        ->toBe(['apache', 'php', 'postgres', 'postgres-pulse', 'redis']);
});

it('declares dev profile services correctly', function (): void {
    expect(ComposeFile::withProfile(ComposeFile::services('docker-compose.yml'), 'dev'))
        ->toBe(['adminer', 'mailpit', 'node']);
});

it('declares tools profile services correctly', function (): void {
    expect(ComposeFile::withProfile(ComposeFile::services('docker-compose.yml'), 'tools'))
        ->toBe(['dozzle', 'it-tools', 'watchtower']);
});

it('declares dev-extra as redis-commander only (legacy MySQL admin tool dropped — D2)', function (): void {
    $services = ComposeFile::services('docker-compose.yml', 'docker-compose.dev.yml');

    expect(ComposeFile::withProfile($services, 'dev-extra'))
        ->toBe(['redis-commander']);
});

it('isolates the browser runner behind the test profile (ADR-0013)', function (): void {
    // Le runner navigateur embarque Chromium (~1,5 Go) : il ne doit démarrer ni
    // avec `make up-local`, ni avec `make up-prod`. Sans ce test, le sortir du
    // profil `test` ne déclencherait aucun signal.
    expect(ComposeFile::withProfile(ComposeFile::services('docker-compose.yml'), 'test'))
        ->toBe(['test-browser']);
});

it('excludes custom-built images from Watchtower', function (): void {
    expect(ComposeFile::withLabel(
        ComposeFile::services('docker-compose.yml'),
        'com.centurylinklabs.watchtower.enable=false',
    ))
        // `test-browser` (ADR-0013) est bâti depuis docker/php/Dockerfile, stage
        // `test` : image custom, donc exclue de Watchtower comme les trois autres.
        ->toBe(['apache', 'node', 'php', 'test-browser']);
});
