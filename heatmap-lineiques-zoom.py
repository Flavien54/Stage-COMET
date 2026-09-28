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

 Pipeline de lissage :
     1) Débruitage (filtre gaussien ou médian) pour effacer le "grillage"
        (bruit haute fréquence / lignes de balayage du capteur).
     2) Sur-échantillonnage bicubique pour un rendu lisse.

 Options réglables manuellement en haut du script (section CONFIG) :
     - DENOISE_METHOD / DENOISE_SIGMA / DENOISE_SIZE : débruitage
     - SMOOTH_FACTOR / SMOOTH_ORDER : sur-échantillonnage
     - VMIN / VMAX : plage de la barre de couleur (en µm), scalaires
     - XLIM / YLIM : zoom manuel, tuples de coordonnées (xmin, xmax) / (ymin, ymax)
     - PIXEL_SIZE_MM : taille de pixel pour convertir les axes X/Y en mm
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
from scipy.ndimage import gaussian_filter, median_filter

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
# le dossier d'entrée puis le dossier de sortie.
INPUT_FOLDER = None            # ex : r"C:\Users\moi\Desktop\TIFF_a_traiter"
OUTPUT_FOLDER = None           # ex : r"C:\Users\moi\Desktop\PNG_export"
RECURSIVE = False              # chercher aussi dans les sous-dossiers ?

# --- Unité des données brutes -------------------------------------------------
# Les TIFF contiennent des hauteurs en MÈTRES -> conversion vers µm à l'affichage.
UNIT_FACTOR = 1e6      # m -> µm (mettre 1.0 si les données sont déjà en µm)
UNIT_LABEL = "µm"

# --- Taille de pixel / dimensions physiques -----------------------------------
# Utilisées pour afficher les axes X/Y en mm. Le script essaie dans l'ordre :
#   1) PIXEL_SIZE_MM ci-dessous, si renseigné (mm/pixel, pixels carrés) ;
#   2) les métadonnées du TIFF (tags XResolution/ResolutionUnit), si présentes ;
#   3) SAMPLE_WIDTH_MM / SAMPLE_HEIGHT_MM ci-dessous, si renseignées ;
#   4) à défaut, axes affichés en pixels (avec avertissement dans la console).
#
# ⚠️ ATTENTION au ratio : si tu utilises SAMPLE_WIDTH_MM / SAMPLE_HEIGHT_MM,
# le rapport SAMPLE_WIDTH_MM / SAMPLE_HEIGHT_MM DOIT être égal à n_cols / n_rows
# du TIFF, sinon imshow laisse des bandes blanches (aspect="equal").
# En cas de doute, laisse ces deux variables à None : le script calcule
# automatiquement depuis les métadonnées ou affiche en pixels.
PIXEL_SIZE_MM = None          # ex : 0.05  (=> 1 pixel = 0.05 mm)
SAMPLE_WIDTH_MM = None        # ex : 20.0  (largeur physique totale, axe Y)
SAMPLE_HEIGHT_MM = None       # ex : 3.5   (hauteur physique totale, axe Z)
                              # ⚠️ doit respecter : H = W * n_rows / n_cols

# --- Lissage / sur-échantillonnage --------------------------------------------
# Le "grillage" visible sur les cartes de rugosité est un bruit haute fréquence
# (lignes de balayage du capteur). Pour l'éliminer :
#   1) on applique un filtre gaussien (ou médian) qui écrase le bruit périodique
#   2) PUIS on sur-échantillonne par interpolation bicubique pour un rendu doux.
APPLY_SMOOTHING = True

