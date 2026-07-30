# Spike — choix du runner navigateur

> Préparé le 2026-07-31. **À exécuter à la prochaine session.**
> Critères d'acceptation figés par [ADR-0011](adr/ADR-0011-observation-avant-composition.md) —
> ils ont été écrits **avant** toute installation et ne se renégocient pas en séance.

---

## Pourquoi ce spike

Aucun navigateur n'a jamais affiché ce projet. Les 55 tests sont structurels : arborescence,
`composer.json`, profils Compose, présence de chaînes dans des fichiers. Aucun n'a rendu un pixel.

**7 AC sur 14** du reliquat d'Epic 1 exigent une *valeur calculée* (hauteur de header rendue,
`prefers-reduced-motion`, pseudo-états `hover`/`focus-visible`, police effective). Ce spike ne
débloque pas la seule Story 1.9 : il débloque la moitié du reliquat.

---

## Pré-vol — déjà vérifié le 2026-07-31, ne pas refaire

| Contrainte | Exigence de `pest-plugin-browser` v4.3.1 | Réel | Verdict |
|---|---|---|---|
| PHP | `^8.3` | **8.5.4** (conteneur) | ✅ |
| Pest | `pestphp/pest: ^4.3.1` | **4.7.5** | ✅ |
| `ext-sockets` | requis | **chargée** | ✅ |
| Plugin en v5 ? | `v5.0.0` exige `pest: ^5` | on est en Pest 4 | ⇒ viser **v4.3.1**, pas v5 |

Autres dépendances tirées : `amphp/amp ^3.1.1`, `amphp/http-server ^3.4.3`,
`amphp/websocket-client ^2.0.2`, `symfony/process ^7.4.3`.
⚠️ `symfony/process ^7.4` — **vérifier le conflit** avec la version tirée par Laravel 13 ; c'est
le risque le plus probable d'échec du critère (1).

**État de la stack au moment de la préparation** : 55 tests exit 0 · ratchet respecté ·
apache `healthy` · `/` répond **200** et sert le CSS Vite compilé. Il y a une page à charger.

> ⚠️ Si la base n'est pas semée, `/` répond **404** (défaut ouvert, voir `deferred-work.md`).
> `php artisan db:seed` avant de commencer.

---

## L'assertion du spike — et pourquoi elle est valable AVANT la Story 1.9

Piège à éviter : les polices IBM Plex ne sont **pas** encore self-hostées (c'est la Story 1.9,
qui vient en fin de séquence). On pourrait croire qu'il n'y a donc rien à mesurer.

C'est faux, et c'est tout l'intérêt. `getComputedStyle(document.body).fontFamily` renvoie la
**déclaration résolue** — la pile de familles telle que la cascade l'a calculée — et non la fonte
réellement chargée. Aujourd'hui, `tokens.css` déclare :

```css
--font-sans: 'IBM Plex Sans', ui-sans-serif, system-ui, sans-serif, 'Apple Color Emoji', …;
```

Donc le navigateur doit rendre une `font-family` **contenant `IBM Plex Sans`**, même sans
fichier `.woff2`. Ce que le spike mesure n'est pas « la bonne police s'affiche » mais
**« le token gouverne réellement la cascade »** — exactement le doute nommé par ADR-0011 :

> `--font-sans` porte le même nom que la variable de thème Tailwind qu'elle alimente, donc
> `@theme inline` émet `--font-sans: var(--font-sans)`. Ça ne tient que parce que `tokens.css`
> est importé **sans `layer()`**.

Si la cascade n'est pas celle qu'on croit, la valeur calculée sera la pile système et le spike
le dira — **avant** que la Story 1.9 ne soit livrée « verte » sur une police système.

**Ne jamais utiliser `toContain()`** : variadique sur les *needles*, donc
`->not->toContain('foo', 'msg')` passe toujours. Deux garde-fous de la 1.8 sont morts ainsi.
Utiliser `str_contains()` + `toBeTrue()` / `toBeFalse($message)`.

---

## Les 4 critères, dans l'ordre d'exécution

### (1) Installation sur PHP 8.5.4 sans `--ignore-platform-reqs`

```bash
make shell
composer require --dev pestphp/pest-plugin-browser:^4.3 --dry-run   # résolution d'abord
composer require --dev pestphp/pest-plugin-browser:^4.3
```

❌ **Échec si** : conflit de dépendances, ou nécessité de `--ignore-platform-reqs`.
→ passer directement au plan B.

### (2) Le navigateur ne contamine pas l'image de production

