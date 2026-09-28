#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================================
 tiff_to_png.py
-----------------------------------------------------------------------------
 Lit tous les fichiers .tif / .tiff d'un dossier, les visualise (heatmap)
 selon leur type détecté à partir du nom de fichier, puis exporte en PNG.

 Adapté aux ÉCHANTILLONS CYLINDRIQUES découpés en tranches de 90° :
   - crop automatique des bords (divergence capteur / bandes saturées)

 Les données brutes des TIFF sont en MÈTRES -> converties en µm à l'affichage.
=============================================================================
"""

import os
import glob
import traceback

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import TwoSlopeNorm
from tkinter import Tk, filedialog
from scipy.ndimage import zoom as scipy_zoom
from scipy.ndimage import map_coordinates

try:
    import tifffile
    _HAS_TIFFFILE = True
except ImportError:
    _HAS_TIFFFILE = False
    from PIL import Image


# =============================================================================
#                                   CONFIG
# =============================================================================

INPUT_FOLDER = None
OUTPUT_FOLDER = None
RECURSIVE = False

UNIT_FACTOR = 1e6
UNIT_LABEL = "µm"

PIXEL_SIZE_MM = None
SAMPLE_WIDTH_MM = None
SAMPLE_HEIGHT_MM = None

# --- Lissage --------------------------------------------------------------
APPLY_SMOOTHING = True
SMOOTH_FACTOR = 4
SMOOTH_ORDER = 3
MAX_SMOOTHED_PIXELS = 40_000_000

# --- Crop des bords --------------------------------------------------------
# Trois modes :
#   "auto"     : détecte les lignes/colonnes aberrantes (bandes saturées en
#                haut/bas, colonnes décalées sur les côtés) en comparant leur
#                médiane à la médiane globale.
#   "fraction" : crop fixe en fraction de la dimension (0-0.5).
#   "pixels"   : crop fixe en nombre de pixels.
CROP_ENABLED = True
CROP_MODE = "auto"              # "auto", "fraction" ou "pixels"

# --- Paramètres du crop AUTO ----------------------------------------------
# Une ligne/colonne est considérée "aberrante" si sa médiane dépasse la
# médiane globale de plus de AUTO_CROP_SIGMA * MAD_globale (écart-type robuste).
# On retire ensuite ces lignes/colonnes, plus AUTO_CROP_MARGIN pixels de marge.
AUTO_CROP_SIGMA = 3.0           # seuil de détection (en MAD robustes)
AUTO_CROP_MARGIN = 5            # pixels de marge supplémentaires retirés
AUTO_CROP_MAX_FRACTION = 0.25   # ne jamais retirer plus de 25 % d'un côté

# --- Paramètres du crop FRACTION / PIXELS ----------------------------------
CROP_TOP = 0.05                 # 5 % en haut
CROP_BOTTOM = 0.05              # 5 % en bas
CROP_LEFT = 0.05                # 5 % à gauche
CROP_RIGHT = 0.05               # 5 % à droite

# --- Déroulement cylindrique -----------------------------------------------
UNWRAP_ENABLED = False
UNWRAP_CENTER_X = None
UNWRAP_CENTER_Y = None
UNWRAP_R_INNER = None
UNWRAP_R_OUTER = None
UNWRAP_N_ANGLES = 1440
UNWRAP_N_RADII = 256

# --- Barre de couleur ------------------------------------------------------
# Calage automatique : percentiles robustes.
#   1 - 99.5  : bon compromis (garde la dynamique utile ET laisse apparaître
#               les pics intéressants sur les surfaces rugueuses type AB)
#   2 - 98    : plus "serré" mais écrase la dynamique (max à ~40 µm)
#  0.5 - 99.9 : proche du max absolu, peut être sensible aux outliers
VRANGE_PERCENTILE_LOW = 1.0
VRANGE_PERCENTILE_HIGH = 99.5

# Forcer une plage fixe (appliquée à TOUS les fichiers si non None)
VMIN = None
VMAX = None

XLIM = None
YLIM = None

CMAP_ROUGHNESS = "jet"
CMAP_ALIGNED = "jet"

COLORBAR_ORIENTATION = "horizontal"

DPI = 200
TARGET_LONG_SIDE_INCHES = 16.0
MIN_SHORT_SIDE_INCHES = 9.0
MAX_PIXELS_DIM = 20000

TITLE_FONTSIZE = 20
AXIS_LABEL_FONTSIZE = 16
TICK_FONTSIZE = 14
CBAR_LABEL_FONTSIZE = 16
CBAR_TICK_FONTSIZE = 14

# =============================================================================
#                              FIN DE LA CONFIG
# =============================================================================


def select_folder(title: str) -> str:
    root = Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    folder = filedialog.askdirectory(title=title)
    root.destroy()
    return folder


def resolve_folders():
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
    name_lower = filename.lower()
    if "roughness" in name_lower or "rugosit" in name_lower:
        return "roughness"
    elif "aligned" in name_lower:
        return "aligned"
    else:
        return "unknown"


def load_tiff(path: str) -> np.ndarray:
    if _HAS_TIFFFILE:
        arr = tifffile.imread(path)
    else:
        arr = np.array(Image.open(path))

    arr = np.asarray(arr).astype(np.float64)
    if arr.ndim == 3:
        arr = arr[..., 0]
    arr = arr * UNIT_FACTOR
    return arr


# =============================================================================
#                       CROP INTELLIGENT DES BORDS
# =============================================================================

def _robust_sigma(values: np.ndarray) -> float:
    """Écart-type robuste via MAD (Median Absolute Deviation)."""
    med = np.median(values)
    mad = np.median(np.abs(values - med))
    return 1.4826 * mad if mad > 0 else 0.0


def _detect_aberrant_edges(arr: np.ndarray):
    """
    Détecte les lignes (haut/bas) et colonnes (gauche/droite) aberrantes en
    comparant leur médiane à la médiane globale.

    Retourne (top, bottom, left, right) = nombre de lignes/colonnes à retirer
    de chaque côté.
    """
    finite = np.isfinite(arr)
    if not finite.any():
        return 0, 0, 0, 0

    global_med = np.nanmedian(arr)
    global_sigma = _robust_sigma(arr[finite])
    if global_sigma <= 0:
        return 0, 0, 0, 0

    threshold_high = global_med + AUTO_CROP_SIGMA * global_sigma
    threshold_low = global_med - AUTO_CROP_SIGMA * global_sigma

    n_rows, n_cols = arr.shape

    # Médianes par ligne et par colonne (en ignorant les NaN)
    row_meds = np.nanmedian(arr, axis=1)
    col_meds = np.nanmedian(arr, axis=0)

    def count_from_start(meds, thr_hi, thr_lo, max_frac):
        max_n = int(len(meds) * max_frac)
        n = 0
        for v in meds[:max_n]:
            if not np.isfinite(v):
                n += 1
                continue
            if v > thr_hi or v < thr_lo:
                n += 1
            else:
                break
        return n

    def count_from_end(meds, thr_hi, thr_lo, max_frac):
        max_n = int(len(meds) * max_frac)
        n = 0
        for v in meds[::-1][:max_n]:
            if not np.isfinite(v):
                n += 1
                continue
            if v > thr_hi or v < thr_lo:
                n += 1
            else:
                break
        return n

    top = count_from_start(row_meds, threshold_high, threshold_low, AUTO_CROP_MAX_FRACTION)
    bottom = count_from_end(row_meds, threshold_high, threshold_low, AUTO_CROP_MAX_FRACTION)
    left = count_from_start(col_meds, threshold_high, threshold_low, AUTO_CROP_MAX_FRACTION)
    right = count_from_end(col_meds, threshold_high, threshold_low, AUTO_CROP_MAX_FRACTION)

    # Marge de sécurité
    top += AUTO_CROP_MARGIN
    bottom += AUTO_CROP_MARGIN
    left += AUTO_CROP_MARGIN
    right += AUTO_CROP_MARGIN

    # Ne pas dépasser 1/3 de chaque dimension
    top = min(top, n_rows // 3)
    bottom = min(bottom, n_rows // 3)
    left = min(left, n_cols // 3)
    right = min(right, n_cols // 3)

    return top, bottom, left, right


def crop_borders(arr: np.ndarray) -> np.ndarray:
    """Retire les bords aberrants de l'image."""
    if not CROP_ENABLED:
        return arr

    n_rows, n_cols = arr.shape

    if CROP_MODE == "auto":
        top, bottom, left, right = _detect_aberrant_edges(arr)
    elif CROP_MODE == "fraction":
        top = int(round(CROP_TOP * n_rows))
        bottom = int(round(CROP_BOTTOM * n_rows))
        left = int(round(CROP_LEFT * n_cols))
        right = int(round(CROP_RIGHT * n_cols))
    else:  # "pixels"
        top, bottom = int(CROP_TOP), int(CROP_BOTTOM)
        left, right = int(CROP_LEFT), int(CROP_RIGHT)

    r0, r1 = top, n_rows - bottom
    c0, c1 = left, n_cols - right

    if r1 <= r0 or c1 <= c0:
        print("  [!] Crop trop agressif, ignoré.")
        return arr

    cropped = arr[r0:r1, c0:c1]
    print(f"  [i] Crop ({CROP_MODE}) : {arr.shape} -> {cropped.shape} "
          f"(t={top}, b={bottom}, l={left}, r={right})")
    return cropped


