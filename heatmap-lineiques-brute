#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================================
 tiff_to_png.py
-----------------------------------------------------------------------------
 Lit tous les fichiers .tif / .tiff d'un dossier, les visualise (heatmap)
 selon leur type détecté à partir du nom de fichier :
     - "roughness"  -> carte de rugosité (colormap divergente centrée sur 0)
     - "aligned"    -> surface alignée (colormap séquentielle)
 puis exporte chaque figure en PNG dans un dossier de sortie.

 Les données brutes des TIFF sont en MÈTRES -> converties en µm à l'affichage
 (comme dans le script de référence : unit_factor = 1e6).

 Options réglables manuellement en haut du script (section CONFIG) :
     - VMIN / VMAX : plage de la barre de couleur (en µm)
     - XLIM / YLIM : zoom manuel sur une zone (mêmes unités que les axes)
     - PIXEL_SIZE_MM : taille de pixel pour convertir les axes X/Y en mm

 Toutes ces options sont à None par défaut (comportement automatique,
 pas de zoom, échelle de couleur auto-calée sur les données).

 Au lancement, une fenêtre s'ouvre pour choisir le dossier d'entrée puis
 le dossier de sortie (comme filedialog dans le script de référence).
=============================================================================
"""

import os
import glob
import traceback

import numpy as np
import matplotlib
matplotlib.use("Agg")  # pas d'affichage interactif, on exporte direct en fichier
import matplotlib.pyplot as plt
from matplotlib.colors import TwoSlopeNorm
from tkinter import Tk, filedialog
from scipy.ndimage import zoom as scipy_zoom

try:
    import tifffile
    _HAS_TIFFFILE = True
except ImportError:
    _HAS_TIFFFILE = False
    from PIL import Image


# =============================================================================
#                                   CONFIG
# =============================================================================

# --- Dossiers ----------------------------------------------------------------
# Laisser à None : une fenêtre s'ouvrira au lancement du script pour choisir
# le dossier d'entrée puis le dossier de sortie. Renseigner un chemin en dur
# permet de sauter la fenêtre correspondante (utile en automatisé).
INPUT_FOLDER = None            # ex : r"C:\Users\moi\Desktop\TIFF_a_traiter"
OUTPUT_FOLDER = None           # ex : r"C:\Users\moi\Desktop\PNG_export"
RECURSIVE = False              # chercher aussi dans les sous-dossiers ?

# --- Unité des données brutes -------------------------------------------------
# Les TIFF contiennent des hauteurs en MÈTRES -> conversion vers µm à l'affichage.
UNIT_FACTOR = 1e6      # m -> µm (mettre 1.0 si les données sont déjà en µm)
UNIT_LABEL = "µm"

# --- Taille de pixel / dimensions physiques -----------------------------------
# Utilisées pour afficher les axes X/Y en mm (comme sur l'image de référence).
# Le script essaie, dans l'ordre, jusqu'à ce que l'une des méthodes fonctionne :
#   1) PIXEL_SIZE_MM ci-dessous, si renseigné (mm/pixel, pixels carrés) ;
#   2) les métadonnées du TIFF (tags XResolution/ResolutionUnit), si présentes ;
#   3) SAMPLE_WIDTH_MM / SAMPLE_HEIGHT_MM ci-dessous, si renseignées : la taille
#      physique totale connue du champ scanné (comme dans le script de
#      référence : width_mm / height_mm), appliquée à TOUS les fichiers du lot,
#      indépendamment du nombre de pixels de chacun ;
#   4) à défaut, axes affichés en pixels (avec avertissement dans la console).
PIXEL_SIZE_MM = None          # ex : 0.05  (=> 1 pixel = 0.05 mm)
SAMPLE_WIDTH_MM = None        # ex : 34.96   (largeur physique totale, axe Y)
SAMPLE_HEIGHT_MM = None       # ex : 23.57   (hauteur physique totale, axe Z)

# --- Lissage / sur-échantillonnage (comme le script de référence) -------------
# Le script de référence sur-échantillonne les données (interpolation
# bicubique, scipy.ndimage.zoom, order=3) avant affichage, ce qui donne un
# rendu lisse au lieu du grain brut pixel par pixel. Activé par défaut ici.
APPLY_SMOOTHING = True
SMOOTH_FACTOR = 4        # facteur de sur-échantillonnage (comme "scale = 4" dans le script de référence)
SMOOTH_ORDER = 3         # ordre de l'interpolation (3 = bicubique)
# Garde-fou : si (n_lignes*facteur) x (n_colonnes*facteur) dépasse ce nombre
# de pixels, le facteur est réduit automatiquement pour éviter un calcul trop
# long / trop de mémoire sur les images déjà très grandes (ex: 5000+ px de large).
MAX_SMOOTHED_PIXELS = 40_000_000

# --- Plage de la barre de couleur (colorbar), en µm ---------------------------
# None = calage automatique (percentiles 1-99 des données).
VMIN = None            # ex : -100
VMAX = None            # ex : 100

# --- Zoom manuel (mêmes unités que les axes : mm si PIXEL_SIZE_MM est défini,
#     sinon en pixels) -----------------------------------------------------
XLIM = None            # ex : (5, 20)   -> zoom sur l'axe horizontal (Y sur le graph)
YLIM = None            # ex : (0, 10)   -> zoom sur l'axe vertical   (Z sur le graph)

# --- Colormaps -----------------------------------------------------------------
CMAP_ROUGHNESS = "jet"        # colormap divergente, centrée automatiquement sur 0
CMAP_ALIGNED = "jet"          # colormap séquentielle pour la surface alignée

# --- Colorbar -------------------------------------------------------------------
COLORBAR_ORIENTATION = "horizontal"   # "horizontal" ou "vertical"

# --- Habillage des figures ------------------------------------------------------
DPI = 200

# Taille de la figure : la plus grande dimension est fixée à TARGET_LONG_SIDE_INCHES,
# l'autre suit le ratio largeur/hauteur réel des données (aspect préservé),
# avec un minimum MIN_SHORT_SIDE_INCHES pour garder de la place aux titres/labels/colorbar.
# Augmenter ces valeurs agrandit l'image finale sans la déformer.
TARGET_LONG_SIDE_INCHES = 16.0
MIN_SHORT_SIDE_INCHES = 9.0
MAX_PIXELS_DIM = 20000

# --- Tailles de police (en points) -----------------------------------------------
# Volontairement généreuses pour rester lisibles même quand l'image finale
# est affichée en miniature.
TITLE_FONTSIZE = 20
AXIS_LABEL_FONTSIZE = 16
TICK_FONTSIZE = 14
CBAR_LABEL_FONTSIZE = 16
CBAR_TICK_FONTSIZE = 14

# =============================================================================
#                              FIN DE LA CONFIG
# =============================================================================


def select_folder(title: str) -> str:
    """Ouvre une fenêtre de sélection de dossier et retourne le chemin choisi."""
    root = Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    folder = filedialog.askdirectory(title=title)
    root.destroy()
    return folder


def resolve_folders():
    """
    Détermine le dossier d'entrée et le dossier de sortie :
    - si INPUT_FOLDER / OUTPUT_FOLDER sont renseignés en dur, on les utilise
      directement (pas de fenêtre) ;
    - sinon, on ouvre une fenêtre de sélection pour chacun.
    """
    input_folder = INPUT_FOLDER
    output_folder = OUTPUT_FOLDER

    if not input_folder:
        input_folder = select_folder("Sélectionner le dossier contenant les fichiers TIFF")
        if not input_folder:
            print("Aucun dossier d'entrée sélectionné. Arrêt.")
            raise SystemExit

    if not output_folder:
        output_folder = select_folder("Sélectionner le dossier de destination des PNG")
        if not output_folder:
            print("Aucun dossier de sortie sélectionné. Arrêt.")
            raise SystemExit

    return input_folder, output_folder


def detect_file_type(filename: str) -> str:
    """Détecte le type de fichier : 'roughness', 'aligned', ou 'unknown'."""
    name_lower = filename.lower()
    if "roughness" in name_lower or "rugosit" in name_lower:
        return "roughness"
    elif "aligned" in name_lower:
        return "aligned"
    else:
        return "unknown"


def load_tiff(path: str) -> np.ndarray:
    """Charge un fichier .tif/.tiff en tableau numpy 2D (float), en mètres."""
    if _HAS_TIFFFILE:
        arr = tifffile.imread(path)
    else:
        arr = np.array(Image.open(path))

    arr = np.asarray(arr).astype(np.float64)

    if arr.ndim == 3:  # image multi-canaux -> on garde le 1er canal
        arr = arr[..., 0]

    # Conversion m -> µm (ou facteur défini par l'utilisateur)
    arr = arr * UNIT_FACTOR

    return arr


def smooth_upsample(arr: np.ndarray) -> np.ndarray:
    """
    Sur-échantillonne arr par interpolation bicubique (comme le script de
    référence : scipy.ndimage.zoom, order=3), pour un rendu lisse au lieu du
    grain brut pixel par pixel. Le facteur est réduit automatiquement si le
    résultat dépasserait MAX_SMOOTHED_PIXELS.
    """
    if not APPLY_SMOOTHING:
        return arr

    # Gestion des NaN avant interpolation (comme le script de référence)
    if np.isnan(arr).any():
        mean_val = np.nanmean(arr)
        arr = np.nan_to_num(arr, nan=mean_val)

    n_rows, n_cols = arr.shape
    factor = SMOOTH_FACTOR
    total_pixels = (n_rows * factor) * (n_cols * factor)
    if total_pixels > MAX_SMOOTHED_PIXELS:
        # réduit le facteur pour rester sous la limite (jamais en dessous de 1)
        max_factor_sq = MAX_SMOOTHED_PIXELS / (n_rows * n_cols)
        factor = max(1.0, max_factor_sq ** 0.5)
        print(f"  [i] Facteur de lissage réduit automatiquement à {factor:.2f} "
              f"(image {n_cols}x{n_rows} trop grande pour x{SMOOTH_FACTOR}).")

    if factor <= 1:
        return arr

    return scipy_zoom(arr, factor, order=SMOOTH_ORDER)


def get_pixel_size_from_metadata(path: str):
    """
    Essaie de lire la taille de pixel (en mm) depuis les tags TIFF standards
    (XResolution + ResolutionUnit). Retourne None si l'info n'est pas présente
    ou pas exploitable.
    """
    if not _HAS_TIFFFILE:
        return None
    try:
        with tifffile.TiffFile(path) as tf:
            tags = tf.pages[0].tags
            x_res_tag = tags.get("XResolution")
            unit_tag = tags.get("ResolutionUnit")
            if x_res_tag is None:
                return None

            x_res_val = x_res_tag.value
            if isinstance(x_res_val, tuple) and len(x_res_val) == 2:
                num, den = x_res_val
                pixels_per_unit = (num / den) if den else None
            else:
                pixels_per_unit = float(x_res_val)

            if not pixels_per_unit:
                return None

            unit_code = unit_tag.value if unit_tag is not None else 2  # 2 = inch par défaut
            if unit_code == 2:      # pouce
                mm_per_unit = 25.4
            elif unit_code == 3:    # centimètre
                mm_per_unit = 10.0
            else:
                return None

            return mm_per_unit / pixels_per_unit
    except Exception:
        return None


def resolve_pixel_size_mm(path: str, arr: np.ndarray):
    """Détermine la taille de pixel en mm à utiliser pour ce fichier."""
    if PIXEL_SIZE_MM is not None:
        return PIXEL_SIZE_MM

    auto_value = get_pixel_size_from_metadata(path)
    if auto_value is not None:
        return auto_value

    return None


def resolve_extent(path: str, arr: np.ndarray):
    """
    Détermine l'extent (xmin, xmax, ymin, ymax) à utiliser pour imshow, et si
    les axes doivent être affichés en mm ou en pixels.
    Ordre de priorité : PIXEL_SIZE_MM -> métadonnées TIFF -> SAMPLE_WIDTH_MM /
    SAMPLE_HEIGHT_MM -> pixels (avec avertissement).
    Retourne (extent, is_mm).
    """
    n_rows, n_cols = arr.shape

    pixel_size_mm = resolve_pixel_size_mm(path, arr)
    if pixel_size_mm is not None:
        return (0, n_cols * pixel_size_mm, n_rows * pixel_size_mm, 0), True

    if SAMPLE_WIDTH_MM is not None and SAMPLE_HEIGHT_MM is not None:
        # Dimensions physiques totales connues (comme dans le script de
        # référence), appliquées telles quelles, indépendamment du nb de pixels.
        return (0, SAMPLE_WIDTH_MM, SAMPLE_HEIGHT_MM, 0), True

    print(f"  [!] Taille de pixel introuvable (ni PIXEL_SIZE_MM, ni métadonnées, "
          f"ni SAMPLE_WIDTH_MM/SAMPLE_HEIGHT_MM) pour "
          f"{os.path.basename(path)} -> axes affichés en pixels.")
    return (0, n_cols, n_rows, 0), False


def compute_figsize(extent):
    """
    Calcule une taille de figure (largeur, hauteur en pouces) en respectant le
    ratio largeur/hauteur des données (aspect préservé, pas de déformation),
    MAIS mise à l'échelle pour que la plus grande dimension soit
    TARGET_LONG_SIDE_INCHES.

    - La plus grande dimension est fixée à TARGET_LONG_SIDE_INCHES.
    - L'autre dimension suit le ratio, mais reste >= MIN_SHORT_SIDE_INCHES
      pour garder de la place aux titres/labels/colorbar.
    """
    x_span = abs(extent[1] - extent[0])
    y_span = abs(extent[2] - extent[3])
    if x_span == 0 or y_span == 0:
        return (TARGET_LONG_SIDE_INCHES, TARGET_LONG_SIDE_INCHES * 3 / 4)

    ratio = x_span / y_span  # > 1 si plus large que haut

    if ratio >= 1:
        width = TARGET_LONG_SIDE_INCHES
        height = width / ratio
        if height < MIN_SHORT_SIDE_INCHES:
            height = MIN_SHORT_SIDE_INCHES
            width = height * ratio
    else:
        height = TARGET_LONG_SIDE_INCHES
        width = height * ratio
        if width < MIN_SHORT_SIDE_INCHES:
            width = MIN_SHORT_SIDE_INCHES
            height = width / ratio

    return (width, height)


def get_effective_dpi(figsize):
    """
    Réduit le DPI si nécessaire pour que la plus grande dimension du PNG final
    ne dépasse pas MAX_PIXELS_DIM pixels (évite des fichiers énormes sur les
    échantillons très allongés).
    """
    largest_inches = max(figsize)
    dpi = DPI
    if largest_inches * dpi > MAX_PIXELS_DIM:
        dpi = MAX_PIXELS_DIM / largest_inches
    return dpi


def get_vrange(arr: np.ndarray):
    """Retourne (vmin, vmax) à utiliser pour la colorbar, en µm."""
    vmin = VMIN if VMIN is not None else float(np.nanpercentile(arr, 1))
    vmax = VMAX if VMAX is not None else float(np.nanpercentile(arr, 99))
    return vmin, vmax


def plot_tiff_to_png(tiff_path: str, output_folder: str):
    """Lit un fichier tiff, le visualise selon son type, exporte en PNG."""
    filename = os.path.basename(tiff_path)
    base_name = os.path.splitext(filename)[0]
    file_type = detect_file_type(filename)

    arr = load_tiff(tiff_path)
    extent, is_mm = resolve_extent(tiff_path, arr)
    vmin, vmax = get_vrange(arr)
    arr_plot = smooth_upsample(arr)
    figsize = compute_figsize(extent)
    effective_dpi = get_effective_dpi(figsize)

    fig, ax = plt.subplots(figsize=figsize, dpi=effective_dpi)

    if file_type == "roughness":
        # colormap divergente centrée sur 0 (comme sur l'image de référence)
        norm = TwoSlopeNorm(vmin=vmin, vcenter=0, vmax=vmax) if vmin < 0 < vmax else None
        im = ax.imshow(
            arr_plot, cmap=CMAP_ROUGHNESS, extent=extent, aspect="equal",
            norm=norm, vmin=None if norm else vmin, vmax=None if norm else vmax,
        )
        cbar_label = f"Rugosité ({UNIT_LABEL})"
        title = f"{base_name} - Surface roughness map (vue de dessus)"

    elif file_type == "aligned":
        im = ax.imshow(
            arr_plot, cmap=CMAP_ALIGNED, extent=extent, aspect="equal",
            vmin=vmin, vmax=vmax,
        )
        cbar_label = f"Hauteur ({UNIT_LABEL})"
        title = f"{base_name} - Aligned surface map (vue de dessus)"

    else:
        im = ax.imshow(
            arr_plot, cmap="jet", extent=extent, aspect="equal",
            vmin=vmin, vmax=vmax,
        )
        cbar_label = f"Valeur ({UNIT_LABEL})"
        title = f"{base_name} (type non reconnu)"

    # --- axes ---
    if is_mm:
        ax.set_xlabel("Y (mm)", fontsize=AXIS_LABEL_FONTSIZE)
        ax.set_ylabel("Z (mm)", fontsize=AXIS_LABEL_FONTSIZE)
    else:
        ax.set_xlabel("Y (px)", fontsize=AXIS_LABEL_FONTSIZE)
        ax.set_ylabel("Z (px)", fontsize=AXIS_LABEL_FONTSIZE)

    ax.set_title(title, fontsize=TITLE_FONTSIZE, fontweight="bold")
    ax.tick_params(axis="both", labelsize=TICK_FONTSIZE)

    # --- zoom manuel ---
    if XLIM is not None:
        ax.set_xlim(XLIM)
    if YLIM is not None:
        # l'axe Y est inversé (origine en haut) -> on respecte l'ordre demandé
        ax.set_ylim(max(YLIM), min(YLIM))

    # --- colorbar ---
    if COLORBAR_ORIENTATION == "horizontal":
        cbar = fig.colorbar(im, ax=ax, orientation="horizontal", location="bottom",
                             fraction=0.08, pad=0.12, shrink=0.9)
    else:
        cbar = fig.colorbar(im, ax=ax, orientation="vertical", fraction=0.046, pad=0.04)
    cbar.set_label(cbar_label, fontsize=CBAR_LABEL_FONTSIZE)
    cbar.ax.tick_params(labelsize=CBAR_TICK_FONTSIZE)

    os.makedirs(output_folder, exist_ok=True)
    out_path = os.path.join(output_folder, base_name + ".png")
    fig.savefig(out_path, dpi=effective_dpi, bbox_inches="tight", pad_inches=0.2)
    plt.close(fig)
    return out_path


def find_tiff_files(input_folder: str, recursive: bool = False):
    patterns = ["*.tif", "*.tiff", "*.TIF", "*.TIFF"]
    files = []
    for p in patterns:
        if recursive:
            files.extend(glob.glob(os.path.join(input_folder, "**", p), recursive=True))
        else:
            files.extend(glob.glob(os.path.join(input_folder, p)))
    return sorted(set(files))


def main():
    input_folder, output_folder = resolve_folders()

    print(f"Lecture des fichiers .tif/.tiff dans : {input_folder}")
    tiff_files = find_tiff_files(input_folder, RECURSIVE)

    if not tiff_files:
        print("Aucun fichier .tif/.tiff trouvé.")
        return

    print(f"{len(tiff_files)} fichier(s) trouvé(s).\n")

    n_ok, n_fail = 0, 0
    for path in tiff_files:
        try:
            out_path = plot_tiff_to_png(path, output_folder)
            file_type = detect_file_type(os.path.basename(path))
            print(f"[OK] {os.path.basename(path)}  (type={file_type})  -> {out_path}")
            n_ok += 1
        except Exception as e:
            print(f"[ERREUR] {os.path.basename(path)} : {e}")
            traceback.print_exc()
            n_fail += 1

    print(f"\nTerminé : {n_ok} succès, {n_fail} échec(s).")
    print(f"PNG exportés dans : {output_folder}")


if __name__ == "__main__":
    main()
