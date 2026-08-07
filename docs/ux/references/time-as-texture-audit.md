# Audit time-as-texture — écrans de référence (0c)

> Réalisé le 2026-08-07, en même temps que les 3 écrans de référence.
> Avancé de l'Epic 10 à ici par le roundtable du 2026-07-30, avec la coupe
> portée de −30 % à **−50 %**. Motif retenu :
>
> > *« Un audit qui arrive après le durcissement de la référence n'est pas un
> > audit, c'est une autopsie. »*

---

## 1. De quoi on parle

Le *time-as-texture* (spec UX, Direction Vercel/Astro) consiste à exprimer
**toutes** les mentions temporelles en durée relative plutôt qu'en date absolue :
« en direct depuis 2 h 17 » plutôt que « en direct depuis 19:43 ».

La spec d'origine le voulait **systématique partout** — c'est ce mot qui pose
problème. Un motif systématique n'est plus une texture : c'est un fond. Et le
risque était nommé dès la spec : *« bug d'exécution possible si time-as-texture
devient bruit »*.

## 2. La règle d'admission retenue

Une mention temporelle est **conservée** si, et seulement si, elle répond à l'une
de ces deux questions :

1. **« Est-ce que c'est vivant, maintenant ? »**
2. **« Est-ce que c'est encore frais ? »**

Elle est **coupée** dans tous les autres cas — y compris quand elle est jolie,
y compris quand elle est vraie.

Cette règle n'est pas arbitraire : elle dérive du job que le PO a nommé pour
l'écran offline dans [ADR-0012](../../adr/ADR-0012-ecran-offline-et-module-media.md) §1bis
— ni convertir, ni gagner des abonnés, mais **prouver que ça vit**. Une mention
temporelle qui ne sert pas cette preuve occupe l'attention sans la payer.

## 3. Décisions, écran par écran

| Écran | Mention | Décision | Motif |
|---|---|---|---|
| Accueil LIVE | « En direct depuis 2 h 17 » | **gardée** | Répond à Q1. La durée est plus informative que l'heure de début. |
| Accueil LIVE | « Dernier test publié il y a 3 jours » | **gardée** | Répond à Q2, et date toute la section d'un coup. |
| Accueil LIVE | ~~« 247 viewers right now »~~ | **coupée** | Mesure la performance du stream, pas la vitalité du site. Sur une petite audience, elle dessert l'objectif. Et elle imposait un appel API de plus. |
| Accueil LIVE | ~~date relative sur chaque carte de test~~ | **coupée** | Redondante avec la mention de section. Trois dates pour trois cartes, c'est le moment exact où la texture devient fond. |
| Accueil par défaut | « Dernier stream il y a 14 h » | **gardée** | La plus importante du site. Seule réponse à Q1 quand le stream est éteint, et elle reste vraie après bascule du circuit breaker. |
| Accueil par défaut | « il y a 14 h » / « il y a 2 jours » / « il y a 3 semaines » sur les vignettes | **gardées** | Répondent à Q2, et ADR-0012 pose que la **fraîcheur prime sur l'exhaustivité** : un flux périmé dessert l'objectif et vaut mieux masqué. Ici la date EST le critère de tri. |
| Press kit | « En stream depuis 4 ans » | **gardée** | Répond à Q1 au sens de la longévité — argument de crédibilité pour un interlocuteur presse. |
| Press kit | « Médias mis à jour il y a 2 mois » | **gardée** | Répond à Q2, et engage le lecteur : un portrait de 2021 utilisé en 2026 est son problème. |
| Press kit | ~~« Bio mise à jour il y a 6 mois »~~ | **coupée** | Aucune décision du lecteur n'en dépend, et l'information se retourne contre l'auteur : six mois c'est vieux, deux ans c'est mort. |

## 4. La coupe fait −43 %, pas −50 %. Et c'est volontaire.

**Comptage avant.** En appliquant le motif « systématique partout » de la spec
aux 3 écrans : 6 sur l'accueil LIVE (direct, viewers, dernier test, + une date
par carte de test), 4 sur l'accueil par défaut (dernier stream + une date par
vignette), 4 sur le press kit (ancienneté, bio, médias, dernière VOD) = **14**.