# =============================================================================
#                       DÉROULEMENT CYLINDRIQUE
# =============================================================================

def estimate_cylinder_params(arr: np.ndarray):
    mask = np.isfinite(arr) & (arr != 0)
    if mask.sum() < 100:
        return None
    ys, xs = np.nonzero(mask)
    cx, cy = float(xs.mean()), float(ys.mean())
    r = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
    r_inner = float(np.percentile(r, 5))
    r_outer = float(np.percentile(r, 95))
    return cx, cy, r_inner, r_outer


def unwrap_cylindrical(arr, cx, cy, r_inner, r_outer, n_angles, n_radii):
    angles = np.linspace(0, 2 * np.pi, n_angles, endpoint=False)
    radii = np.linspace(r_inner, r_outer, n_radii)

    A, R = np.meshgrid(angles, radii, indexing="ij")
    X = cx + R * np.cos(A)
    Y = cy + R * np.sin(A)

    coords = np.array([Y.ravel(), X.ravel()])
    sampled = map_coordinates(np.nan_to_num(arr, nan=0.0),
                              coords, order=3, mode="nearest")
    sampled = sampled.reshape(n_angles, n_radii)

    extent = (0.0, 360.0, r_outer, r_inner)
    return sampled, extent


def maybe_unwrap(arr: np.ndarray, path: str):
    if not UNWRAP_ENABLED:
        return arr, None

    global UNWRAP_CENTER_X, UNWRAP_CENTER_Y, UNWRAP_R_INNER, UNWRAP_R_OUTER

    n_rows, n_cols = arr.shape
    cx = UNWRAP_CENTER_X if UNWRAP_CENTER_X is not None else n_cols / 2.0
    cy = UNWRAP_CENTER_Y if UNWRAP_CENTER_Y is not None else n_rows / 2.0

    if UNWRAP_R_INNER is None or UNWRAP_R_OUTER is None:
        params = estimate_cylinder_params(arr)
        if params is None:
            print(f"  [!] UNWRAP activé mais impossible d'estimer le cylindre "
                  f"pour {os.path.basename(path)} -> déroulement ignoré.")
            return arr, None
        cx_auto, cy_auto, r_in_auto, r_out_auto = params
        if UNWRAP_CENTER_X is None:
            cx = cx_auto
        if UNWRAP_CENTER_Y is None:
            cy = cy_auto
        if UNWRAP_R_INNER is None:
            UNWRAP_R_INNER = r_in_auto
        if UNWRAP_R_OUTER is None:
            UNWRAP_R_OUTER = r_out_auto
        print(f"  [i] Paramètres cylindre estimés : centre=({cx:.0f},{cy:.0f}), "
              f"R∈[{UNWRAP_R_INNER:.0f},{UNWRAP_R_OUTER:.0f}] px")

    arr_u, extent_px = unwrap_cylindrical(
        arr, cx, cy, UNWRAP_R_INNER, UNWRAP_R_OUTER,
        UNWRAP_N_ANGLES, UNWRAP_N_RADII,
    )
    return arr_u, extent_px


