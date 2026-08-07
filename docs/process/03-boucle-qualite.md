# Boucle qualité par story

> Écrit le 2026-08-07, à partir de ce que ce projet a réellement produit comme
> défauts — pas d'un catalogue de bonnes pratiques.
>
> Objectif d'Alex : *« une qualité de code excellente, sans pour autant
> sur-ingénierer à chaque fois. »* Les deux moitiés de la phrase comptent
> autant. Une boucle qu'on applique intégralement à tout est une boucle qu'on
> finit par contourner.

---

## 1. Le principe qui organise tout le reste

Ce projet a produit sept « garde-fous silencieux » en six mois : une CI qui
tournait sur le mauvais moteur, un hook jamais exécuté, des scans dormants, un
`.gitignore` qui avalait des fichiers, un `toContain()` variadique qui passait
toujours, un AC sans référent, un flag ENV que rien ne testait. Cause racine
nommée par Mary : **l'affirmation précède son référent.**

Une seule question distingue un garde-fou d'une décoration :

> **Est-ce que je l'ai vu rougir ?**

Pas « est-ce qu'il pourrait rougir ». **Vu.** Toute la boucle ci-dessous en
découle. Le reste — couverture, scores, revues — est de l'instrumentation, utile
mais subordonnée.

Corollaire appris le 2026-08-07 : **la couverture ne répond pas à cette
question.** `AppServiceProvider` était à 100 % de couverture pendant qu'une
mutation le rendant sourd à sa configuration passait les 58 tests. Et
`App\Models\User` à 0 % a porté une erreur *fatale* sans qu'une assertion bouge.
La couverture mesure ce qui a été **exécuté**, jamais ce qui serait **détecté**.

---

## 2. Classer la story avant de choisir la cérémonie

C'est l'étape qui empêche la sur-ingénierie. Elle prend deux minutes.

| Niveau | Ce qui déclenche | Exemples de ce projet |
|---|---|---|
| **S — Standard** | Code applicatif sans surface de sécurité ni invariant transverse | 1.11 composants Blade, 1.12 time-as-texture, 1.9 fonts |
| **R — Renforcé** | Touche un invariant transverse, la CI, l'installeur, ou un mécanisme dont dépendent d'autres stories | 1.13 layouts (CSP + `<head>`), 0e Livewire, Epic 2 |
| **C — Critique** | Authentification, autorisation, tenancy, secrets, données personnelles, exposition réseau | 1.10a Filament + Sanctum + Permission, Epic 4 embed Twitch, ADR-0002 RLS |

Une story est **S par défaut**. On monte de niveau sur un critère nommable, pas
sur une impression. En cas d'hésitation entre deux niveaux, prendre le plus bas
et écrire pourquoi : un doute non écrit se retransforme en zèle à la story
suivante.

---

## 3. La boucle

### Étape 0 — Definition-of-ready (toutes stories, 5 min)

> **Chaque nom cité dans les AC résout vers un chemin existant ou une story
> `done`.**

Née du 6ᵉ cas : l'AC3 de la 1.9 nommait `<x-layouts.public>`, créé par la 1.13.
Un AC sans référent est invérifiable et faux-vert garanti. La passe de relecture
du 2026-07-30 en a trouvé **5 sur 14**.

Non automatisable, et c'est assumé : personne n'a su nommer la mutation qui
ferait rougir un tel test. Le résolveur de noms, c'est Laravel — un test qui
passe par un rendu réel échoue nativement sur un composant inexistant.

```
/bmad-create-story          # puis relire les AC AVANT de lancer le dev
```

### Étape 1 — Développement

```
/bmad-dev-story _bmad-output/implementation-artifacts/<story>.md
```

Règle unique pendant le dev : **tout garde-fou ajouté doit avoir été vu rouge
avant d'être considéré comme livré.** Casser ce qu'il teste, constater l'échec,
restaurer. Trois lignes dans le message de commit suffisent à le prouver.

### Étape 2 — Portes automatiques (toutes stories)

```bash
make test               # 67 tests, exit 0
make quality-ratchet    # 0/0/0 — monotone, ne remonte jamais
make test-browser       # si la story touche du rendu
```

Le ratchet est à zéro depuis le 2026-08-07 (PHPStan niveau 10). Toute hausse est
un échec, pas une négociation. S'il faut vraiment monter un compteur, mettre à
jour `quality-baseline.json` **dans le même commit** pour que ce soit visible en
revue.

### Étape 3 — Revue de code, dosée

| Niveau | Revue |
|---|---|
| **S** | `/bmad-code-review` — les 3 layers, contexte frais |
| **R** | idem + relecture ciblée de l'invariant touché |
| **C** | idem + `/bmad-review-adversarial-general` sur la surface sensible |

Ne pas empiler les revues « pour être sûr ». Deux revues qui disent la même
chose ne valent pas mieux qu'une ; elles coûtent juste le double et fabriquent
de la confiance.

### Étape 4 — Revue de sécurité (R et C uniquement)

