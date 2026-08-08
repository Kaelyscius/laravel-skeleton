# ADR-0011 — Observation avant composition : réordonnancement d'Epic 1

> **Statut** : ✅ Accepted — 2026-07-30 · **amendé le 2026-08-08** (§1 uniquement, voir ci-dessous)
> **Décideurs** : Alex (PO), roundtable party-mode (Winston, Murat, Amelia, Sally, John, Mary, Paige, Caravaggio)
> **Supersède** : l'ordre des stories 1.9 → 1.13 dans `_bmad-output/planning-artifacts/epics.md`, et la note de reprise `docs/RESUME-1.9.md` (supprimée)
> **Voir aussi** : [ADR-0009](ADR-0009-modular-app-modules-psr4.md), [ADR-0012](ADR-0012-ecran-offline-et-module-media.md), [ADR-0013](ADR-0013-runner-navigateur-pest-browser.md)

---

## ⚠️ Amendement du 2026-08-08 — les layouts (1.13) passent AVANT les composants time-as-texture (1.12)

> **Décideur** : Alex (PO), question ponctuelle à agent unique — la règle de cadrage interdisant
> les roundtables jusqu'à `epic-1: done` a été respectée.
> **Portée** : §1 « Réordonnancement d'Epic 1 » **uniquement**. La doctrine (§3, règles R1/R2/R3),
> les écartements (§4) et la hiérarchie documentaire (§5) sont **inchangés** — c'est d'ailleurs
> R1 qui produit cet amendement.

**Nouvel ordre du reliquat** : `1.11 ✅ → 1.13 → 1.12 → 1.9 → 1.10a`.

**Fait nouveau, découvert en livrant la Story 1.11.** Alpine n'est pas une dépendance qu'on
installe : il arrive dans le bundle de Livewire 4, donc **uniquement sur les pages qui appellent
`@livewireScripts`** — ce que câble la Story **1.13**. Toute story antérieure qui affirme un
comportement client se retrouve donc avec un AC sans référent, au sens exact du tableau du
Contexte ci-dessus.

Ce n'est pas une hypothèse : le cas s'est produit en 1.11. L'AC7 de `<x-toast>` exigeait une
auto-fermeture ; il a fallu l'arbitrer en cours de story (structure en 1.11, comportement en
1.13). La Story 1.12 porte **le même défaut**, à l'identique — « refresh Alpine 60 s pour
`<x-time-relative>` », déjà classé `SANS-RÉFÉRENT` par la passe de relecture du 2026-07-30.

**Pourquoi inverser plutôt que re-scinder.** Scinder une deuxième fois était possible et
cohérent avec le précédent. Deux raisons l'ont emporté :

1. **La 1.13 devenait le point de concentration du risque.** Elle porterait alors les layouts
   public + minimal, `@livewireScripts`, l'articulation avec la CSP de `spatie/laravel-csp`,
   l'auto-fermeture du toast **et** le refresh du temps. Une story de niveau R qui accumule les
   reports de trois autres stories n'est plus une story, c'est un point de rupture.
2. **Un temps relatif qui ne se rafraîchit pas vide la story de sa substance.** « Time as
   texture » (Direction C) repose sur une durée vivante ; la reporter, c'est livrer la forme
   sans la fonction, puis vérifier la fonction ailleurs — exactement ce que §3/R3 refuse.

**Ce que l'inversion ne coûte pas.** L'argument d'origine — *observation avant composition* —
portait sur l'impossibilité de vérifier un rendu sans navigateur. Ce verrou est levé depuis
ADR-0013 : `make test-browser` existe et son rouge est prouvé en local et en CI. Et un layout
n'a besoin d'aucun composant pour naître : les 6 primitives de la 1.11 existent déjà, donc la
1.13 a de quoi se remplir pour être vérifiée.

**Ce que l'inversion ne change pas.** La 1.9 ferme toujours la marche (elle seule dépend de
l'état **final** du `<head>`), et la 1.10a la suit toujours pour la même raison qu'avant : le
pipeline Vite de Filament v5 risquerait de réécrire la configuration sous les preloads.