# =============================================================================
#                       TRAITEMENTS GÉNÉRIQUES
# =============================================================================

def smooth_upsample(arr: np.ndarray) -> np.ndarray:
    if not APPLY_SMOOTHING:
        return arr

    if np.isnan(arr).any():
        mean_val = np.nanmean(arr)
        arr = np.nan_to_num(arr, nan=mean_val)

    n_rows, n_cols = arr.shape
    factor = SMOOTH_FACTOR
    total_pixels = (n_rows * factor) * (n_cols * factor)
    if total_pixels > MAX_SMOOTHED_PIXELS:
        max_factor_sq = MAX_SMOOTHED_PIXELS / (n_rows * n_cols)
        factor = max(1.0, max_factor_sq ** 0.5)
        print(f"  [i] Facteur de lissage réduit à {factor:.2f}.")

    if factor <= 1:
        return arr

    return scipy_zoom(arr, factor, order=SMOOTH_ORDER)


def get_pixel_size_from_metadata(path: str):
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
            unit_code = unit_tag.value if unit_tag is not None else 2
            if unit_code == 2:
                mm_per_unit = 25.4
            elif unit_code == 3:
                mm_per_unit = 10.0
            else:
                return None
            return mm_per_unit / pixels_per_unit
    except Exception:
        return None