```
/security-review        # revue des changements de la branche
make security-scan      # Snyk PHP + Node
composer audit && npm audit
```

`composer audit` a rapporté **7 advisories en une seule session** le
2026-08-06, toutes publiées dans les 48 h. Ce n'est pas un contrôle annuel : à
lancer à chaque story de niveau R ou C, et de toute façon la CI le fait chaque
nuit.

En niveau **C**, ajouter la question que les outils ne posent pas : *qu'est-ce
qui se passe si cette fonctionnalité est appelée sans authentification, ou par
un autre streamer ?* C'est la question qui manquait à `SetCurrentStreamer`.

### Étape 5 — Couverture : la bonne question

```bash
docker compose exec -u 1000:1000 -e XDEBUG_MODE=coverage php \
    php artisan test --coverage
```

**Aucun seuil global.** Un seuil se satisfait en testant ce qui est facile, et
ce projet a la preuve qu'il ment. Trois questions, dans cet ordre :

1. **Le code nouveau de la story est-il exercé ?** Si une classe qu'on vient
   d'écrire est à 0 %, elle n'a jamais été chargée — même pas pour vérifier
   qu'elle se déclare.
2. **Les branches d'erreur le sont-elles ?** C'est là que vivent les défauts
   silencieux. `SetCurrentStreamer` avait 100 % de couverture et rendait un 404
   indiscernable d'une page inexistante.
3. **Un garde-fou nouveau a-t-il été vu rouge ?** Si non, la couverture qu'il
   apporte est cosmétique.

Améliorer la couverture n'est jamais un but en soi : on ajoute un test parce
qu'on a nommé le défaut qu'il attraperait. Si on n'arrive pas à le nommer, on
n'écrit pas le test — on aurait fabriqué un garde-fou silencieux de plus.

`make test-drift` (mutation testing, déjà installé) répond mieux que la
couverture, et c'est l'outil à privilégier sur une story de niveau **C**.

### Étape 6 — Commit et hygiène documentaire

> **Quand une décision contredit un document, on modifie le document dans le
> même commit.**

Hiérarchie d'autorité (Paige) : `ADR > epics.md + sprint-status.yaml > ETAT.md >
roundtable-decisions.md (aucune autorité)`. Plus un document est difficile à
changer, plus il fait autorité.

Le message de commit dit **ce qui a été observé**, pas ce qui a été fait. « Rouge
observé sur la mutation X » vaut mieux que « ajout de tests ».

---

## 4. Ce qu'on ne fait PAS

Cette section a autant d'importance que les autres. Elle évite que la boucle
gonfle à chaque story.

- **Pas de roundtable party-mode** tant qu'`epic-1` n'est pas `done`. Une
  question ponctuelle à un agent unique reste autorisée.
- **Pas de revue empilée.** Une revue par niveau, choisie, pas cumulée.
- **Pas de seuil de couverture en CI.** Voir §5.
- **Pas de test écrit pour un défaut qu'on ne sait pas nommer.**
- **Pas de correction d'un outil contre un autre sans arbitrer.** PHP Insights a
  demandé un type natif sur `User::$fillable` ; PHPStan a refusé ; PHP produit un
  *fatal*. Quand deux outils divergent, **le langage tranche**, puis PHPStan,
  puis Insights — qui est informatif en CI, et le reste.
- **Pas de garde-fou livré sans son rouge.** C'est la seule règle sans exception.

---

## 5. Pourquoi pas de seuil de couverture en CI

Parce qu'il aurait été vert pendant absolument tout ce que cette session a
trouvé :

| Défaut réel | Couverture au moment du défaut |
|---|---|
| `register()` sourd à sa configuration, flag ENV inerte | `AppServiceProvider` **100 %** |
| Erreur fatale PHP dans le modèle User | `Models/User` **0 %**, suite verte |
| `SetCurrentStreamer` rend un 404 silencieux en prod | `SetCurrentStreamer` **100 %** |

Un seuil transforme la couverture en cible ; une cible cesse de mesurer. On
suit le chiffre (78,8 % aujourd'hui) comme un **indicateur de tendance**, jamais
comme une porte.

---

## 6. Résumé exécutable

```bash
# 0. Definition-of-ready : chaque nom des AC résout
/bmad-create-story

# 1. Dev — tout garde-fou ajouté doit être vu rouge
/bmad-dev-story <story>

# 2. Portes automatiques
make test && make quality-ratchet
make test-browser                     # si rendu

# 3. Revue (S/R/C)
/bmad-code-review
/bmad-review-adversarial-general       # C uniquement

# 4. Sécurité (R et C)
/security-review && make security-scan

# 5. Couverture : le code neuf est-il exercé ? les branches d'erreur ?
php artisan test --coverage
make test-drift                        # C : mutation plutôt que couverture

# 6. Commit — le message dit ce qui a été OBSERVÉ
```

**Niveau S : étapes 0, 1, 2, 3, 6.** C'est la boucle courte, et c'est la
majorité des stories. Les étapes 4 et 5 ne s'ajoutent que quand le niveau les
appelle.
