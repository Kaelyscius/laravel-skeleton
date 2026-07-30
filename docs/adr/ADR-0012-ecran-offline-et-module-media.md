# ADR-0012 — Écran offline : vignettes + liens sortants, module `Media`, Twitch seul

> **Statut** : ✅ Accepted — 2026-07-30 *(§1bis, §2bis et §2ter ajoutés le même jour, après clarification du PO sur l'objectif et le choix de YouTube)*
> **Décideurs** : Alex (PO), roundtable party-mode (Sally, Caravaggio, John, Winston, Victor)
> **Amende** : FR-Live-3, FR-Live-5, UX-DR-19, UX-DR-50, NFR-Metric-7 de `_bmad-output/planning-artifacts/epics.md`
> **Voir aussi** : [ADR-0001](ADR-0001-modularity-plausible-style.md), [ADR-0009](ADR-0009-modular-app-modules-psr4.md), [ADR-0011](ADR-0011-observation-avant-composition.md)

---

## Contexte

Un streamer est hors ligne environ **88 % du temps**. L'écran « offline » de la homepage n'est
donc pas un état dégradé : c'est statistiquement *le* site. Le PRD le reconnaît déjà —
FR-Live-3 le qualifie d'« état nominal » — mais aucun écran n'a jamais été dessiné, et aucun
navigateur n'a jamais affiché ce projet (ADR-0011).

Deux demandes ont convergé sur cet écran :

1. Le besoin d'un **écran de référence** avant d'écrire les composants de la Story 1.11 — les
   tokens CSS de la Story 1.8 ont été écrits sans qu'aucun écran n'existe, et une baseline
   visuelle démarrée sans référence gèlerait l'accident au lieu de garder l'intention.
2. Une demande du PO : agréger **VODs Twitch, clips Twitch, best-of YouTube, Reels Instagram,
   TikTok** sur cet écran, « afin de générer du trafic sur nos réseaux ».

La seconde demande change le **job** de l'écran, pas seulement son contenu.

### Le visiteur réel

Il arrive d'un clip, d'un Discord, d'un retweet — donc d'un téléphone. Son geste n'est pas
« donne-moi encore du contenu », c'est « attends, c'est qui ce type ». Lui répondre par un
article est un décalage de format ; lui répondre par un mur de vignettes lui rend l'écran qu'il
vient de quitter, en moins bien fourni et sans algorithme — un terrain où TikTok gagne sans
jouer.

---

## Décision

### 1. Sens de circulation : réseaux → site → possession

Le site ne doit pas être un aiguillage vers les plateformes. Elles possèdent l'algorithme, la
distribution et l'audience ; elles gagnent ce match sans jouer. Le seul axe où elles sont
structurellement incapables de suivre est **la permanence et la propriété** : un VOD Twitch
expire, un clip se perd, un compte peut être suspendu sans appel. Le site est le seul endroit où
le streamer possède l'adresse, l'archive et la relation.

Les réseaux sont donc traités comme **entonnoir d'entrée**, pas comme sortie. Une sortie n'est
un gain que si elle crée un **canal de retour** (abonnement, Discord — qui notifient au prochain
live). Un clic vers un contenu qui ne s'abonne pas est une fuite qu'on ne mesure même pas.

### 1bis. Le troisième job : prouver que ça vit

*(Ajouté 2026-07-30 après clarification du PO.)*

La table opposait deux objectifs — gagner des abonnés sur les plateformes (A) *ou* obtenir que
le visiteur revienne au prochain live (B). Le PO refuse l'alternative et en nomme un troisième,
qui les subsume :

> « Ça permet d'avoir une **vie hors live**. De créer de l'engagement. Et de donner envie au
> viewer de revenir sur un prochain live. »

Ce n'est ni A ni B : c'est un **signal d'activité**. Un visiteur qui tombe sur un site inerte
conclut que le streamer a arrêté ; un visiteur qui voit trois publications récentes conclut que
c'est vivant. Le contenu affiché ne sert pas d'abord à convertir — **il sert à dater le
projet**. C'est aussi ce qui donne son poids au statut « dernier stream il y a X » : une durée
récente est une preuve de vie, une durée longue est un aveu.

Conséquence de conception : ce qui compte est la **fraîcheur visible**, pas l'exhaustivité du
catalogue. Trois éléments récents valent mieux que douze dont le plus récent a six mois. Un flux
qui n'a rien produit depuis longtemps **dessert** l'objectif — il vaut mieux le masquer que
l'afficher périmé. À trancher au moment de l'implémentation : un seuil d'ancienneté au-delà
duquel un item n'est plus rendu.

**Ce que cette clarification règle sans coût :** l'objectif du PO — faire grandir Instagram,
TikTok et YouTube — **ne requiert aucune API**. Faire grandir un réseau demande un lien vers le
profil (`social_links[]`) ; montrer une publication demande un lien collé à la main. Les deux
sont déjà retenus ci-dessous. Ce que l'analyse écarte n'est pas *les réseaux du streamer*, c'est
l'**ingestion automatique par API** — un travail invisible qui n'ajoute rien à l'objectif et qui
se paie chez chaque forkeur. Instagram, TikTok, YouTube et Twitter peuvent donc figurer sur
l'écran offline **dès la v1, sans une seule clé API**.

### 2. Sources : Twitch seul, plus un champ de lien manuel

| Source | Décision | Motif |
|---|---|---|
| **Twitch** (VODs + clips) | ✅ retenue | mêmes client credentials que le statut live, endpoints `/videos` et `/clips` — coût marginal quasi nul |
| **YouTube Data API v3** | ⏸️ différée en implémentation, **retenue en principe** | voir §2bis — le PO l'a désignée comme seconde surface de vision. Coût : projet Google Cloud, clé, quota journalier, pour *chaque* fork-streamer |
| **Instagram Reels** | ❌ écartée | l'accès aux médias passe par l'écosystème Meta : compte professionnel, app, revue applicative, tokens à renouveler. *L'état exact des endpoints en 2026 n'a pas été vérifié — à établir avant tout engagement.* |
| **TikTok** | ❌ écartée | API developer avec revue d'application. *État actuel à vérifier de même.* |
| **Lien manuel** | ✅ retenue | un champ URL saisi à la main délivre l'essentiel de la valeur pour zéro dépendance |

Le critère décisif n'est pas la difficulté pour Alex, c'est la **philosophie « clone et lance »**
(ADR-0001). Un squelette qui exige de chaque forkeur une revue d'application Meta ou TikTok
avant d'avoir une homepage n'est pas forké : il ne vend pas une fonctionnalité, il vend une
charge de maintenance perpétuelle — cinq jeux de credentials, cinq quotas, cinq breaking
changes, pour un projet solo bénévole.

Si un forkeur réclame un jour Instagram ou TikTok, il aura ouvert une issue. Ce jour-là il y
aura une donnée. Aujourd'hui il n'y a qu'une envie — et zéro visiteur.

### 2bis. YouTube — retenue en principe, différée en implémentation

*(Ajouté 2026-07-30. Le PO, interrogé sur le seul réseau à retenir en plus de Twitch, a répondu
YouTube : « c'est la deuxième source de vision des lives, clips etc. »)*

**Pourquoi YouTube n'est pas un cinquième réseau.** L'abonnement YouTube est un **canal de
notification** : il alerte l'abonné au prochain live. Instagram et TikTok ne notifient rien.
YouTube est donc simultanément une vitrine de contenu et un mécanisme de retour — le seul cas où
« envoyer un visiteur dehors » satisfait la condition posée en §1 (une sortie n'est un gain que
si elle crée un canal de retour). Twitch + YouTube ne forment pas un agrégateur : c'est **la
source live et son archive**, deux faces du même contenu.

La condition reste attachée à la propriété du canal, pas au nom de la marque : un réseau qui ne
notifie pas ne bénéficie pas de cet argument.

**Ce qui est décidé :**

- **v1 : aucune API YouTube.** Les vidéos YouTube entrent par le **champ de lien manuel**,
  au même titre que n'importe quel réseau. Le squelette doit fonctionner sans qu'aucun forkeur
  n'ouvre une console Google.
- **Quand l'API sera implémentée** : source activée **uniquement si `YOUTUBE_API_KEY` est non
  vide**. Clé absente → connecteur non enregistré, aucun job planifié, aucun avertissement en
  boucle dans les logs, **section absente du DOM** (pas vide). C'est la première dépendance
  optionnelle du projet ; elle ne doit jamais être bloquante.
- **Quota** : cadence lente (une ingestion par heure suffit pour un catalogue). Un
  `403 quotaExceeded` est traité comme un **succès dégradé** — on journalise, on ne vide rien, et
  le backoff est un **no-op jusqu'au reset**, pas un exponentiel : réessayer brûle un quota qu'on
  n'a plus. ⚠️ *Les valeurs de quota 2026 n'ont pas été vérifiées — à établir avant d'écrire la
  story, pas à supposer.*
- **Tri** : récence pure, **aucune pondération** entre sources. Pondérer, c'est inventer un
  algorithme de feed que personne n'a demandé et que personne ne pourra déboguer. Si un flux
  noie l'autre, on corrige par la présentation (une rangée par source), pas par un score.
- **Table `media_items` inchangée** : les six colonnes couvrent les deux sources — c'est
  précisément pourquoi le polymorphisme a été refusé. `source` reste une chaîne.
- **Miniatures YouTube** : ⚠️ *les conditions d'utilisation 2026 concernant le rehosting des
  miniatures n'ont pas été vérifiées.* Absence de blocage technique ≠ autorisation
  contractuelle. À établir. Repli propre si la réponse est non : hotlink avec `img-src` élargi —
  coût CSP, aucun script, aucun consentement.
- **Séquencement** : YouTube ne conditionne pas la mise en ligne. Deux sources vides valent
  exactement autant qu'une source vide. Livrer Twitch, mettre le site en ligne, rouvrir YouTube
  sur une raison observable.

**Sur la « possession »** : un abonné YouTube n'appartient pas au streamer. C'est une place dans
la file d'attente d'un algorithme, révocable. YouTube est donc classé comme un **meilleur
réseau**, pas comme un début de possession — il ne remplace pas la capture directe.

### 2ter. Sortie et retour sont deux mécaniques, donc deux emplacements

- **`social_links[]`** (label + url + ordre, **zéro réseau en dur**) — c'est de la **sortie** :
  profils Instagram, TikTok, YouTube, Twitter. Aucune API, disponible dès la v1, et c'est
  suffisant pour l'objectif « faire grandir les réseaux » du §1bis.
- **`discord_url`** — c'est du **retour**. Discord n'est pas un contenu : ni vignette, ni entrée
  de `social_links[]`. Il se place au rang du CTA éditable, en bas, en texte.
- **Marqueur de source sur les vignettes** : deux vignettes 16:9 se ressemblent, et un lien
  sortant qui surprend est un lien qu'on regrette. Marqueur **textuel et discret** —
  **jamais un logo de marque** : un squelette open-source qui embarque des logos propriétaires
  crée un problème juridique gratuit pour chaque forkeur.

### 3. Vignette + lien sortant, jamais d'embed

Aucun script tiers n'est chargé pour afficher un média. Une vignette et un lien sortant :

- **aucun consentement RGPD requis** pour l'affichage — le bandeau et la CSP ne sont sollicités
  qu'au moment où le visiteur demande explicitement un lecteur ;
- **les vignettes sont rapatriées et servies depuis notre domaine** par le job d'ingestion. Une
  image servie par nous n'est pas un tiers : l'écran pré-consentement affiche donc de vraies
  images cliquables, pas des rectangles gris ;
- le consentement se demande **au moment de l'intention** : tap sur play → « charger le lecteur
  Twitch ? ». Un consentement qu'on comprend parce qu'on vient de le déclencher.

Bénéfice stratégique : un embed retient le visiteur ici, un lien sortant l'envoie chez le
streamer. **La version boring sert mieux l'objectif que la version riche.**

### 4. Module `Media`, distinct de `Live`

`Live` gère un **état temps réel** ; `Media` gère un **catalogue persistant**. Cycles de vie,
cadences de rafraîchissement et modes de panne différents. Un fork qui coupe
`MODULE_LIVE_ENABLED` peut vouloir garder son catalogue.

Namespace `App\Modules\Media\`, dossier `app/Modules/Media/`, activable par
`MODULE_MEDIA_ENABLED` — conforme à ADR-0009. Pas d'import direct d'un autre module, sauf via
`App\Core\`.

### 5. Stockage : PostgreSQL source de vérité, Redis cache de lecture

Le pattern « job planifié → Redis → la vue lit le cache », valable pour le statut live
(éphémère), **ne convient pas** à un catalogue : une VOD vit des mois, et un `FLUSHALL` viderait
la home.

Table plate `media_items` — `streamer_id`, `source`, `external_id`, `title`, `thumbnail_url`,
`url`, `published_at` — tenant-aware via `BelongsToStreamer`. Pas de polymorphisme Eloquent.
Ingestion idempotente par `upsert` sur `(source, external_id)`.

Conséquence sur la dégradation : une panne d'API ne vide rien, la dernière ingestion réussie
reste affichée. **À froid, table vide → la section média n'existe pas dans le DOM.** Pas de
grille de squelettes, pas de « bientôt ». L'écran doit rester valable avec zéro item.

### 6. Composition de l'écran, 375 px

Une vidéo, pas une grille. La forme porte le sens — pas un badge :
**16:9 = ça se regarde ici · 9:16 = ça t'emmène ailleurs** (flèche sortante + nom du réseau).

```
1.  « Dernier stream il y a 3 jours »        1 ligne, mono, discrète
2.  HERO : un clip, le plus vu des 7 jours   16:9 pleine largeur — CTA visuel unique
3.  Rail horizontale, 3-4 vidéos             scroll latéral : promet une fin, pas l'infini
4.  Bande de verticaux (si présents)         9:16, petits, liens sortants
5.  Dernière review                          descend, ne sort pas — reste si la vidéo n'a pas pris
6.  CTA éditable (cta_text / cta_url)
```

Aucune section n'est nommée par une plateforme : pas de titre « TikTok ». Les sections se
remplissent avec ce qui existe et **disparaissent si vides**. Zéro vidéo → la review reprend le
hero.

**Le mot « Hors ligne » est supprimé.** Une scène conçue comme état nominal ne s'ouvre pas sur
une négation : « Hors ligne » décrit le serveur Twitch, pas ce que le visiteur peut faire.
« Dernier stream il y a 3 jours » suffit, reste vrai même quand le circuit breaker a basculé
(FR-Live-5), et fait de **LIVE le seul état nommé du site** — ce qui le renforce.

**Le lien press kit est retiré de l'écran offline** (amendement à UX-DR-19). Il s'adressait à un
persona journaliste absent de cet écran. Le press kit vit en Epic 8, accessible par le footer.

### 7. Discipline time-as-texture : audit avancé, coupe portée à −50 %

L'audit « time-as-texture » (UX-DR-50) était planifié pour l'Epic 10 avec une consigne de
retirer 30 % des mentions temporelles. Il est **avancé** : cet écran devient la référence gelée
pour la Story 1.11 et toutes les suivantes, et un audit qui arrive après le durcissement de la
référence n'est pas un audit, c'est une autopsie.

Sur l'écran offline, **deux mentions temporelles sur quatre survivent** :

| Mention | Sort | Motif |
|---|---|---|
| « dernier stream il y a X » | ✅ gardée | c'est *la* donnée de l'écran — transforme l'absence en rythme |
| timestamp du média | ✅ gardé | qualifie le contenu, pas le statut |
| « Publié il y a 3 jours » sur la review | ❌ coupée | une date ancienne dissuade — la signature sabote la conversion |
| « Streaming depuis 4 ans » | ❌ coupée | vanité ; appartient au press kit. `<x-time-since>` reste en bibliothèque |

Règles IBM Plex Mono à 375 px : **≥ 13 px** (en dessous, les chiffres se ferment), jamais deux
lignes de mono adjacentes, max 2 occurrences par écran, couleur secondaire, `tracking-tight`, et
**largeur réservée** pour que le refresh Alpine 60 s de `<x-time-relative>` ne fasse pas
tressauter la page.

### 8. NFR-Metric-7 reclassée en hypothèse datée

La cible « conversion home → article en offline > 25 % » ne vient d'aucun visiteur : il n'y a ni
site, ni audience, ni baseline. C'est une hypothèse habillée en cible, et l'habillage est le
problème — pas l'hypothèse.

- **NFR-Metric-7 cesse d'être un critère d'acceptation.** On ne bloque pas une story sur un
  nombre inventé.
- Reformulée : « on suppose > 25 % ; instrumentation livrée en Epic 4 ; premier relevé après
  30 jours de trafic réel ; **le chiffre observé remplace la cible** ».
- L'AC d'Epic 4 devient : *l'instrumentation existe et produit un nombre*. Pas : *le nombre
  dépasse 25*.
- **Mesure server-side, sans cookie** : compteur de vues home + compteur de vues article avec
  `referer` interne. Une mesure derrière un consentement RGPD ne mesure que le sous-ensemble
  consentant et l'appelle « la conversion » — un garde-fou silencieux de plus (ADR-0011).
- La métrique devient bicéphale : conversion home → article **et** taux de sortie sortante.

### 9. Le troisième état : `MODULE_LIVE_ENABLED=false`

Ni LIVE ni OFFLINE — un trou dans la spec, sur ce qui est pourtant le cas d'usage *nominal* du
fork-streamer (quelqu'un sans chaîne Twitch qui veut les reviews et le press kit).

Décision : la home retombe sur une **variante éditoriale** sans zone live du tout, le hero
devenant la dernière review. L'alternative — garder la mise en page et ne pas rendre le badge —
est écartée : une grille conçue autour d'un badge absent se lit comme un bug.

L'écran offline est déjà à ~80 % la home module-éteint : c'est un argument de plus pour le
dessiner maintenant.

---

## Conséquences

### Positives

- Zéro dépendance tierce ajoutée au chemin d'installation d'un fork : Twitch réutilise des
  credentials déjà nécessaires au statut live.
- L'écran pré-consentement — celui que 100 % des premiers visiteurs voient — est pleinement
  fonctionnel et visuellement complet.
- La CSP reste étroite : aucun script tiers, `img-src` seul concerné, et même pas si les
  vignettes sont servies localement.
- L'écran tient à 0, 3 et 12 items, et sans aucun réseau configuré.

### Négatives / acceptées

- **Pas de lecture inline sans clic** : le visiteur qui veut regarder fait une action de plus.
  Accepté — c'est le prix du zéro-tiers, et le clic est aussi ce qui rend le consentement
  compréhensible.
- **Les Reels et TikTok ne sont pas agrégés automatiquement.** Le champ de lien manuel couvre le
  besoin sans dépendance. Réévaluable sur demande réelle d'un forkeur.
- **Le rapatriement des vignettes** implique du stockage et un nettoyage. Coût assumé : il
  achète l'affranchissement du consentement pour l'affichage.
- **La capture directe n'est pas encore spécifiée.** C'est pourtant le seul actif réellement
  transférable — les plateformes prêtent leurs followers, une liste se garde. Piste retenue
  pour une story propre (`Notify`), hors de cet ADR :

  > **« Je te préviens 10 minutes avant le prochain live. »** [email] → [OK]

  La formulation compte plus que le mécanisme : un bouton « rejoins mon Discord » demande
  d'entrer quelque part sans dire ce qu'il donne ; cette ligne promet **un service précis, daté,
  à valeur immédiate**. Coût technique pour un solo : une table, un email, un lien de
  désinscription, et un job déclenché par le webhook Twitch `stream.online` — que le module
  `Media` consommera déjà. Aucune dépendance nouvelle.

### Livrable immédiat

`docs/ux/references/offline-mobile-375.html` — HTML statique important les vrais tokens CSS de
la Story 1.8 (aucune valeur en dur), viewport 375 px, quatre états dans le même fichier :

- **(A)** pré-consentement complet — *c'est la référence*
- **(B)** post-consentement, lecteur inline
- **(C)** fork pauvre — 1 source, 2 vidéos, aucun vertical
- **(D)** vide — `MODULE_LIVE_ENABLED=false`, zéro média, la review reprend le hero

Chaque bloc porte un commentaire le reliant à son FR / UX-DR.

---

## Alternatives écartées

- **L'agrégateur cinq réseaux.** C'est un linktree avec des vignettes : marché saturé, produit
  gratuit ailleurs, et reconstruit ici en cinq intégrations d'API. Le coût n'est pas le
  développement, c'est la maintenance perpétuelle transférée à chaque fork.
- **Le mur de vignettes en grille.** Rend au visiteur le feed qu'il vient de quitter, sans
  algorithme et avec moins de contenu. La rail horizontale promet une fin ; la grille promet
  l'infini et ne le tient pas.
- **L'embed inline systématique.** Multiplie les directives CSP et les fournisseurs du bandeau
  de consentement, pour un coût non linéaire — et retient le visiteur sur le site alors que
  l'objectif déclaré était de l'envoyer vers les réseaux du streamer.
