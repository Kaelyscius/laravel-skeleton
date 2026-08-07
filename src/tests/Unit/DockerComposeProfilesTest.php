<?php

declare(strict_types=1);

// tests/Unit/DockerComposeProfilesTest.php
// Smoke test for Story 1.2 Docker Compose profiles — guards against accidental profile drift across the 11 services.

use Symfony\Component\Yaml\Yaml;

// Guarded against redeclaration: these are global functions loaded across the
// whole tests/Unit suite, so guard them so a future Unit test reusing the names
// cannot trigger a fatal "Cannot redeclare function" error.
if (! function_exists('repoRoot')) {
    function repoRoot(): string
    {
        // The compose files live at the repository root. Resolve it across the two
        // execution layouts this suite runs under:
        //   - host:      src/tests/Unit/ → dirname(__DIR__, 3) is the repo root
        //   - container: src is mounted at /var/www/html and the repo root (where the
        //                compose files live) is mounted read-only at /var/www/project
        foreach ([dirname(__DIR__, 3), '/var/www/project'] as $candidate) {
            if (file_exists($candidate . '/docker-compose.yml')) {
                return $candidate;
            }
        }

        return dirname(__DIR__, 3);
    }
}

if (! function_exists('composeYaml')) {
    function composeYaml(string $file): array
    {
        $path = repoRoot() . '/' . $file;
        expect(file_exists($path))
            ->toBeTrue("Missing {$file}");

        return Yaml::parseFile($path);
    }
}

it('declares the 5 essential prod services (no profile) in docker-compose.yml', function (): void {
    $services = composeYaml('docker-compose.yml')['services'] ?? [];
    $noProfile = array_keys(array_filter(
        $services,
        fn (array $svc) => empty($svc['profiles'])
    ));
    sort($noProfile);
    expect($noProfile)
        ->toBe(['apache', 'php', 'postgres', 'postgres-pulse', 'redis']);
});

it('declares dev profile services correctly', function (): void {
    $services = composeYaml('docker-compose.yml')['services'] ?? [];
    $dev = array_keys(array_filter(
        $services,
        fn (array $svc) => in_array('dev', $svc['profiles'] ?? [], true)
    ));
    sort($dev);
    expect($dev)
        ->toBe(['adminer', 'mailpit', 'node']);
});

it('declares tools profile services correctly', function (): void {
    $services = composeYaml('docker-compose.yml')['services'] ?? [];
    $tools = array_keys(array_filter(
        $services,
        fn (array $svc) => in_array('tools', $svc['profiles'] ?? [], true)
    ));
    sort($tools);
    expect($tools)
        ->toBe(['dozzle', 'it-tools', 'watchtower']);
});

it('declares dev-extra as redis-commander only (legacy MySQL admin tool dropped — D2)', function (): void {
    $main = composeYaml('docker-compose.yml')['services'] ?? [];
    $dev = composeYaml('docker-compose.dev.yml')['services'] ?? [];
    $merged = array_merge($main, $dev);
    $devExtra = array_keys(array_filter(
        $merged,
        fn (array $svc) => in_array('dev-extra', $svc['profiles'] ?? [], true)
    ));
    sort($devExtra);
    expect($devExtra)
        ->toBe(['redis-commander']);
});

it('excludes custom-built images from Watchtower', function (): void {
    $services = composeYaml('docker-compose.yml')['services'] ?? [];
    $excluded = [];
    foreach ($services as $name => $svc) {
        foreach ($svc['labels'] ?? [] as $label) {
            if ($label === 'com.centurylinklabs.watchtower.enable=false') {
                $excluded[] = $name;
            }
        }
    }
    sort($excluded);
    expect($excluded)
        // `test-browser` (ADR-0013) est bâti depuis docker/php/Dockerfile, stage
        // `test` : image custom, donc exclue de Watchtower comme les trois autres.
        ->toBe(['apache', 'node', 'php', 'test-browser']);
});
