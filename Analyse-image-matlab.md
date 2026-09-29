# Visualisation topographique — TIFF vers PNG

Ce dépôt regroupe trois scripts MATLAB permettant de convertir des fichiers
topographiques `.tif` / `.tiff` en cartes de chaleur (heatmaps) exportées en
PNG. Ils partagent une même architecture (configuration centralisée, mode
« image unique » ou « batch », détection automatique du type de fichier) mais
diffèrent par le pipeline de traitement appliqué aux données.

---

## Sommaire

- [Scripts disponibles](#scripts-disponibles)
- [Prérequis](#prérequis)
- [Configuration commune](#configuration-commune)
- [1. `heatmap-lineiques-zoom.m`](#1-heatmap-lineiques-zoomm)
- [2. `heatmap-lineiques-brute.m`](#2-heatmap-lineiques-brutem)
- [3. `heatmap-cylindres-filtred.m`](#3-heatmap-cylindres-filtredm)
- [Comparaison rapide](#comparaison-rapide)
- [Conventions de nommage des fichiers](#conventions-de-nommage-des-fichiers)
- [Notes et dépannage](#notes-et-dépannage)

---

## Scripts disponibles

| Script | Échantillon visé | Traitement principal |
|---|---|---|
| `heatmap-lineiques-zoom.m` | Surfaces linéiques (zoom manuel) | Débruitage gaussien/médian + sur-échantillonnage bicubique |
| `heatmap-lineiques-brute.m` | Surfaces linéiques (sans prétraitement) | Sur-échantillonnage bicubique uniquement |
| `heatmap-cylindres-filtred.m` | Échantillons cylindriques (tranches 90°) | Crop auto + suppression d'artefacts + filtre bilatéral + déroulement optionnel |

---

## Prérequis

- **MATLAB** avec les toolboxes suivantes :
  - *Image Processing Toolbox* (`imgaussfilt`, `medfilt2`, `imresize`, `imbilatfilt`, `strel`, `imdilate`, `imclose`, `imopen`, `bwlabel`, `regionprops`, `interp2`, …)
- `imbilatfilt` requiert **R2018a** ou plus récent (un fallback gaussien est prévu).
- Les données brutes des TIFF sont supposées être en **mètres** : elles sont converties en **µm** à l'affichage (`cfg.UNIT_FACTOR = 1e6`).

---

## Configuration commune

Les trois scripts partagent la même structure de configuration `cfg` et les
mêmes conventions :

### Dossiers / fichiers

```matlab
cfg.INPUT_FOLDER  = '';      % dossier source (mode batch)
cfg.INPUT_FILE    = '';      % fichier unique (mode single)
cfg.OUTPUT_FOLDER = '';      % dossier de destination des PNG
cfg.RECURSIVE     = false;   % parcours récursif des sous-dossiers
cfg.PROCESS_MODE  = '';      % 'single', 'batch' ou '' (fenêtre de dialogue)
