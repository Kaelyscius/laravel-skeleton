<?php

$errors = [];
$warnings = [];

// Vérification des extensions critiques
$requiredExtensions = ['pdo', 'pdo_mysql', 'mbstring', 'zip'];
$optionalExtensions = ['redis', 'apcu'];

foreach ($requiredExtensions as $ext) {
    if (!extension_loaded($ext)) {
        $errors[] = "Extension PHP manquante (critique): $ext";
    }
}

foreach ($optionalExtensions as $ext) {
    if (!extension_loaded($ext)) {
        $warnings[] = "Extension PHP manquante (optionnelle): $ext";
    }
}

// Vérification spéciale pour opcache (Zend extension)
if (!extension_loaded('Zend OPcache') && !extension_loaded('opcache')) {
    $errors[] = "Extension PHP manquante: opcache";
} else {
    // Vérifier que opcache fonctionne vraiment
    if (!function_exists('opcache_get_status')) {
        $warnings[] = "OPcache chargé mais non fonctionnel";
    }
}

// Vérification de PHP-FPM
if (!function_exists('fastcgi_finish_request')) {
    $warnings[] = "PHP-FPM peut ne pas fonctionner correctement";
}

// Affichage des résultats
if (empty($errors)) {
    echo "HEALTHY\n";
    if (!empty($warnings)) {
        echo "Warnings:\n";
        foreach ($warnings as $warning) {
            echo "  - $warning\n";
        }
    }
    exit(0);
} else {
    echo "UNHEALTHY\n";
    echo "Errors:\n";
    foreach ($errors as $error) {
        echo "  - $error\n";
    }
    if (!empty($warnings)) {
        echo "Warnings:\n";
        foreach ($warnings as $warning) {
            echo "  - $warning\n";
        }
    }
    exit(1);
}