def resolve_pixel_size_mm(path: str, arr: np.ndarray):
    if PIXEL_SIZE_MM is not None:
        return PIXEL_SIZE_MM
    auto_value = get_pixel_size_from_metadata(path)
    if auto_value is not None:
        return auto_value
    return None


def resolve_extent(path: str, arr: np.ndarray, extent_override=None):
    n_rows, n_cols = arr.shape

    if extent_override is not None:
        return extent_override, False

    pixel_size_mm = resolve_pixel_size_mm(path, arr)
    if pixel_size_mm is not None:
        return (0, n_cols * pixel_size_mm, n_rows * pixel_size_mm, 0), True

    if SAMPLE_WIDTH_MM is not None and SAMPLE_HEIGHT_MM is not None:
        return (0, SAMPLE_WIDTH_MM, SAMPLE_HEIGHT_MM, 0), True

    print(f"  [!] Taille de pixel introuvable pour "
          f"{os.path.basename(path)} -> axes en pixels.")
    return (0, n_cols, n_rows, 0), False


def compute_figsize(extent):
    x_span = abs(extent[1] - extent[0])
    y_span = abs(extent[2] - extent[3])
    if x_span == 0 or y_span == 0:
        return (TARGET_LONG_SIDE_INCHES, TARGET_LONG_SIDE_INCHES * 3 / 4)

    ratio = x_span / y_span

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
    largest_inches = max(figsize)
    dpi = DPI
    if largest_inches * dpi > MAX_PIXELS_DIM:
        dpi = MAX_PIXELS_DIM / largest_inches
    return dpi


