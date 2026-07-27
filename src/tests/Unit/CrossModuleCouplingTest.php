<?php

declare(strict_types=1);

/**
 * Cross-module coupling guard (ADR-0009 §Couplage — risk §12.1).
 *
 * A file under app/Modules/<X> may import App\Core\… and its own
 * App\Modules\<X>\…, but NEVER another module App\Modules\<Y>\… (Y != X).
 * Non-App imports (Illuminate, vendor, App\Models, …) are unrestricted.
 *
 * Pure structural scan — no Laravel boot, no DB. Project root resolved via
 * dirname(__DIR__, 2) (same pattern as PsrAutoloadTest). Dormant today (modules
 * hold only .gitkeep) — activates as Epic 4/5+ add module code; the self-check
 * below proves the detector works regardless.
 *
 * @see docs/process/05-module-boundaries.md
 */
$projectRoot = dirname(__DIR__, 2);

/**
 * Forbidden cross-module imports found in a PHP source.
 *
 * @return list<string>  FQCNs of App\Modules\<Y>\… imports where Y !== $ownModule
 */
function crossModuleUseViolations(string $source, string $ownModule): array
{
    if (preg_match_all('/^use\s+([^\s;]+)/m', $source, $matches) === false) {
        return [];
    }

    $violations = [];

    foreach ($matches[1] as $import) {
        $parts = explode('\\', $import);

        // Only App\Modules\<Module>\… imports are subject to the boundary rule.
        if (count($parts) >= 3 && $parts[0] === 'App' && $parts[1] === 'Modules' && $parts[2] !== $ownModule) {
            $violations[] = $import;
        }
    }

    return $violations;
}

it('flags another module but allows Core, intra-module and vendor imports (self-check)', function (): void {
    // Forbidden: a Reviews file importing the Live module.
    expect(crossModuleUseViolations('use App\\Modules\\Live\\Services\\HelixClient;', 'Reviews'))
        ->toBe(['App\\Modules\\Live\\Services\\HelixClient']);

    // Allowed: Core is the only shared layer.
    expect(crossModuleUseViolations('use App\\Core\\Models\\Streamer;', 'Reviews'))
        ->toBeEmpty();

    // Allowed: intra-module import.
    expect(crossModuleUseViolations('use App\\Modules\\Reviews\\Models\\Game;', 'Reviews'))
        ->toBeEmpty();

    // Allowed: vendor / framework imports.
    expect(crossModuleUseViolations('use Illuminate\\Support\\Str;', 'Reviews'))
        ->toBeEmpty();

    // Aliased import is still detected.
    expect(crossModuleUseViolations('use App\\Modules\\Admin\\Foo as Bar;', 'Reviews'))
        ->toBe(['App\\Modules\\Admin\\Foo']);
});

it('finds no cross-module coupling in app/Modules', function () use ($projectRoot): void {
    // Derive the module list from the directories actually present under
    // app/Modules/ — never a hardcoded list, so a newly added module is never
    // silently exempt from the boundary rule it must obey.
    $moduleDirs = glob($projectRoot . '/app/Modules/*', GLOB_ONLYDIR) ?: [];

    $violations = [];

    foreach ($moduleDirs as $dir) {
        $module = basename($dir);

        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS),
        );

        foreach ($iterator as $file) {
            /** @var SplFileInfo $file */
            if (! $file->isFile() || $file->getExtension() !== 'php') {
                continue;
            }

            $source = (string) file_get_contents($file->getPathname());

            foreach (crossModuleUseViolations($source, $module) as $import) {
                $violations[] = $file->getPathname() . ' → ' . $import;
            }
        }
    }

    expect($violations)
        ->toBeEmpty();
});