**Conséquence sur la dette ouverte par la 1.11 :** `src/tests/Feature/BladeComponentsTest.php`
contient un test daté qui interdit `x-data`, `x-init`, `setTimeout`, `addEventListener`, `wire:`
et `Alpine` dans `toast.blade.php`. Il **doit être supprimé en Story 1.13** et remplacé par le
test de comportement d'auto-fermeture. Le voir rougir alors n'est pas une régression : c'est le
rendez-vous qu'il a lui-même inscrit dans son message d'échec.

---

## Contexte

Au 2026-07-30, l'Epic 1 est à 8 stories sur 13. Les trois workflows CI sont verts pour la
première fois du projet (HEAD `647d276`), et la suite compte 55 tests / 203 assertions.

**Aucun navigateur n'a jamais affiché ce projet.** Les 55 tests sont structurels — arborescence
PSR-4, `composer.json`, profils Compose, présence de tokens CSS. Aucun n'a rendu un pixel.

Ce fait n'est pas isolé : il est la dernière instance d'un motif que le projet traîne depuis
mai, nommé lors d'une session antérieure **« les garde-fous silencieux »**. Six cas recensés,
tous de même signature — une affirmation que rien ne pouvait contredire :

| # | L'affirmation | Le référent qui manquait |
|---|---|---|
| 1 | « les tests passent » | la CI tournait sur MariaDB, pas PostgreSQL |
| 2 | « rien ne passe sans contrôle » | le hook pre-commit n'était jamais exécuté |
| 3 | « on est scanné » | les scans de sécurité étaient dormants |
| 4 | « les secrets sont exclus » | `.gitignore *token*` aurait avalé les fichiers Sanctum |
| 5 | « la chaîne est absente » | `toContain()` est variadique sur les needles — l'assertion passait toujours |
| 6 | « le layout est utilisé » | `<x-layouts.public>` naît en Story 1.13, l'AC3 de la 1.9 le nomme |

La preuve en creux, la plus nette : jusqu'au 2026-07-27, `origin/main` était resté à la
Story 1.1. Sept stories marquées `done`, un seul référent poussé. Le mot `done` lui-même était
une affirmation sans référent — et le premier push a fait tomber 11 défauts d'un coup, dont
**aucun** n'était consigné dans `deferred-work.md`.

### Le cas n°6, qui déclenche cet ADR

L'AC3 de la Story 1.9 (*self-host IBM Plex*) exige trois `<link rel="preload">` dans le `<head>`
de `<x-layouts.public>`. Ce composant est créé par la Story **1.13**. L'AC est donc *sans
référent* : il ne peut être ni vérifié ni infirmé au moment où la story serait implémentée.

La réciproque existe et confirme le diagnostic : l'AC de la Story 1.13 exige un `<head>` « avec
preload fonts », c'est-à-dire le produit de la 1.9. **Les deux stories se citent mutuellement.**

### Le layout jetable, écarté

L'échappatoire naturelle — écrire un layout minimal pour tester la 1.9 — a été examinée et
refusée. Un échafaudage de test n'est légitime que s'il est **plus contraint** que la
production. Un layout jetable serait plus *permissif* : ni les directives CSP de
`spatie/laravel-csp`, ni l'ordre réel des balises, ni la concurrence avec Vite pour l'injection
dans le `<head>`. Le preload passerait au vert sur un `<head>` vide et rougirait peut-être une
fois le vrai layout arrivé. Le test mesurerait l'échafaudage, pas la fonctionnalité.

---

## Décision

### 1. Réordonnancement d'Epic 1

> ⚠️ **Les étapes 4 et 5 ont été INVERSÉES le 2026-08-08** — voir l'amendement en tête de
> document. Le bloc ci-dessous est conservé tel qu'il a été décidé le 2026-07-30 ; il n'est
> plus l'ordre applicable.