# --- Étape 1 : filtre anti-bruit ---------------------------------------------
# DENOISE_METHOD : "gaussian" (rapide, recommandé), "median" (préserve les bords
#                  mais plus lent), ou None pour désactiver.
# DENOISE_SIGMA  : écart-type du flou gaussien, en pixels.
#                  - 0.5 à 1.0 : léger (enlève le grain fin)
#                  - 1.5 à 3.0 : fort (enlève le grillage / lignes de balayage)
#                  - >3        : très fort (risque de lisser les vraies features)
# DENOISE_SIZE   : taille du noyau pour le filtre médian (impair : 3, 5, 7...).
DENOISE_METHOD = "gaussian"     # "gaussian", "median", ou None
DENOISE_SIGMA = 1.5             # utilisé si method == "gaussian"
DENOISE_SIZE = 3                # utilisé si method == "median"

# --- Étape 2 : sur-échantillonnage (rendu doux) ------------------------------
SMOOTH_FACTOR = 4               # facteur d'agrandissement
SMOOTH_ORDER = 3                # 3 = bicubique
MAX_SMOOTHED_PIXELS = 40_000_000

# --- Plage de la barre de couleur (colorbar), en µm ---------------------------
# None = calage automatique (percentiles 1-99 des données).
# VMIN et VMAX sont des SCALAIRES (en µm).
VMIN = None            # ex : -100
VMAX = None            # ex : 100

# --- Zoom manuel ---------------------------------------------------------------
# XLIM et YLIM sont des TUPLES de coordonnées dans les unités des axes :
#   - en mm si PIXEL_SIZE_MM ou SAMPLE_WIDTH_MM/SAMPLE_HEIGHT_MM est défini,
#   - en pixels sinon.
# None = pas de zoom (vue complète).
XLIM = (6,20)           # ex : (5.0, 20.0)  -> (xmin, xmax) sur l'axe horizontal (Y)
YLIM = (0,3.5)           # ex : (0.0, 10.0)  -> (ymin, ymax) sur l'axe vertical   (Z)

# --- Colormaps -----------------------------------------------------------------
CMAP_ROUGHNESS = "jet"        # colormap divergente, centrée automatiquement sur 0
CMAP_ALIGNED = "jet"          # colormap séquentielle pour la surface alignée

# --- Colorbar -------------------------------------------------------------------
COLORBAR_ORIENTATION = "horizontal"   # "horizontal" ou "vertical"

# --- Habillage des figures ------------------------------------------------------
DPI = 200

# Taille de figure : la plus grande dimension est fixée à TARGET_LONG_SIDE_INCHES,
# l'autre suit le ratio des données, avec un minimum MIN_SHORT_SIDE_INCHES.
TARGET_LONG_SIDE_INCHES = 16.0
MIN_SHORT_SIDE_INCHES = 9.0
MAX_PIXELS_DIM = 20000

# --- Tailles de police (en points) -----------------------------------------------
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


def denoise(arr: np.ndarray) -> np.ndarray:
    """
    Étape 1 : atténue le bruit haute fréquence (grillage, lignes de balayage).
    Utilise un filtre gaussien ou médian selon DENOISE_METHOD.
    """
    if DENOISE_METHOD is None:
        return arr

    # Remplace les NaN par la moyenne avant filtrage (sinon le filtre propage les NaN)
    if np.isnan(arr).any():
        mean_val = np.nanmean(arr)
        arr = np.nan_to_num(arr, nan=mean_val)

    if DENOISE_METHOD == "gaussian":
        if DENOISE_SIGMA and DENOISE_SIGMA > 0:
            return gaussian_filter(arr, sigma=DENOISE_SIGMA, mode="nearest")
        return arr

    elif DENOISE_METHOD == "median":
        size = DENOISE_SIZE if DENOISE_SIZE % 2 == 1 else DENOISE_SIZE + 1
        return median_filter(arr, size=size, mode="nearest")

    else:
        print(f"  [!] DENOISE_METHOD='{DENOISE_METHOD}' inconnu -> ignoré.")
        return arr


