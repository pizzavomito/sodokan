# Guide de création de niveaux — Sodokan
TmZAS1ZWI6IeZPwC
Bienvenue ! Ce guide explique tout ce qu'il faut savoir pour créer tes propres niveaux dans `levels.txt`.
Pas besoin de coder. Il suffit de comprendre le format et de dessiner ta grille avec des caractères.

---

## Sommaire

1. [Structure d'un niveau](#1-structure-dun-niveau)
2. [Attributs](#2-attributs)
3. [Caractères de mur](#3-caractères-de-mur)
4. [Caractères de sol](#4-caractères-de-sol)
5. [Éléments de jeu](#5-éléments-de-jeu)
6. [La section FLOORS](#6-la-section-floors)
7. [Rotations manuelles](#7-rotations-manuelles)
8. [Rotations automatiques par patterns](#8-rotations-automatiques-par-patterns)
9. [Exemple complet commenté](#9-exemple-complet-commenté)
10. [Règles importantes](#10-règles-importantes)

---

## 1. Structure d'un niveau

Un niveau commence par une ligne `LEVEL_NOM:` et se termine par `END`.

```
LEVEL_MONNOM:
level_name=Mon Premier Niveau
#########
#P.....D#
#########
END
```

- **`LEVEL_NOM`** : identifiant unique du niveau (lettres, chiffres, `_`). Exemple : `LEVEL_5`, `LEVEL_HANGAR`
- Le `:` à la fin du nom de niveau active la lecture des **attributs**
- Les niveaux sont chargés dans l'**ordre d'apparition** dans le fichier

---

## 2. Attributs

Les attributs se placent entre la ligne `LEVEL_NOM:` et le début de la grille.
Format : `clé=valeur` (une par ligne).

### `level_name` — Nom affiché

Texte affiché dans l'interface pendant le niveau.

```
level_name=Entrepôt A1
```

---

### `default_ground` — Sol par défaut

Sol utilisé pour toutes les cases qui ne sont pas un caractère de sol explicite.
Par défaut : `.` (sol bleu).

```
default_ground=,
```

> **Astuce :** Si tu mets `default_ground=,`, toutes les cases "vides" (derrière les caisses, le joueur, etc.) seront du sol marron.

---

### `override_ground` — Sol forcé partout

Comme `default_ground`, mais **remplace même les caractères de sol** dans la grille.
Utile pour changer l'ambiance visuelle sans réécrire la grille.

```
override_ground=.
```

---

### `override_wall` — Mur forcé partout

Force tous les murs de la grille à utiliser le même tileset, quel que soit le caractère.

```
override_wall=#
```

---

### `text` — Dialogue tutoriel

Affiche une bulle de dialogue quand le niveau commence.
Tu peux en mettre plusieurs (elles s'affichent dans l'ordre).
Supporte les balises BBCode : `[b]texte en gras[/b]`.

```
text = Bienvenue ! 👋
text = Pousse les caisses sur les marques au sol.
text = Utilise [b]Z[/b] pour annuler un mouvement.
```

---

### `rot` — Rotation manuelle d'une tuile

Force la rotation d'un mur à une position précise de la grille.
Format : `rot=colonne,ligne,angle`
Les coordonnées commencent à `0` depuis le coin haut-gauche de la grille.
Angles disponibles : `0`, `90`, `180`, `270`.

```
rot=3,1,180
rot=7,2,90
```

> La rotation écrase ce que le système automatique aurait calculé.

---

## 3. Caractères de mur

Les murs sont des cases infranchissables. Chaque caractère correspond à un tileset visuel différent.

| Char | Tileset |
|------|---------|
| `#` | Mur standard (brique) |
| `&` | Mur pierre sombre |
| `@` | Mur alternatif |
| `%` | Mur alternatif 2 |
| `\|` | Mur vertical |
| `_` | Mur bas / entrée |
| `[` | Coin gauche d'arche |
| `]` | Coin droit d'arche |
| `(` | Arc gauche |
| `-` | Arc milieu |
| `)` | Arc droit |
| `<` | Variante arc gauche |
| `=` | Variante arc milieu |
| `>` | Variante arc droit |

**Exemple de grille avec différents murs :**
```
###########
#.........&
#.........&
#WWWWWWWWW&
&&&&&&&&&&&
```

> Le caractère `_` est aussi utilisé comme **entrée latérale** (le joueur peut venir de ce côté).

---

## 4. Caractères de sol

Le sol est la surface sur laquelle le joueur se déplace.

| Char | Rendu | Remarque |
|------|-------|----------|
| `.` | Sol bleu (défaut) | |
| `,` | Sol marron | |
| `:` | Sol pierre | |
| `/` | Sol désert | |
| `;` | Sol aléatoire | Choisit une texture au hasard parmi 4 variantes |

Les caractères de sol peuvent être utilisés **directement dans la grille principale** ou dans la **section FLOORS** (voir §6).

**Exemple :**
```
#########
#...,,,,#
#...,,,,#
#...;,,,#
#########
```

---

## 5. Éléments de jeu

### Joueur

| Char | Rôle |
|------|------|
| `P` | Position de départ du joueur |

Il doit y en avoir **exactement un** par niveau.

---

### Porte

| Char | Rôle |
|------|------|
| `D` | Porte de sortie |

La porte s'ouvre quand toutes les caisses sont sur leurs cibles.

---

### Caisses (MAJUSCULES)

| Char | Type | Description |
|------|------|-------------|
| `W` | Bois | Caisse standard, légère |
| `M` | Métal | Lourde, peut bloquer |
| `R` | Rouge | Doit aller sur cible rouge |
| `G` | Verte | Doit aller sur cible verte |
| `B` | Bleue | Doit aller sur cible bleue |
| `X` | Radioactive | Comporte des effets spéciaux |
| `N` | Magnétique | Attire/déplace d'autres caisses |
| `E` | Explosive | Explose et déclenche une réaction en chaîne |

---

### Cibles (minuscules)

Les cibles sont les marques au sol sur lesquelles placer les caisses.
Chaque caisse colorée doit aller sur la **cible de même couleur**.

| Char | Cible pour |
|------|-----------|
| `w` | Caisse Bois |
| `m` | Caisse Métal |
| `r` | Caisse Rouge |
| `g` | Caisse Verte |
| `b` | Caisse Bleue |
| `x` | Caisse Radioactive |
| `n` | Caisse Magnétique |

**Exemple simple :**
```
#######
#P.W.##
#..w.D#
#######
```
> Le joueur pousse la caisse bois (`W`) sur la cible bois (`w`), puis la porte (`D`) s'ouvre.

---

### Téléporteurs

| Char | Rôle |
|------|------|
| `1` | Téléporteur A (lié au téléporteur `2`) |
| `2` | Téléporteur B (lié au téléporteur `1`) |

En entrant dans `1`, on sort par `2` (et inversement).
Attention : un seul couple `1`/`2` par niveau.

---

### Collectibles

| Char | Objet | Effet |
|------|-------|-------|
| `!` | Batterie (undo) | Donne des batteries pour l'annulation |
| `~` | Batterie cachée | Idem, mais invisible (easter egg) |
| `+` | Vie | Donne un cœur supplémentaire |
| `^` | Vie cachée | Idem, mais invisible (easter egg) |

> Les collectibles ne réapparaissent pas une fois ramassés.

---

### Mur secret

| Char | Rôle |
|------|------|
| `$` | Mur secret (easter egg) |

Ressemble à un mur mais cache quelque chose.

---

## 6. La section FLOORS

La section `FLOORS` permet de définir une grille de sol indépendante de la grille principale.
Elle a la **priorité maximale** sur tout autre réglage de sol.

### Placement

Le bloc `FLOORS:` peut être placé **dans le même bloc** que le niveau, ou **après un END séparé**.

**Dans le même bloc :**
```
LEVEL_MON_NIVEAU:
level_name=Test
#########
#P.....D#
#########

FLOORS:
,,,,,,,,,
,....,,,,
,,,,,,,,,
END
```

**Dans un bloc séparé :**
```
LEVEL_MON_NIVEAU:
level_name=Test
#########
#P.....D#
#########
END

FLOORS:
,,,,,,,,,
,....,,,,
,,,,,,,,,
END
```

### Règles

- La grille FLOORS doit avoir les **mêmes dimensions** que la grille principale
- Chaque case de FLOORS remplace le sol de la case correspondante
- Utilise les mêmes caractères de sol que la grille principale (`.`, `,`, `:`, `/`, `;`)

**Exemple avec une zone en pierres au milieu :**
```
LEVEL_ZONE:
level_name=Zone mixte
default_ground=,
###########
#P.......D#
#.........#
#.........#
###########

FLOORS:
,,,,,,,,,,,
,,,,....,,,
,,,,....,,,
,,,,,,,,,,,
,,,,,,,,,,,
END
```
> Résultat : la zone centrale sera en sol `.` (bleu), le reste en `,` (marron).

---

## 7. Rotations manuelles

Certains tilesets de mur peuvent être **tournés** pour créer des formes (arches, cadres...).

### Via l'attribut `rot=`

```
LEVEL_ARCHE:
rot=3,1,180
rot=4,1,180
######
#P..D#
##(-)#
######
END
```

**Syntaxe :** `rot=colonne,ligne,angle`

- `colonne` : position horizontale (0 = gauche)
- `ligne` : position verticale (0 = haut)
- `angle` : `0` | `90` | `180` | `270`

### Visualiser les coordonnées

```
Col :  0 1 2 3 4 5
       # # # # # #   ← ligne 0
       # P . . . #   ← ligne 1
       # # # # # #   ← ligne 2
```

> Le `rot=` écrase tout calcul automatique pour la tuile ciblée.

---

## 8. Rotations automatiques par patterns

Pour les tilesets d'arche `(`, `-`, `)`, la rotation s'applique **automatiquement** quand ils forment une séquence reconnue dans la grille.

### Patterns horizontaux (même ligne)

| Séquence | Rotation appliquée |
|----------|-------------------|
| `)-(`   | 180° (arche inversée) |
| `>=(` | 180° |

**Exemple :**
```
########
#P....D#
#)--(--#   ← )-( détecté → rotation 180° automatique
########
```

### Patterns verticaux (même colonne)

| Séquence (haut→bas) | Rotation appliquée |
|---------------------|-------------------|
| `(` / `-` / `)` | 270° (arche verticale) |

**Exemple :**
```
##(##
##-##   ← colonne : (, -, ) → rotation 270° automatique
##)##
#P..D
#####
```

> Les patterns explicites ont **priorité sur** la rotation automatique par voisins.
> La rotation automatique par voisins sert de fallback quand aucun pattern ne correspond.

---

## 9. Exemple complet commenté

```
LEVEL_ENTREPOT_B1:
level_name=Entrepôt B1
default_ground=,        ← sol marron par défaut
rot=9,1,90              ← rotation manuelle du mur en (9,1)
text = Pousse chaque caisse sur sa cible ! 💪
text = Commence par la caisse [b]rouge[/b].

#############
#WWWW..RRR..&    ← caisses Bois et Rouge
#wwww......R&    ← cibles Bois en bas à gauche
#M....rrrr..&    ← caisse Métal, cibles Rouge
#m..........&    ← cible Métal
_P..........D    ← joueur à gauche, porte à droite
#############

FLOORS:
,,,,,,,,,,,,,
,....;;;;.,,,
,....;;;;.,,,
,....,,,,.,,,
,,,,,,,,,,,,,
,,,,,,,,,,,,,
,,,,,,,,,,,,,
END
```

**Ce que ça donne :**
- Sol marron partout sauf dans la zone centrale (sol aléatoire `;` et bleu `.`)
- 4 caisses Bois + 3 caisses Rouge + 1 caisse Métal
- Cibles correspondantes à chaque caisse
- Dialogue au démarrage
- Mur rotatif en position (9,1)

---

## 10. Règles importantes

### Obligatoires
- Chaque niveau doit avoir exactement **un `P`** (joueur)
- Chaque niveau doit avoir exactement **un `D`** (porte)
- Toute caisse colorée (R, G, B...) doit avoir **une cible de même type** (r, g, b...)
- Le nombre de caisses et de cibles **doit être égal** pour que le niveau soit faisable

### Recommandées
- Entourer la grille de `#` pour éviter que le joueur "sorte" du niveau
- Garder les noms de niveaux uniques (si deux niveaux ont le même `LEVEL_NOM`, seul le premier compte)
- Tester régulièrement en lançant le jeu

### Ce qui est ignoré
- Les caractères inconnus (ni mur, ni sol, ni élément) sont **silencieusement ignorés**
- Les attributs inconnus sont stockés mais n'ont aucun effet
- `glitch=` est parsé mais non fonctionnel actuellement
- Le caractère `T` n'a aucun effet

### Ordre des priorités pour le sol

```
FLOORS: grid (priorité 1, la plus haute)
  ↓ si absent
override_ground (priorité 2)
  ↓ si absent
Caractère de sol dans la grille principale (priorité 3)
  ↓ si absent
default_ground (priorité 4, valeur par défaut : ".")
```

---

*Doc générée pour Sodokan — mise à jour selon les fonctionnalités actuelles du moteur.*
