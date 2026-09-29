# README — Heatmaps de surfaces topographiques (TIFF → PNG)

Ce dépôt regroupe **trois scripts Python** complémentaires permettant de transformer des fichiers topographiques `.tif` / `.tiff` (issus par exemple d'un profilomètre optique ou d'un microscope confocal) en **cartes de chaleur (heatmaps) exportées en PNG**, prêtes à être intégrées dans des rapports ou publications.

Les trois scripts partagent la même philosophie :

- entrée : un fichier TIFF unique **ou** un dossier complet (mode *batch*) ;
- sortie : un PNG par fichier, avec barre de couleur, axes physiques (mm) et titre ;
- configuration par constantes en haut de fichier (pas de ligne de commande à retenir) ;
- interface graphique minimale (Tkinter) pour choisir les dossiers/fichiers.

Chaque variante correspond à un **niveau de traitement croissant** :

| Script | Rôle | Traitements appliqués |
|---|---|---|
| `heatmap-lineiques-brute.py` | Rendu brut | Lecture + sur-échantillonnage bicubique |
| `heatmap-lineiques-zoom.py` | Rendu débruité + zoom | Débruitage (gaussien/médian) + sur-échantillonnage + zoom manuel |
| `heatmap-cylindres-filtred.py` | Échantillons cylindriques | Crop auto, suppression d'artefacts verticaux, filtre bilatéral, déroulement cylindrique optionnel |

---

## Table des matières