```
0.  spike runner navigateur                    ← prérequis de tout le reste
0b. observer MODULE_LIVE_ENABLED=false         ← observation, pas test
1.  3 écrans de référence (docs/ux/references/)  + audit time-as-texture
2.  passe de relecture des AC 1.9 → 1.13
3.  1.11  composants Blade de base   (+ cta_text / cta_url)
4.  1.12  composants time-as-texture           ← devient 5 (amendement 2026-08-08)
5.  1.13  layouts                              ← devient 4 (amendement 2026-08-08)
6.  1.9   self-host IBM Plex
7.  1.10a Filament v5 + Sanctum + Spatie Permission
    1.10b SettingsResource  → déplacée en Epic 5
```

La 1.9 ferme la marche parce qu'elle est la seule dont l'AC dépend de l'**état final** du
`<head>`. La 1.10a suit, et non précède, parce que Filament v5 embarque son propre pipeline
Vite : l'installer après la 1.9 risquerait de réécrire la configuration sous les preloads.
Ce risque est retenu comme **à vérifier lors de la 1.10a**, pas comme acquis.

### 2. Le spike runner navigateur, avec ses critères écrits à l'avance

Le plugin browser de Pest 4 est retenu **si les quatre sont satisfaits** :

1. Il s'installe sur PHP 8.5.4 sans `--ignore-platform-reqs`.
2. Il pilote un navigateur hors du conteneur `php`, ou son coût reste confiné à un
   `Dockerfile.test` **sans toucher à l'image de production**.
3. Un test minimal charge une page et lit `getComputedStyle(document.body).fontFamily`.
4. **Le même test échoue quand on casse la source de la police.**

Le critère (4) est le seul qui compte. Les trois autres sont de la logistique.

Sinon → Playwright TypeScript, service Compose dédié profil `test`, image
`mcr.microsoft.com/playwright` tirée et non buildée, `ipc: host` obligatoire (sinon OOM Chromium
sur `/dev/shm`), version épinglée exactement sur celle du package npm. Dans les deux cas :
**un seul runner navigateur, jamais deux.** Le vhost servant en HTTPS auto-signé,
`ignoreHTTPSErrors` — on ne réécrit pas le vhost pour un test.

**Critère d'abandon d'hypothèse** (et non timebox — le temps n'est plus une contrainte du
projet) : deux tentatives de contournement documentées sur le plugin Pest, puis bascule
Playwright sans re-débat. Un timebox n'existe pas pour aller vite, il existe pour empêcher le
sunk cost de transformer « cette approche ne marche pas » en « je suis à deux doigts ».

### 3. Doctrine de vérification — trois règles

**R1 — Résolution des noms (porte humaine, definition-of-ready).**
Tout AC nomme un artefact : fichier, route, sélecteur, composant. Avant qu'une story passe
`backlog` → `in-progress`, chaque nom cité doit résoudre vers un chemin existant ou vers une
story `done`. Un nom qui ne résout pas bloque la story.

**R2 — Le référent se vérifie à l'exécution, pas dans le document.**
Aucun test ne scanne `epics.md`. Laravel *est déjà* le résolveur de noms : un test front qui
passe par un rendu réel (`Blade::render()` ou une vue montée) échoue nativement sur un composant
inexistant, sans qu'on écrive un seul assert. Un test navigateur qui cible un sélecteur absent
du DOM échoue de même.

**R3 — Critère de sortie de toute story front.**
Un test qui ne peut pas rougir en cassant ce qu'il prétend tester n'est pas un test. La mutation
doit être exécutée et le rouge observé, pas supposé.

### 4. Ce qui a été explicitement écarté

- **Un test Pest scannant `epics.md`** pour vérifier que chaque AC nomme un artefact existant.
  Personne n'a pu nommer la mutation qui le ferait rougir : pour supprimer un artefact
  référencé par une story `done`, il faudrait supprimer un module — ce qui fait déjà rougir
  `PsrAutoloadTest`, `CrossModuleCouplingTest` et la moitié de la suite. Redondant par
  construction, donc garde-fou silencieux n°7. Écarté définitivement.
- **Un balisage `produces:` / `consumes:` par story dans `epics.md`.** Mécaniquement faisable,
  mais le test ne vérifierait jamais que `consumes` est *complet* : une story partant en dev
  avec un bloc vide resterait verte. On aurait automatisé l'étape facile (la résolution) en
  laissant manuelle l'étape qui échoue (l'extraction).