Question à trancher **avant** d'installer quoi que ce soit de lourd : où tourne Chromium ?

Fait relevé en pré-vol : `docker/php/Dockerfile:44` installe déjà `nodejs` — **Node v22.22.2,
55 Mo, est dans l'image PHP, qui est aussi l'image de production**. Ça ne rend pas acceptable
d'y ajouter un navigateur (~300 Mo + dépendances graphiques), mais ça retire l'argument
« aucun outillage JS n'a le droit d'y être ». *(Voir la dette ouverte plus bas : cette présence
de Node est un sujet en soi, et sa version diverge du conteneur `node` épinglé en 24.18 LTS.)*

✅ **Accepté si** : le navigateur tourne hors du conteneur `php`, **ou** son coût est confiné à
un `Dockerfile.test` qui ne modifie pas l'image de prod.
❌ **Refusé si** : la seule voie est d'installer Chromium dans `docker/php/Dockerfile`.

### (3) Le test minimal passe (vert)

```php
// src/tests/Browser/CascadeSmokeTest.php
it('resolves --font-sans through the real cascade', function () {
    $page = visit('/');                      // API à confirmer selon le plugin
    $family = $page->script('getComputedStyle(document.body).fontFamily');

    expect(str_contains($family, 'IBM Plex Sans'))
        ->toBeTrue("font-family calculée = [{$family}] — le token ne gouverne pas la cascade");
});
```

⚠️ Le vhost sert en **HTTPS auto-signé** → `ignoreHTTPSErrors` côté runner, **ou** viser le vhost
HTTP interne. **Ne pas réécrire le vhost pour un test.**

### (4) LE SEUL QUI COMPTE — le test rougit quand on casse la source

C'est le critère qui manquait aux 6 garde-fous silencieux du projet. **Le rouge doit être
observé, pas supposé.**

```bash
# muter : casser le token
sed -i "s/--font-sans: 'IBM Plex Sans'/--font-sans: 'Comic Sans MS'/" src/resources/css/tokens.css
make npm-build
# → le test DOIT échouer ici
git checkout src/resources/css/tokens.css && make npm-build
# → le test DOIT repasser au vert
```

❌ **Si le test reste vert avec le token cassé, le spike a ÉCHOUÉ**, quel que soit le runner —
et on vient de découvrir que la cascade ne fonctionne pas comme supposé, ce qui est un **bug de
la Story 1.8**, pas un ajustement de la 1.9.

---

## Critère d'abandon d'hypothèse

Ce n'est **pas** un timebox : le temps n'est pas une contrainte de ce projet (décision PO).
Il existe pour empêcher le sunk cost de transformer « cette approche ne marche pas » en
« je suis à deux doigts ».

> **Deux tentatives de contournement documentées** sur le plugin Pest → bascule Playwright,
> sans re-débat. La décision est déjà prise ici ; ne pas la rejouer en séance.

Le compteur est en **essais**, pas en minutes. Écrire les deux tentatives dans ce fichier.

---

## Plan B — Playwright TypeScript

Déclenché par l'échec du critère (1) ou (2), ou par deux contournements documentés.

- Service Compose dédié, **profil `test`** (jamais démarré en prod ni en dev courant)
- Image `mcr.microsoft.com/playwright` — **tirée, jamais buildée**
- `ipc: host` **obligatoire** — sinon OOM Chromium sur `/dev/shm`
- Version de l'image **épinglée exactement** sur celle du package npm (sinon dérive silencieuse)
- `ignoreHTTPSErrors: true`

**Dans les deux cas : un seul runner navigateur, jamais deux.**

---

## À la sortie du spike

1. Consigner la décision en **ADR-0013** (quel runner, pourquoi, ce qui a été essayé et écarté).
2. Mettre à jour `docs/ETAT.md` (prochaine action) et `sprint-status.yaml`
   (`0-spike-browser-runner: done`).
3. Enchaîner sur `0b-observe-module-live-disabled`, puis les 3 écrans de référence.

## Dette relevée pendant la préparation

| Sujet | Détail |
|---|---|
| **Node dans l'image PHP de production** | `docker/php/Dockerfile:44` installe `nodejs` → binaire de 55 Mo dans l'image de prod. Surface d'attaque et poids non justifiés côté runtime PHP. À instruire : est-ce requis par un outil de build, ou un reliquat ? |
| **Dérive de version Node** | Image PHP = **v22.22.2**, conteneur `node` = **v24.18** (épinglé LTS, à ne pas bumper avant le 2026-10-28). Deux runtimes Node dans la même stack, à deux majeures d'écart. |