def smooth_upsample(arr: np.ndarray) -> np.ndarray:
    """
    Pipeline complet :
      1) Débruitage (gaussien ou médian) pour effacer le grillage.
      2) Sur-échantillonnage bicubique pour un rendu lisse.

    Le facteur de sur-échantillonnage est réduit automatiquement si le résultat
    dépasserait MAX_SMOOTHED_PIXELS.
    """
    if not APPLY_SMOOTHING:
        return arr

    # --- Étape 1 : débruitage ---
    arr = denoise(arr)

    # --- Étape 2 : sur-échantillonnage ---
    n_rows, n_cols = arr.shape
    factor = SMOOTH_FACTOR
    total_pixels = (n_rows * factor) * (n_cols * factor)
    if total_pixels > MAX_SMOOTHED_PIXELS:
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
    (XResolution + ResolutionUnit). Retourne None si l'info n'est pas présente.
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

            unit_code = unit_tag.value if unit_tag is not None else 2  # 2 = inch
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
    Retourne (extent, is_mm).
    """
    n_rows, n_cols = arr.shape

    pixel_size_mm = resolve_pixel_size_mm(path, arr)
    if pixel_size_mm is not None:
        return (0, n_cols * pixel_size_mm, n_rows * pixel_size_mm, 0), True

    if SAMPLE_WIDTH_MM is not None and SAMPLE_HEIGHT_MM is not None:
        return (0, SAMPLE_WIDTH_MM, SAMPLE_HEIGHT_MM, 0), True

    print(f"  [!] Taille de pixel introuvable (ni PIXEL_SIZE_MM, ni métadonnées, "
          f"ni SAMPLE_WIDTH_MM/SAMPLE_HEIGHT_MM) pour "
          f"{os.path.basename(path)} -> axes affichés en pixels.")
    return (0, n_cols, n_rows, 0), False


def compute_figsize(extent):
    """
    Calcule une taille de figure (largeur, hauteur en pouces) en respectant le
    ratio largeur/hauteur des données, avec la plus grande dimension fixée à
    TARGET_LONG_SIDE_INCHES.
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
    ne dépasse pas MAX_PIXELS_DIM pixels.
    """
    largest_inches = max(figsize)
    dpi = DPI
    if largest_inches * dpi > MAX_PIXELS_DIM:
        dpi = MAX_PIXELS_DIM / largest_inches
    return dpi


def get_vrange(arr: np.ndarray):
    """
    Retourne (vmin, vmax) à utiliser pour la colorbar, en µm.
    - VMIN et VMAX (CONFIG) sont des scalaires.
    - Si l'un des deux est None, on utilise le percentile 1 ou 99 des données.
    """
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

    # Pipeline : débruitage + sur-échantillonnage
    arr_plot = smooth_upsample(arr)

    figsize = compute_figsize(extent)
    effective_dpi = get_effective_dpi(figsize)

    fig, ax = plt.subplots(figsize=figsize, dpi=effective_dpi)

    if file_type == "roughness":
        # colormap divergente centrée sur 0
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

    # --- zoom manuel -----------------------------------------------------------
    if XLIM is not None:
        xmin, xmax = XLIM
        if xmin < xmax:
            ax.set_xlim(xmin, xmax)
        else:
            print(f"  [!] XLIM={XLIM} invalide (xmin >= xmax) -> ignoré.")
    if YLIM is not None:
        ymin, ymax = YLIM
        if ymin < ymax:
            # axe Y inversé (origine en haut) : on respecte l'ordre demandé
            ax.set_ylim(max(ymin, ymax), min(ymin, ymax))
        else:
            print(f"  [!] YLIM={YLIM} invalide (ymin >= ymax) -> ignoré.")

    # --- colorbar ---
    if COLORBAR_ORIENTATION == "horizontal":
        cbar = fig.colorbar(im, ax=ax, orientation="horizontal", location="bottom",
                            fraction=0.08, pad=0.12, shrink=0.9)
    else:
        cbar = fig.colorbar(im, ax=ax, orientation="vertical",
                            fraction=0.046, pad=0.04)
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