- **Un rapport d'audit séparé** dans `_bmad-output/`. Lu une fois, jamais relu. La passe de
  relecture produit des **patchs directs sur `epics.md`**, avec une ligne
  `> Requalifié 2026-07-30 : <raison>` sous chaque AC touché. Ce qui doit survivre, c'est l'AC
  corrigé.

### 5. Hiérarchie documentaire

Règle unique : **plus un document est difficile à changer, plus il fait autorité.**

```
docs/adr/                       immuable — on ne corrige pas, on supersède
  ↑ contredit seulement par un nouvel ADR
epics.md + sprint-status.yaml   source de vérité opérationnelle
  ↑ contredit seulement par une story terminée
docs/ETAT.md                    pointeur de reprise, volatile, écrasable, jamais cité ailleurs
docs/roundtable-decisions.md    journal de conversation — aucune autorité
```

`docs/RESUME-1.9.md` est **supprimé**, pas archivé. Son nom de fichier encodait une séquence
désormais fausse, et un nom de fichier survit à toutes les relectures. L'archiver aurait produit
une seconde copie du mensonge avec un badge de légitimité. Son remplaçant `docs/ETAT.md` porte
un nom stable, jamais daté, jamais numéroté, et il est écrasé à chaque session.

Le pointeur de `sprint-status.yaml` vers la note de reprise est retiré : une source de vérité
qui délègue à un post-it n'est plus une source de vérité.

**Règle d'hygiène :** quand une décision contredit un document, on modifie le document dans le
même commit.

---

## Conséquences

### Positives

- L'AC3 de la Story 1.9 devient vérifiable. La dépendance circulaire 1.9 ↔ 1.13 est rompue.
- La classe entière des assertions « valeur calculée » devient accessible — amortie sur les
  ~118 scénarios du test-design (`_bmad-output/test-artifacts/`), pas seulement sur la 1.9.
- Les 3 écrans de référence deviennent le premier **consommateur** des tokens CSS de la
  Story 1.8, qui avaient été écrits sans qu'aucun écran n'existe.

### Négatives / acceptées

- **La Story 1.8 peut être rouverte.** Si les écrans de référence révèlent des tokens mal
  calibrés, on corrige. `done` n'a jamais voulu dire `gelé` : un artefact que rien n'a jamais pu
  contredire n'est pas validé, il est seulement non testé. Un token corrigé avant qu'aucun
  composant ne le consomme coûte une ligne ; après la 1.11, il coûte une refonte.
- **R1 reste une discipline humaine.** Elle n'est pas automatisable, et la discipline est
  précisément ce qui a produit les six cas. Atténuation : les six cas ont tous été écrits en
  phase de *rédaction*, où nommer un artefact futur est légitime ; ils ne deviennent des défauts
  qu'à l'entrée en dev. La porte est donc placée au bon moment, et R2 la double à l'exécution.
- Un runner navigateur est une pièce d'infrastructure de plus à maintenir.

### Le 7e cas, ouvert

`MODULE_*_ENABLED=false` n'a **jamais été exécuté ni observé**, alors que la Story 1.7 est
`done` et que l'activation conditionnelle par ENV est la promesse centrale du produit
(ADR-0001, ADR-0009). `src/tests/Feature/ModuleActivationTest.php` existe — reste à établir
s'il peut rougir. Action retenue : poser `MODULE_LIVE_ENABLED=false` et **regarder ce que
Laravel rend**. Pas un test : une observation.

---

## Alternatives écartées

- **Garder l'ordre du plan et découper la 1.9 en 1.9a / 1.9b.** Un preload sans layout n'est pas
  un incrément livrable, et l'AC3 resterait invérifiable jusqu'à la 1.13.
- **Un layout minimal jetable.** Voir Contexte : plus permissif que la production, donc
  producteur de faux-verts.
- **Aller moins vite.** Le projet a produit 8 stories en deux mois sur un Epic budgété cinq
  jours : la lenteur était déjà là et n'a rien empêché. La lenteur produit du soin, pas du
  référent.
