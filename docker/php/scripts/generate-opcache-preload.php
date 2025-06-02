<?php

/**
 * Générateur de fichier de preload OPcache pour Laravel
 * À exécuter après l'installation de Laravel
 */

$projectPath = '/var/www/html';
$outputFile = $projectPath . '/config/opcache-preload.php';

// Répertoires à précharger
$directories = [
    $projectPath . '/vendor/laravel/framework/src',
    $projectPath . '/vendor/symfony',
    $projectPath . '/app',
    $projectPath . '/config',
];

// Fichiers à exclure
$excludePatterns = [
    '*/Tests/*',
    '*/tests/*',
    '*/Test/*',
    '*/test/*',
    '*/.git/*',
    '*/vendor/laravel/framework/src/Illuminate/Foundation/Testing/*',
];

$files = [];

// Récupérer tous les fichiers PHP
foreach ($directories as $directory) {
    if (!is_dir($directory)) {
        continue;
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($directory)
    );

    foreach ($iterator as $file) {
        if ($file->isFile() && $file->getExtension() === 'php') {
            $path = $file->getPathname();

            // Vérifier les exclusions
            $exclude = false;
            foreach ($excludePatterns as $pattern) {
                if (fnmatch($pattern, $path)) {
                    $exclude = true;
                    break;
                }
            }

            if (!$exclude) {
                $files[] = $path;
            }
        }
    }
}

// Générer le fichier de preload
$preloadContent = "<?php\n\n";
$preloadContent .= "/**\n";
$preloadContent .= " * Fichier de preload OPcache pour Laravel\n";
$preloadContent .= " * Généré automatiquement le " . date('Y-m-d H:i:s') . "\n";
$preloadContent .= " * Nombre de fichiers : " . count($files) . "\n";
$preloadContent .= " */\n\n";

$preloadContent .= "// Ignorer les erreurs lors du preload\n";
$preloadContent .= "error_reporting(0);\n\n";

foreach ($files as $file) {
    $preloadContent .= "opcache_compile_file('$file');\n";
}

file_put_contents($outputFile, $preloadContent);

echo "Fichier de preload généré : $outputFile\n";
echo "Nombre de fichiers à précharger : " . count($files) . "\n";

// Afficher la taille totale
$totalSize = 0;
foreach ($files as $file) {
    $totalSize += filesize($file);
}
echo "Taille totale : " . round($totalSize / 1024 / 1024, 2) . " MB\n";