def get_vrange(arr: np.ndarray):
    """
    Calcule (vmin, vmax) en utilisant des percentiles robustes.
    Affiche aussi quelques stats (min, médiane, max, percentiles) pour
    diagnostiquer le calage de la colorbar.
    """
    finite = arr[np.isfinite(arr)]
    if finite.size == 0:
        return 0.0, 1.0

    vmin = VMIN if VMIN is not None else float(np.percentile(finite, VRANGE_PERCENTILE_LOW))
    vmax = VMAX if VMAX is not None else float(np.percentile(finite, VRANGE_PERCENTILE_HIGH))

    # --- DEBUG : stats pour comprendre le calage ---
    print(f"  [debug] min={finite.min():.2f}  "
          f"p{VRANGE_PERCENTILE_LOW}={np.percentile(finite, VRANGE_PERCENTILE_LOW):.2f}  "
          f"med={np.median(finite):.2f}  "
          f"p{VRANGE_PERCENTILE_HIGH}={np.percentile(finite, VRANGE_PERCENTILE_HIGH):.2f}  "
          f"max={finite.max():.2f}  "
          f"-> vmin={vmin:.2f}  vmax={vmax:.2f}")

    if vmin >= vmax:
        vmax = vmin + 1.0
    return vmin, vmax


def plot_tiff_to_png(tiff_path: str, output_folder: str):
    filename = os.path.basename(tiff_path)
    base_name = os.path.splitext(filename)[0]
    file_type = detect_file_type(filename)

    # --- Chargement ---
    arr = load_tiff(tiff_path)

    # --- Crop des bords aberrants ---
    arr = crop_borders(arr)

    # --- Déroulement cylindrique éventuel ---
    arr, extent_override = maybe_unwrap(arr, tiff_path)

    # --- Extent, plage de couleurs, lissage ---
    extent, is_mm = resolve_extent(tiff_path, arr, extent_override=extent_override)
    vmin, vmax = get_vrange(arr)
    arr_plot = smooth_upsample(arr)
    figsize = compute_figsize(extent)
    effective_dpi = get_effective_dpi(figsize)

    fig, ax = plt.subplots(figsize=figsize, dpi=effective_dpi)

    if file_type == "roughness":
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
        title = f"{base_name}"

    # --- axes ---
    if extent_override is not None:
        ax.set_xlabel("Angle (°)", fontsize=AXIS_LABEL_FONTSIZE)
        ax.set_ylabel("Rayon (px)", fontsize=AXIS_LABEL_FONTSIZE)
    elif is_mm:
        ax.set_xlabel("Y (mm)", fontsize=AXIS_LABEL_FONTSIZE)
        ax.set_ylabel("Z (mm)", fontsize=AXIS_LABEL_FONTSIZE)
    else:
        ax.set_xlabel("Y (px)", fontsize=AXIS_LABEL_FONTSIZE)
        ax.set_ylabel("Z (px)", fontsize=AXIS_LABEL_FONTSIZE)

    ax.set_title(title, fontsize=TITLE_FONTSIZE, fontweight="bold")
    ax.tick_params(axis="both", labelsize=TICK_FONTSIZE)

    if XLIM is not None:
        ax.set_xlim(XLIM)
    if YLIM is not None:
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
        print(f"--- Traitement de {os.path.basename(path)} ---")
        try:
            out_path = plot_tiff_to_png(path, output_folder)
            file_type = detect_file_type(os.path.basename(path))
            print(f"[OK] {os.path.basename(path)}  (type={file_type})  -> {out_path}\n")
            n_ok += 1
        except Exception as e:
            print(f"[ERREUR] {os.path.basename(path)} : {e}")
            traceback.print_exc()
            n_fail += 1
            print()

    print(f"Terminé : {n_ok} succès, {n_fail} échec(s).")
    print(f"PNG exportés dans : {output_folder}")


if __name__ == "__main__":
    main()