1. [Prérequis](#1-prérequis)
2. [Installation](#2-installation)
3. [Utilisation générale](#3-utilisation-générale)
4. [Script 1 — `heatmap-lineiques-brute.py`](#4-script-1--heatmap-lineiques-brutepy)
5. [Script 2 — `heatmap-lineiques-zoom.py`](#5-script-2--heatmap-lineiques-zoompypy)
6. [Script 3 — `heatmap-cylindres-filtred.py`](#6-script-3--heatmap-cylindres-filtredpy)
7. [Paramètres communs](#7-paramètres-communs)
8. [Détection du type de fichier](#8-détection-du-type-de-fichier)
9. [Conversion des unités et axes physiques](#9-conversion-des-unités-et-axes-physiques)
10. [Dépannage](#10-dépannage)
11. [Structure du dépôt suggérée](#11-structure-du-dépôt-suggérée)

---

## 1. Prérequis

- **Python 3.8+**
- Système d'exploitation : Windows / Linux / macOS (Tkinter requis pour les boîtes de dialogue)

### Bibliothèques Python

| Bibliothèque | Obligatoire | Rôle |
|---|---|---|
| `numpy` | ✅ | Calcul numérique |
| `matplotlib` | ✅ | Génération des heatmaps |
| `scipy` | ✅ | Interpolation, filtres, morphologie |
| `tifffile` | recommandé | Lecture rapide et fiable des TIFF |
| `Pillow` | fallback | Lecture TIFF si `tifffile` absent |
| `scikit-image` | optionnel | Filtre bilatéral (script cylindres) |
| `tkinter` | ✅ | Boîtes de dialogue (fourni avec Python) |

---

## 2. Installation

### Environnement virtuel recommandé

```bash
python -m venv .venv
# Windows
.venv\Scripts\activate
# Linux / macOS
source .venv/bin/activate
```

### Installation des dépendances

```bash
pip install numpy matplotlib scipy tifffile Pillow scikit-image
```

> Sur Linux, si Tkinter n'est pas présent : `sudo apt install python3-tk`

---

## 3. Utilisation générale

Les trois scripts se lancent de la même façon :

```bash
python heatmap-lineiques-brute.py
python heatmap-lineiques-zoom.py
python heatmap-cylindres-filtred.py
```

Au lancement, le script :

1. Demande le **mode de traitement** dans une petite fenêtre :
   - *Une seule image*
   - *Batch (tout un dossier)*
2. Ouvre une boîte de dialogue pour choisir le fichier ou le dossier d'entrée ;
3. Ouvre une boîte de dialogue pour choisir le dossier de sortie ;
4. Traite chaque fichier et exporte un PNG par image ;
5. Affiche dans la console un récapitulatif (`n succès, n échecs`).

### Mode non-interactif (config en dur)

Pour éviter les boîtes de dialogue, il suffit de renseigner les constantes en haut de fichier :

```python
PROCESS_MODE   = "single"        # ou "batch"
INPUT_FILE     = r"C:\chemin\image.tif"
INPUT_FOLDER   = r"C:\chemin\dossier"
OUTPUT_FOLDER  = r"C:\chemin\sortie"
```

Si `PROCESS_MODE` et les chemins sont renseignés, aucune fenêtre ne s'ouvre.

---

## 4. Script 1 — `heatmap-lineiques-brute.py`

### Objectif

Afficher **tel quel** le contenu du TIFF, sans aucun débruitage ni correction. Idéal pour un rendu « brut » de contrôle ou une inspection rapide.

### Pipeline

```
TIFF  →  lecture  →  conversion m → µm  →  sur-échantillonnage bicubique (ordre 3)  →  imshow  →  PNG
```

### Paramètres clés

| Constante | Description | Défaut |
|---|---|---|
| `UNIT_FACTOR` | Facteur de conversion des unités brutes | `1e6` (m → µm) |
| `SAMPLE_WIDTH_MM` | Largeur physique de l'échantillon (mm) | `40.52` |
| `SAMPLE_HEIGHT_MM` | Hauteur physique de l'échantillon (mm) | `27.28` |
| `APPLY_SMOOTHING` | Active le sur-échantillonnage | `True` |
| `SMOOTH_FACTOR` | Facteur d'agrandissement | `4` |
| `SMOOTH_ORDER` | Ordre d'interpolation spline (`0`–`5`) | `3` (bicubique) |
| `VMIN` / `VMAX` | Plage fixe de la colorbar (µm), `None` = auto | `None` |
| `XLIM` / `YLIM` | Zoom manuel `(min, max)` en mm | `None` |
| `CMAP_ROUGHNESS` | Colormap pour les fichiers `roughness` | `"jet"` |
| `CMAP_ALIGNED` | Colormap pour les fichiers `aligned` | `"jet"` |
| `COLORBAR_ORIENTATION` | `"horizontal"` ou `"vertical"` | `"horizontal"` |

### Cas d'usage typiques

- Vérifier qu'un TIFF a bien été exporté sans artefact de lecture ;
- Comparer plusieurs échantillons à plage de couleur commune (`VMIN`/`VMAX` fixés) ;
- Zoom manuel sur une zone d'intérêt via `XLIM`/`YLIM`.

---

## 5. Script 2 — `heatmap-lineiques-zoom.py`

### Objectif

Version **débruitée et zoomable**. Conçu pour les surfaces « linéiques » (bandes, rainures, lignes de balayage) où le bruit haute fréquence ou le « grillage » du capteur vient polluer la lecture.

### Pipeline

```
TIFF  →  lecture  →  m→µm  →  débruitage  →  sur-échantillonnage bicubique  →  zoom manuel  →  PNG
```

### Débruitage (étape 1)

| Constante | Description | Défaut |
|---|---|---|
| `DENOISE_METHOD` | `"gaussian"`, `"median"` ou `None` | `"gaussian"` |
| `DENOISE_SIGMA` | Sigma du filtre gaussien (px) | `1.5` |
| `DENOISE_SIZE` | Taille du noyau médian (impair) | `3` |

- **Gaussien** : lissage doux, idéal pour le bruit continu de type « grillage ».
- **Médian** : meilleur pour supprimer les pixels aberrants (salt & pepper) sans flouter les bords.
- `None` : aucun débruitage (équivalent au script brut pour cette étape).

### Sur-échantillonnage (étape 2)

Identique au script brut : `SMOOTH_FACTOR`, `SMOOTH_ORDER`, `MAX_SMOOTHED_PIXELS`.

### Zoom manuel

```python
XLIM = (6, 20)    # plage horizontale en mm (ou en pixels)
YLIM = (0, 3.5)   # plage verticale en mm (ou en pixels)
```

⚠️ **Important** : si `XLIM`/`YLIM` sont plus petits que l'étendue réelle des données, `matplotlib` **n'étire pas** l'image, il **recadre** la vue (les zones hors cadre sont masquées, pas de bandes blanches). Contrairement au script cylindres, il n'y a pas de recadrage physique du tableau.

### Différences avec le script brut

| Aspect | Brut | Zoom |
|---|---|---|
| Débruitage | ❌ | ✅ gaussien ou médian |
| Zoom manuel | ✅ | ✅ |
| Coupe physique du tableau | ❌ | ❌ |
| Colormap par défaut | `jet` | `jet` |
| Cible | Rendu de contrôle | Surfaces linéiques bruitées |

---

## 6. Script 3 — `heatmap-cylindres-filtred.py`

### Objectif

Version **la plus avancée**, dédiée aux **échantillons cylindriques découpés en tranches de 90°** (ou tout autre format où les bords du capteur et les artefacts verticaux posent problème).

### Pipeline complet

```
TIFF
  →  lecture + m→µm
  →  crop intelligent des bords (auto / fraction / pixels)
  →  suppression des artefacts verticaux + interpolation
  →  [optionnel] déroulement cylindrique
  →  recadrage à la fenêtre XLIM/YLIM
  →  calcul de la plage de couleurs (IQR robuste)
  →  filtre bilatéral + upsampling
  →  imshow
  →  PNG
```

### 6.1 Crop des bords

| Constante | Description | Défaut |
|---|---|---|
| `CROP_ENABLED` | Active le crop | `True` |
| `CROP_MODE` | `"auto"`, `"fraction"` ou `"pixels"` | `"auto"` |
| `AUTO_CROP_SIGMA` | Seuil de détection en σ robuste (MAD) | `2.0` |
| `AUTO_CROP_MARGIN` | Marge de sécurité ajoutée (px) | `15` |
| `AUTO_CROP_MAX_FRACTION` | Fraction max de l'image pouvant être rognée | `0.35` |
| `CROP_TOP/BOTTOM/LEFT/RIGHT` | Valeurs pour mode `fraction` (0–0.5) ou `pixels` | `0.15/0.15/0.03/0.03` |

**Mode `auto`** : compare la médiane de chaque ligne/colonne à la médiane globale. Toute ligne/colonne aberrante (bande saturée, divergence capteur) est retirée.

### 6.2 Suppression des artefacts verticaux

Détecte les **traces fines verticales négatives** (rayures, chutes de signal) et les interpole horizontalement.

| Constante | Description | Défaut |
|---|---|---|
| `ARTIFACT_REMOVAL` | Active la suppression | `True` |
| `ARTIFACT_FILE_FILTER` | Ne traiter que les noms contenant ces chaînes | `["-AB-"]` |
| `ART_BG_WINDOW_MM` | Fenêtre du médian horizontal (mm) | `0.20` |
| `ART_K_SIGMA` | Seuil de détection (σ robuste). Baisser = plus sensible | `3.5` |
| `ART_CLOSE_MM` | Comble les trous verticaux (mm) | `0.30` |
| `ART_MIN_HEIGHT_MM` | Hauteur minimale d'une trace | `0.30` |
| `ART_MAX_WIDTH_MM` | Largeur maximale d'une trace | `0.08` |
| `ART_MIN_ASPECT` | Ratio hauteur/largeur minimal | `6.0` |
| `ART_MIN_FILL` | Taux de remplissage minimal | `0.20` |
| `ART_DILATE_MM` | Élargissement du masque (mm) | `0.02` |
| `ART_V_MARGIN_MM` | Prolongation verticale (mm) | `0.12` |
| `ART_SAVE_MASK` | Exporte le masque en PNG (debug) | `False` |

**Deux détecteurs combinés :**

- **A) par forme** : après fermeture morphologique verticale, on garde les objets fins, allongés et suffisamment remplis.
- **B) par profil de colonne** : on détecte les colonnes avec un excès de pixels fortement négatifs (rattrape les traces collées à un pore).

Le masque final est dilaté horizontalement et verticalement pour couvrir les bords pâles, puis les pixels masqués sont **interpolés linéairement** ligne par ligne.

### 6.3 Déroulement cylindrique (optionnel)

| Constante | Description | Défaut |
|---|---|---|
| `UNWRAP_ENABLED` | Active le déroulement | `False` |
| `UNWRAP_CENTER_X/Y` | Centre du cylindre (px). `None` = auto | `None` |
| `UNWRAP_R_INNER/OUTER` | Rayons intérieur/extérieur (px). `None` = auto | `None` |
| `UNWRAP_N_ANGLES` | Nombre de points angulaires | `1440` |
| `UNWRAP_N_RADII` | Nombre de points radiaux | `256` |

Transforme une image polaire (vue de dessus d'un cylindre) en une image cartésienne **angle × rayon** par échantillonnage `map_coordinates` (spline cubique). Les axes deviennent alors `Angle (°)` et `Rayon (px)`.

### 6.4 Filtre bilatéral

| Constante | Description | Défaut |
|---|---|---|
| `APPLY_SMOOTHING` | Active le lissage | `True` |
| `BILATERAL_SIGMA_COLOR` | Préserve les intensités (0.05–0.2) | `0.10` |
| `BILATERAL_SIGMA_SPATIAL` | Taille de la zone spatiale (px) | `5.0` |
| `BILATERAL_WIN_SIZE` | Taille du voisinage (impair) | `11` |
| `SMOOTH_FACTOR` | Facteur d'upsampling final | `3` |

> Le filtre bilatéral **préserve les pics isolés** tout en lissant le bruit de fond — c'est sa grande force par rapport à un gaussien classique, qui écrase les extrema locaux.

Nécessite `scikit-image` :
```bash
pip install scikit-image
```

### 6.5 Plage de couleurs robuste (IQR)

Contrairement aux scripts 1 et 2 qui utilisent les percentiles 1/99, ce script utilise la **méthode de Tukey** :

```
Q1, Q3 = percentiles 25, 75
IQR    = Q3 - Q1
vmin   = max(Q1 - 3·IQR, min)
vmax   = min(Q3 + 3·IQR, max)
```

Le facteur `3.0` est volontairement large pour ne pas couper les pics intéressants, tout en ignorant les outliers extrêmes. Un `[debug]` est affiché en console avec `min`, `Q1`, `med`, `Q3`, `max`, `vmin`, `vmax`.

### 6.6 Recadrage à la fenêtre (`FILL_AXES_LIMITS`)

Quand `FILL_AXES_LIMITS = True`, le tableau est **physiquement découpé** à la fenêtre `XLIM`/`YLIM` (en mm) **avant** le calcul de `vmin`/`vmax` et **avant** le lissage.

Conséquences :

- les bords hors fenêtre (bandes bleues, bouts de traces) ne polluent plus l'échelle de couleurs ;
- plus aucune zone blanche dans la figure ;
- si l'échantillon est **plus court** que la fenêtre, la partie disponible est **étirée** pour remplir tout le cadre.

---

## 7. Paramètres communs

### Habillage des figures

| Constante | Description | Défaut |
|---|---|---|
| `DPI` | Résolution de base | `200` |
| `TARGET_LONG_SIDE_INCHES` | Côté long cible (pouces) | `16.0` |
| `MIN_SHORT_SIDE_INCHES` | Côté court minimum (pouces) | `9.0` |
| `MAX_PIXELS_DIM` | Dimension max du PNG (px) | `20000` |
| `TITLE_FONTSIZE` | Taille du titre | `20` |
| `AXIS_LABEL_FONTSIZE` | Taille des labels d'axes | `16` |
| `TICK_FONTSIZE` | Taille des ticks | `14` |
| `CBAR_LABEL_FONTSIZE` | Taille du label de colorbar | `16` |
| `CBAR_TICK_FONTSIZE` | Taille des ticks de colorbar | `14` |

`compute_figsize` + `get_effective_dpi` garantissent un ratio correct et un PNG final sous `MAX_PIXELS_DIM`.

### Gestion des NaN

Tous les scripts remplacent les NaN par la moyenne (ou la médiane) avant le filtrage, afin d'éviter les artefacts d'interpolation.

### Détection du type de fichier

```python
"roughness" / "rugosit"  →  roughness
"aligned"                →  aligned
sinon                    →  unknown
```

| Type | Colormap | Label colorbar | Titre |
|---|---|---|---|
| `roughness` | `CMAP_ROUGHNESS` (défaut `jet`) | Rugosité (µm) | `… - Surface roughness map (vue de dessus)` |
| `aligned` | `CMAP_ALIGNED` (défaut `jet`) | Hauteur (µm) | `… - Aligned surface map (vue de dessus)` |
| `unknown` | `jet` | Valeur (µm) | Nom du fichier |

Pour `roughness`, une `TwoSlopeNorm` est appliquée si `vmin < 0 < vmax`, afin de centrer le zéro sur une couleur neutre.

### Résolution de la taille de pixel

Ordre de priorité :

1. `PIXEL_SIZE_MM` (constante config) ;
2. tags TIFF `XResolution` + `ResolutionUnit` ;
3. `SAMPLE_WIDTH_MM` / `SAMPLE_HEIGHT_MM` ;
4. sinon : axes en **pixels**.

---

## 8. Détection du type de fichier

Le type est déduit du **nom de fichier** (insensible à la casse) :

| Motif dans le nom | Type détecté |
|---|---|
| `roughness`, `rugosit` | `roughness` |
| `aligned` | `aligned` |
| autre | `unknown` |

Renommez vos fichiers en conséquence pour bénéficier des bons titres, labels et colormaps.

---

## 9. Conversion des unités et axes physiques

- Les TIFF bruts sont supposés être en **mètres** → conversion en **µm** via `UNIT_FACTOR = 1e6`.
- Si vos données sont déjà en µm : `UNIT_FACTOR = 1.0`.
- La taille de pixel est cherchée dans l'ordre décrit ci-dessus.
- ⚠️ Si vous utilisez `SAMPLE_WIDTH_MM` / `SAMPLE_HEIGHT_MM`, leur **rapport doit être égal à `n_cols / n_rows`** du TIFF, sinon `imshow` laisse des bandes blanches (l'image n'est pas déformée, mais le cadre l'est).

---

## 10. Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `scikit-image non installé` | `skimage` absent | `pip install scikit-image` |
| `[!] Taille de pixel introuvable` | Tags TIFF absents | Renseigner `PIXEL_SIZE_MM` ou `SAMPLE_WIDTH_MM`/`SAMPLE_HEIGHT_MM` |
| `[!] Crop trop agressif, ignoré` | `CROP_*` trop grands | Réduire les fractions ou passer en `CROP_MODE="auto"` |
| Bandes blanches autour de l'image | Ratio `SAMPLE_*` ≠ `n_cols/n_rows` | Corriger les dimensions ou laisser `PIXEL_SIZE_MM=None` |
| Image entièrement saturée (une seule couleur) | `VMIN`/`VMAX` fixes inadaptés | Mettre `VMIN=VMAX=None` pour auto |
| Pics écrasés après lissage | Filtre trop fort | Réduire `DENOISE_SIGMA`, ou augmenter `BILATERAL_SIGMA_COLOR` (script 3) |
| Traces verticales non supprimées | Seuil `ART_K_SIGMA` trop haut | Baisser à `3.0` puis `2.5` |
| Tkinter indisponible | Module manquant (Linux) | `sudo apt install python3-tk` |

---

## 11. Structure du dépôt suggérée

```
.
├── README.md
├── heatmap-lineiques-brute.py       # rendu brut
├── heatmap-lineiques-zoom.py        # débruitage + zoom
├── heatmap-cylindres-filtred.py     # pipeline cylindres complet
└── examples/
    ├── input/                       # quelques TIFF de démonstration
    └── output/                      # PNG générés
```

---

## Résumé express

| Besoin | Script recommandé |
|---|---|
| Voir un TIFF rapidement, sans retouche | `heatmap-lineiques-brute.py` |
| Surfaces linéiques bruitées + zoom ciblé | `heatmap-lineiques-zoom.py` |
| Échantillons cylindriques (90°), traces verticales, pics à préserver | `heatmap-cylindres-filtred.py` |

Les trois scripts sont **indépendants** et peuvent être utilisés seuls. Il est conseillé de **conserver une copie de la config** utilisée pour chaque jeu de résultats (les constantes en haut de fichier servent de journal de traitement).
