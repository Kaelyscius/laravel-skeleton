# Configuration Xdebug avec PHPStorm

Ce guide vous aide à configurer Xdebug avec PHPStorm pour le développement Laravel dans Docker.

## ✅ État de la configuration

Xdebug est maintenant **correctement configuré** dans votre environnement Docker :
- ✅ Xdebug v3.4.5 activé en mode développement
- ✅ Configuration optimisée pour PHPStorm
- ✅ IDE Key: PHPSTORM
- ✅ Port: 9003 (standard PHPStorm)
- ✅ Host: host.docker.internal (compatible Docker Desktop)
- ✅ JIT désactivé en développement (pas de warnings)
- ✅ JIT activé en production (performances optimales)

## 🔧 Configuration PHPStorm

### 1. Activer Xdebug dans PHPStorm

1. Allez dans **File → Settings** (Windows/Linux) ou **PHPStorm → Preferences** (macOS)
2. Naviguer vers **Languages & Frameworks → PHP → Debug**
3. Configurez les paramètres suivants :
   - ✅ **Debug port:** `9003`
   - ✅ **Can accept external connections:** activé
   - ✅ **Break at first line in PHP scripts:** désactivé (recommandé)

### 2. Configurer le serveur PHP

1. Allez dans **Languages & Frameworks → PHP → Servers**
2. Cliquez sur **+** pour ajouter un nouveau serveur :
   - **Name:** `Laravel Docker`
   - **Host:** `localhost`
   - **Port:** `80` (ou le port de votre Apache)
   - **Debugger:** `Xdebug`
   - ✅ **Use path mappings:** activé

### 3. Path Mappings (CRUCIAL)

Dans la section **Path mappings** :
- **Local path:** `/chemin/vers/votre/projet/src`
- **Server path:** `/var/www/html`

Exemple :
```
Local: /home/user/myLaravelSkeleton/src
Server: /var/www/html
```

### 4. Configurer PHP Interpreter

1. Allez dans **Languages & Frameworks → PHP**
2. Cliquez sur **...** à côté de **CLI Interpreter**
3. Ajoutez un nouvel interpréteur **Docker Compose** :
   - **Server:** Docker (si pas encore configuré, configurez-le)
   - **Configuration files:** `./docker-compose.yml`
   - **Service:** `php`
   - **Environment variables:** peut rester vide
   - **PHP executable:** `/usr/local/bin/php`

## 🚀 Test de la configuration

### 1. Démarrer l'écoute Xdebug

1. Dans PHPStorm, cliquez sur l'icône **téléphone** (Start Listening for PHP Debug Connections)
2. Ou utilisez le raccourci : **Ctrl+Shift+F9** (Windows/Linux) ou **Cmd+Shift+F9** (macOS)

### 2. Tester avec un breakpoint

1. Ouvrez un fichier PHP dans votre projet (ex: `src/routes/web.php`)
2. Placez un breakpoint en cliquant dans la marge gauche
3. Dans votre navigateur, visitez votre application Laravel
4. PHPStorm devrait s'arrêter au breakpoint

### 3. Test en ligne de commande

Pour tester Xdebug en CLI :
```bash
# Depuis votre terminal local
make shell
php -d xdebug.start_with_request=yes your-script.php
```

## 🎯 Configuration JIT optimisée

L'environnement est configuré pour optimiser les performances selon le mode :

### Mode Développement (avec Xdebug)
- ✅ **JIT désactivé** : `opcache.jit=0, opcache.jit_buffer_size=0`
- ✅ **Aucun warning JIT** lors du debugging
- ✅ **Xdebug pleinement fonctionnel**

### Mode Production (sans Xdebug)
- ✅ **JIT activé** : `opcache.jit=1255, opcache.jit_buffer_size=128M`
- ✅ **Performances maximales** pour Laravel
- ✅ **Optimisations OPcache** complètes

## 🔍 Vérification de la configuration

Vous pouvez vérifier que Xdebug est bien configuré :

```bash
# Vérifier que Xdebug est chargé (sans warnings JIT)
docker exec laravel-app_php php -v

# Vérifier la configuration Xdebug
docker exec laravel-app_php php -r "echo 'IDE Key: ' . ini_get('xdebug.idekey') . PHP_EOL;"

# Vérifier l'état de JIT
docker exec laravel-app_php php -r "echo 'JIT: ' . ini_get('opcache.jit') . ' | Buffer: ' . ini_get('opcache.jit_buffer_size') . PHP_EOL;"
```

## 🛠️ Dépannage

### Xdebug ne se connecte pas

1. **Vérifiez le firewall** : Assurez-vous que le port 9003 n'est pas bloqué
2. **Path mappings** : Vérifiez que les chemins sont correctement mappés
3. **Docker network** : Le paramètre `host.docker.internal` fonctionne avec Docker Desktop
4. **Pour WSL2** : La configuration `discover_client_host=1` est activée

### Performance

Si Xdebug ralentit votre application :
1. Utilisez `xdebug.mode=debug` uniquement quand nécessaire
2. Désactivez Xdebug en production (automatique)
3. Utilisez les modes spécifiques : `develop`, `debug`, `coverage`

### Commandes utiles

```bash
# Voir l'état de la configuration
docker exec laravel-app_php php -m | grep -i xdebug

# Redémarrer PHP pour appliquer des changements
docker compose restart php

# Basculer vers mode production (JIT activé, xdebug désactivé)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

## 📚 Ressources supplémentaires

- [Documentation officielle Xdebug](https://xdebug.org/docs/)
- [Guide PHPStorm Xdebug](https://www.jetbrains.com/help/phpstorm/configuring-xdebug.html)
- [PHP JIT Documentation](https://www.php.net/manual/en/opcache.configuration.php#ini.opcache.jit)