**Comptage après.** Les écrans de référence en portent **8**.

**8 / 14 = −43 %.** L'objectif affiché était −50 %. Je ne l'ai pas atteint, et je
n'ai pas coupé une neuvième mention pour y arriver : **aucune des 8 restantes ne
tombe sous la règle d'admission du §2**. Couper la neuvième aurait voulu dire
choisir la moins gênante plutôt que la moins utile — c'est-à-dire faire primer le
quota sur le critère.

C'est le seul arbitrage de cet audit qui mérite d'être discuté. Il se résume
ainsi : **le −50 % était une direction, la règle d'admission est l'instrument.**
Quand les deux divergent, c'est la règle qui gagne, sinon le nombre devient une
cible et cesse de mesurer quoi que ce soit.

Si tu veux réellement −50 %, la mention à sacrifier est *« Médias mis à jour il y
a 2 mois »* sur le press kit : c'est la plus faible des 8, elle passe Q2 de peu.
Décision non prise ici — elle t'appartient.

**Vérifiable, pas déclaratif :**

```bash
grep -c 'class="temporal"' docs/ux/references/*.html   # 2 + 4 + 2 = 8
```

Chaque mention temporelle des écrans porte la classe `.temporal`, et **elle
seule** — c'est la raison d'être de cette classe. Elle donne la liste exhaustive
en une commande, ce qui rend l'audit rejouable quand les écrans évolueront.

> ⚠️ Cette vérification n'est **pas** un test automatisé, et ne doit pas être
> présentée comme tel. Personne n'a su nommer la mutation qui la ferait rougir
> utilement — le même raisonnement qui a fait écarter, au roundtable du
> 2026-07-30, l'automatisation du contrôle « tout AC nomme un artefact
> existant ». C'est une **commande de relecture**, pas un garde-fou.

## 5. Ce que les écrans ont appris sur les tokens

ADR-0011 autorise explicitement la réouverture de la Story 1.8 si les écrans de
référence révèlent des tokens mal calibrés. Résultat de cette première passe :

- **Aucun token ne manque** pour ces 3 écrans. Les 15 tokens suffisent.
- **`--accent-lava` tient sa RÈGLE 2.** Sur les 3 écrans, il n'apparaît que dans
  3 des 4 usages autorisés : badge LIVE, CTA primaire, note ≥ 9/10. Le 4ᵉ
  (destructif admin) n'a pas d'écran ici. Aucun usage opportuniste n'a été
  nécessaire — ce qui est le vrai test de la règle.
- **`--text-secondary` à 0.60 d'opacité** porte à la fois le texte de soutien et
  les mentions temporelles. C'est le seul point où j'ai hésité : les deux rôles
  finissent au même niveau visuel. `.temporal` s'en sort en changeant de
  **famille** (mono) et de taille plutôt que de couleur — mais si la 1.11 fait
  cohabiter les deux dans un même bloc, un token intermédiaire pourrait manquer.
  **Non tranché ici** : on ne crée pas un token pour un besoin hypothétique.
- **`--max-prose` (720px) fonctionne** sur la bio du press kit. Rappel : il
  s'utilise via `max-w-measure`, jamais `max-w-prose` — ce built-in Tailwind est
  codé en dur à 65ch, non surchargeable, et **banni par un test**.

## 6. Statut de ces écrans

Ce sont des **références**, pas de la production, et pas non plus le « layout
jetable » qu'ADR-0011 a refusé — ils ne valident aucun test et ne se substituent
à rien. Ils servent à *voir* avant de composer.

Le layout réel naît en **Story 1.13**, en Blade, avec la CSP, l'ordre réel des
balises et la concurrence Vite pour le `<head>`. Quand il existera, ces fichiers
resteront comme intention de design — à mettre à jour si le design bouge, ou à
supprimer s'ils commencent à mentir. **Un écran de référence périmé est pire
qu'aucun écran de référence.**
