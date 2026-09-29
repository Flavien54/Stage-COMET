#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================================
 tiff_to_png.py
-----------------------------------------------------------------------------
 Lit un fichier .tif / .tiff (mode "single") ou tous les fichiers d'un
 dossier (mode "batch"), les visualise (heatmap) selon leur type détecté à
 partir du nom de fichier, puis exporte en PNG.

 Adapté aux ÉCHANTILLONS CYLINDRIQUES découpés en tranches de 90° :
   - crop automatique des bords (divergence capteur / bandes saturées)
   - suppression des artefacts linéaires verticaux + interpolation
   - lissage par filtre bilatéral (préserve les pics isolés)

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
from scipy.ndimage import (uniform_filter1d, median_filter, binary_closing,
                           binary_opening, binary_dilation, label, find_objects)

try:
    from skimage.restoration import denoise_bilateral

    _HAS_SKIMAGE = True
except ImportError:
    _HAS_SKIMAGE = False
    print("[!] scikit-image non installé. Le filtre bilatéral ne sera pas disponible.")
    print("    Installez-le avec : pip install scikit-image")

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
INPUT_FILE = None          # Chemin d'un fichier unique (mode "single")
OUTPUT_FOLDER = None
RECURSIVE = False

# "single" (une seule image), "batch" (tout un dossier)
# ou None => une fenêtre demande le mode à chaque lancement.
PROCESS_MODE = None

UNIT_FACTOR = 1e6
UNIT_LABEL = "µm"

PIXEL_SIZE_MM = None
SAMPLE_WIDTH_MM = 10.31
SAMPLE_HEIGHT_MM = 6.94

# --- Lissage bilatéral ----------------------------------------------------
# Le filtre bilatéral lisse le bruit tout en préservant les contours et les pics.
#
# sigma_color   : contrôle la préservation des intensités.
#                 Petit  -> préserve fortement les pics (mais lisse moins)
#                 Grand  -> lisse plus mais peut atténuer les pics
#                 Valeur typique : 0.05 à 0.2 (en échelle normalisée 0-1)
#
# sigma_spatial : contrôle la taille de la zone de lissage spatial.
#                 Petit  -> lissage local (garde les détails)
#                 Grand  -> lissage large (image plus douce)
#                 Valeur typique : 2 à 10 (en pixels)
#
# win_size      : taille du voisinage (doit être impair).
#                 Doit être >= 2 * sigma_spatial + 1
#                 Valeur typique : 5, 7, 9, 11, 13
#
# SMOOTH_FACTOR : facteur d'upsampling final (pour lisser les transitions)

APPLY_SMOOTHING = True
BILATERAL_SIGMA_COLOR = 0.10
BILATERAL_SIGMA_SPATIAL = 5.0
BILATERAL_WIN_SIZE = 11
SMOOTH_FACTOR = 3
MAX_SMOOTHED_PIXELS = 40_000_000

# --- Crop des bords --------------------------------------------------------
# Trois modes :
#   "auto"     : détecte les lignes/colonnes aberrantes (bandes saturées en
#                haut/bas, colonnes décalées sur les côtés) en comparant leur
#                médiane à la médiane globale.
#   "fraction" : crop fixe en fraction de la dimension (0-0.5).
#   "pixels"   : crop fixe en nombre de pixels.
CROP_ENABLED = True
CROP_MODE = "auto"  # "auto", "fraction" ou "pixels"

# --- Paramètres du crop AUTO ----------------------------------------------
AUTO_CROP_SIGMA = 2.0
AUTO_CROP_MARGIN = 15
AUTO_CROP_MAX_FRACTION = 0.35

# --- Paramètres du crop FRACTION / PIXELS ----------------------------------
CROP_TOP = 0.15
CROP_BOTTOM = 0.15
CROP_LEFT = 0.03
CROP_RIGHT = 0.03

# --- Suppression des artefacts linéaires verticaux -------------------------
ARTIFACT_REMOVAL = True
# Ne traiter que les fichiers dont le nom contient l'une de ces chaînes
# (None = tous). Les U-MM ont de vrais pores allongés : on les épargne.
ARTIFACT_FILE_FILTER = ["-AB-"]

ART_BG_WINDOW_MM = 0.20      # fenêtre du médian horizontal (> 2x largeur max d'une trace)
ART_K_SIGMA = 3.5            # seuil de détection (sigma robuste). Baisser => plus sensible
ART_CLOSE_MM = 0.30          # comble les trous verticaux dans les traits pointillés
ART_MIN_HEIGHT_MM = 0.30     # hauteur minimale d'une trace
ART_MAX_WIDTH_MM = 0.08      # largeur maximale d'une trace
ART_MIN_ASPECT = 6.0         # hauteur / largeur minimale
ART_MIN_FILL = 0.20          # taux de remplissage minimal (pixels "forts" / objet)
ART_DILATE_MM = 0.02         # élargit le masque de chaque côté (mm)
ART_V_MARGIN_MM = 0.12       # prolonge le masque en haut/bas (mm) : bouts pâles des traces
ART_SAVE_MASK = False        # True => exporte aussi le masque en PNG (pour régler)

# --- Déroulement cylindrique -----------------------------------------------
UNWRAP_ENABLED = False
UNWRAP_CENTER_X = None
UNWRAP_CENTER_Y = None
UNWRAP_R_INNER = None
UNWRAP_R_OUTER = None
UNWRAP_N_ANGLES = 1440
UNWRAP_N_RADII = 256

# --- Barre de couleur ------------------------------------------------------
VRANGE_PERCENTILE_LOW = 1.0
VRANGE_PERCENTILE_HIGH = 99.5

# Forcer une plage fixe (appliquée à TOUS les fichiers si non None)
VMIN = None
VMAX = None

XLIM = None
YLIM = (0.5, 2.7)

# True => le tableau est découpé à la fenêtre XLIM/YLIM (les bords hors fenêtre
# ne sont pas affichés). Si les données sont plus courtes que la fenêtre, elles
# sont étirées pour la remplir : plus aucune zone blanche.
FILL_AXES_LIMITS = True

CMAP_ROUGHNESS = "viridis"
CMAP_ALIGNED = "viridis"

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


def select_file(title: str) -> str:
    """Boîte de dialogue pour choisir un seul fichier TIFF."""
    root = Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    path = filedialog.askopenfilename(
        title=title,
        filetypes=[("Fichiers TIFF", "*.tif *.tiff *.TIF *.TIFF"),
                   ("Tous les fichiers", "*.*")],
    )
    root.destroy()
    return path


def ask_mode() -> str:
    """Petite fenêtre : une seule image ou batch. Retourne 'single', 'batch' ou None."""
    from tkinter import Label, Button, Frame

    root = Tk()
    root.title("Mode de traitement")
    root.attributes("-topmost", True)
    root.resizable(False, False)
    choice = {"value": None}

    def pick(value):
        choice["value"] = value
        root.destroy()

    Label(root, text="Que souhaitez-vous traiter ?",
          font=("Arial", 12, "bold"), padx=20, pady=15).pack()

    frame = Frame(root, padx=20, pady=10)
    frame.pack()
    Button(frame, text="Une seule image", width=20, height=2,
           command=lambda: pick("single")).grid(row=0, column=0, padx=8)
    Button(frame, text="Batch (tout un dossier)", width=20, height=2,
           command=lambda: pick("batch")).grid(row=0, column=1, padx=8)

    root.protocol("WM_DELETE_WINDOW", lambda: pick(None))
    root.mainloop()
    return choice["value"]


def resolve_inputs():
    """
    Retourne (mode, tiff_files, output_folder).
      - mode 'single' : tiff_files contient un seul fichier
      - mode 'batch'  : tiff_files contient tous les TIFF du dossier
    """
    mode = PROCESS_MODE
    if mode is None and INPUT_FILE:
        mode = "single"            # un fichier est déjà fixé dans la config
    if mode is None:
        mode = ask_mode()
    if mode not in ("single", "batch"):
        print("Aucun mode sélectionné. Arrêt.")
        raise SystemExit

    if mode == "single":
        path = INPUT_FILE or select_file("Sélectionner le fichier TIFF à traiter")
        if not path:
            print("Aucun fichier sélectionné. Arrêt.")
            raise SystemExit
        print(f"Mode : image unique -> {path}")
        tiff_files = [path]
    else:
        input_folder = INPUT_FOLDER or select_folder(
            "Sélectionner le dossier contenant les fichiers TIFF")
        if not input_folder:
            print("Aucun dossier d'entrée sélectionné. Arrêt.")
            raise SystemExit
        print(f"Mode : batch -> lecture des .tif/.tiff dans : {input_folder}")
        tiff_files = find_tiff_files(input_folder, RECURSIVE)

    output_folder = OUTPUT_FOLDER or select_folder(
        "Sélectionner le dossier de destination des PNG")
    if not output_folder:
        print("Aucun dossier de sortie sélectionné. Arrêt.")
        raise SystemExit

    return mode, tiff_files, output_folder


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

    top += AUTO_CROP_MARGIN
    bottom += AUTO_CROP_MARGIN
    left += AUTO_CROP_MARGIN
    right += AUTO_CROP_MARGIN

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
#                  SUPPRESSION DES ARTEFACTS VERTICAUX
# =============================================================================

def _odd(n: int) -> int:
    n = int(max(3, round(n)))
    return n if n % 2 == 1 else n + 1


def detect_vertical_artifacts(arr: np.ndarray) -> np.ndarray:
    """
    Retourne un masque booléen des traces fines verticales négatives.
    Deux détecteurs combinés :
      A) par forme : objets fins et allongés (après retrait des parties larges)
      B) par profil de colonne : colonnes avec un excès de pixels très négatifs
         (rattrape les traces collées à un pore/blob).
    """
    n_rows, n_cols = arr.shape
    px = SAMPLE_WIDTH_MM / n_cols          # taille de pixel approx. en Y
    pz = SAMPLE_HEIGHT_MM / n_rows         # taille de pixel approx. en Z

    filled = np.nan_to_num(arr, nan=np.nanmedian(arr))

    # fond local (médian horizontal) et résidu
    win = _odd(ART_BG_WINDOW_MM / px)
    bg = median_filter(filled, size=(1, win), mode="reflect")
    res = filled - bg
    sigma = _robust_sigma(res.ravel())
    if sigma <= 0:
        return np.zeros_like(arr, dtype=bool)
    strong = res < -ART_K_SIGMA * sigma

    max_w = max(2, int(round(ART_MAX_WIDTH_MM / px)))
    close_len = _odd(ART_CLOSE_MM / pz)
    min_h = ART_MIN_HEIGHT_MM / pz

    mask = np.zeros(arr.shape, dtype=bool)

    # --- A) détecteur par forme -------------------------------------------
    sd = binary_dilation(strong, structure=np.ones((1, 3), bool))
    cand = binary_closing(sd, structure=np.ones((close_len, 1), bool))
    wide = binary_opening(cand, structure=np.ones((1, max_w + 1), bool))
    wide = binary_dilation(wide, structure=np.ones((1, 3), bool))
    cand &= ~wide
    lab, n = label(cand)
    for i, sl in enumerate(find_objects(lab), start=1):
        h = sl[0].stop - sl[0].start
        w = sl[1].stop - sl[1].start
        if h < min_h or h / max(w, 1) < ART_MIN_ASPECT:
            continue
        obj = lab[sl] == i
        fill = (strong[sl] & obj).sum() / max(obj.sum(), 1)
        if fill < ART_MIN_FILL:
            continue
        mask[sl] |= obj

    # --- B) détecteur par profil de colonne -------------------------------
    cnt = uniform_filter1d(strong.sum(axis=0).astype(float), 3, mode="nearest") * 3
    base = median_filter(cnt, size=_odd(0.3 / px), mode="reflect")
    excess = cnt - base
    clab, cn = label(excess >= 0.5 * min_h)
    for csl in find_objects(clab):
        ex = excess[csl[0]]
        keep = np.nonzero(ex >= 0.5 * ex.max())[0]
        c0 = max(csl[0].start + keep.min() - 1, 0)
        c1 = min(csl[0].start + keep.max() + 2, n_cols)
        rows = strong[:, c0:c1].any(axis=1)
        rows = binary_closing(rows, structure=np.ones(close_len, bool))
        rl, rn = label(rows)
        for rsl in find_objects(rl):
            if (rsl[0].stop - rsl[0].start) >= min_h:
                mask[rsl[0], c0:c1] = True

    # --- élargit pour couvrir les bords et les bouts pâles des traces -----
    dx = max(1, int(round(ART_DILATE_MM / px)))
    dz = max(0, int(round(ART_V_MARGIN_MM / pz)))
    mask = binary_dilation(mask, structure=np.ones((2 * dz + 1, 2 * dx + 1), bool))
    return mask


def inpaint_rows(arr: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Interpolation linéaire horizontale des pixels masqués, ligne par ligne."""
    out = arr.copy()
    xs = np.arange(arr.shape[1])
    for r in np.nonzero(mask.any(axis=1))[0]:
        bad = mask[r] | ~np.isfinite(arr[r])
        good = ~bad
        if good.sum() < 2:
            continue
        out[r, bad] = np.interp(xs[bad], xs[good], arr[r, good])
    return out


def remove_artifacts(arr: np.ndarray, base_name: str = "",
                     save_mask_path: str = None) -> np.ndarray:
    if not ARTIFACT_REMOVAL:
        return arr
    if ARTIFACT_FILE_FILTER and not any(k in base_name for k in ARTIFACT_FILE_FILTER):
        return arr
    mask = detect_vertical_artifacts(arr)
    print(f"  [i] Artefacts : {mask.sum()} px masqués "
          f"({100 * mask.mean():.2f} %)")
    if save_mask_path and ART_SAVE_MASK:
        plt.imsave(save_mask_path, mask, cmap="gray")
    return inpaint_rows(arr, mask)


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
    """
    Applique un filtre bilatéral pour lisser l'image tout en préservant
    les contours et les pics isolés.

    Le filtre bilatéral combine :
      - Un filtre spatial (sigma_spatial) : moyenne les pixels proches
      - Un filtre d'intensité (sigma_color) : ne moyenne que les pixels
        ayant une valeur similaire

    Résultat : les zones uniformes sont lissées, mais les transitions
    nettes (pics, bords) sont conservées.
    """
    if not APPLY_SMOOTHING:
        return arr

    if not _HAS_SKIMAGE:
        print("  [!] scikit-image non disponible -> lissage ignoré.")
        return arr

    # Gestion des NaN
    if np.isnan(arr).any():
        mean_val = np.nanmean(arr)
        arr = np.nan_to_num(arr, nan=mean_val)

    # Normalisation pour le filtre bilatéral (qui attend des valeurs [0,1])
    vmin, vmax = arr.min(), arr.max()
    if vmax - vmin < 1e-12:
        return arr
    arr_norm = (arr - vmin) / (vmax - vmin)

    # --- Application du filtre bilatéral ---
    arr_filtered = denoise_bilateral(
        arr_norm,
        sigma_color=BILATERAL_SIGMA_COLOR,
        sigma_spatial=BILATERAL_SIGMA_SPATIAL,
        win_size=BILATERAL_WIN_SIZE,
        mode='reflect',
    )

    # Dénormalisation
    arr_filtered = arr_filtered * (vmax - vmin) + vmin

    # Clip pour éviter les valeurs hors plage (affichées comme transparentes
    # par matplotlib).
    arr_filtered = np.clip(arr_filtered, vmin, vmax)

    # --- Upsampling final pour lisser les transitions ---
    n_rows, n_cols = arr_filtered.shape
    factor = SMOOTH_FACTOR
    total_pixels = (n_rows * factor) * (n_cols * factor)
    if total_pixels > MAX_SMOOTHED_PIXELS:
        max_factor_sq = MAX_SMOOTHED_PIXELS / (n_rows * n_cols)
        factor = max(1.0, max_factor_sq ** 0.5)
        print(f"  [i] Facteur d'upsampling réduit à {factor:.2f}.")

    if factor > 1:
        arr_filtered = scipy_zoom(arr_filtered, factor, order=1)

    return arr_filtered


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
    Calcule (vmin, vmax) de manière automatique et robuste.

    Utilise l'écart interquartile (IQR) pour détecter les valeurs aberrantes
    et les ignorer, sans avoir à ajuster manuellement les percentiles.
    """
    finite = arr[np.isfinite(arr)]
    if finite.size == 0:
        return 0.0, 1.0

    # Si VMIN/VMAX sont forcés dans la config, on les utilise
    if VMIN is not None and VMAX is not None:
        return float(VMIN), float(VMAX)

    # --- Calcul automatique basé sur l'IQR ---
    q1 = np.percentile(finite, 25)
    q3 = np.percentile(finite, 75)
    iqr = q3 - q1

    # Limites statistiques (méthode de Tukey), facteur large (3.0) pour ne
    # pas trop couper les pics intéressants.
    FACTOR = 3.0

    vmin_auto = q1 - FACTOR * iqr
    vmax_auto = q3 + FACTOR * iqr

    # On s'assure de ne pas dépasser les bornes réelles des données
    vmin_auto = max(vmin_auto, finite.min())
    vmax_auto = min(vmax_auto, finite.max())

    # Si VMIN ou VMAX est forcé individuellement, on respecte le choix
    vmin = VMIN if VMIN is not None else vmin_auto
    vmax = VMAX if VMAX is not None else vmax_auto

    # --- DEBUG : stats pour comprendre le calage ---
    print(f"  [debug] min={finite.min():.2f}  "
          f"Q1={q1:.2f}  med={np.median(finite):.2f}  Q3={q3:.2f}  "
          f"max={finite.max():.2f}  "
          f"-> vmin={vmin:.2f}  vmax={vmax:.2f}")

    if vmin >= vmax:
        vmax = vmin + 1.0
    return vmin, vmax


def crop_to_window(arr: np.ndarray, extent):
    """
    Découpe le tableau à la fenêtre XLIM/YLIM (en mm), au lieu d'étirer tout
    le tableau dedans : les bords (bandes bleues, bouts de traces) situés hors
    fenêtre ne sont ni affichés ni pris en compte dans l'échelle de couleurs.

    Si le tableau est plus court que la fenêtre (ex. échantillon plus petit),
    la partie disponible est étirée pour remplir toute la fenêtre -> pas de blanc.
    """
    n_rows, n_cols = arr.shape
    x_left, x_right, y_bot, y_top = extent
    dx = (x_right - x_left) / n_cols
    dz = (y_bot - y_top) / n_rows

    r0, r1, c0, c1 = 0, n_rows, 0, n_cols
    new_x0, new_x1, new_y0, new_y1 = x_left, x_right, y_top, y_bot

    if YLIM is not None and dz > 0:
        z0 = max(min(YLIM), y_top)
        z1 = min(max(YLIM), y_bot)
        if z1 > z0:
            r0 = int(round((z0 - y_top) / dz))
            r1 = int(round((z1 - y_top) / dz))
            new_y0, new_y1 = min(YLIM), max(YLIM)   # remplit toute la fenêtre
    if XLIM is not None and dx > 0:
        x0 = max(min(XLIM), x_left)
        x1 = min(max(XLIM), x_right)
        if x1 > x0:
            c0 = int(round((x0 - x_left) / dx))
            c1 = int(round((x1 - x_left) / dx))
            new_x0, new_x1 = min(XLIM), max(XLIM)

    if r1 - r0 < 2 or c1 - c0 < 2:
        return arr, extent
    print(f"  [i] Fenêtre : lignes {r0}:{r1} / {n_rows}, colonnes {c0}:{c1} / {n_cols}")
    return arr[r0:r1, c0:c1], (new_x0, new_x1, new_y1, new_y0)


def plot_tiff_to_png(tiff_path: str, output_folder: str):
    filename = os.path.basename(tiff_path)
    base_name = os.path.splitext(filename)[0]
    file_type = detect_file_type(filename)

    os.makedirs(output_folder, exist_ok=True)

    # --- Chargement ---
    arr = load_tiff(tiff_path)

    # --- Crop des bords aberrants ---
    arr = crop_borders(arr)

    # --- Suppression des artefacts verticaux (AVANT get_vrange) ---
    arr = remove_artifacts(
        arr, base_name, os.path.join(output_folder, base_name + "_mask.png"))

    # --- Déroulement cylindrique éventuel ---
    arr, extent_override = maybe_unwrap(arr, tiff_path)

    # --- Extent, plage de couleurs, lissage ---
    extent, is_mm = resolve_extent(tiff_path, arr, extent_override=extent_override)

    if FILL_AXES_LIMITS and extent_override is None:
        arr, extent = crop_to_window(arr, extent)

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

    # Les limites d'axes sont bornées à l'étendue réelle des données :
    # si l'échantillon est plus court que YLIM (après crop auto), on n'affiche
    # pas de zone blanche vide.
    if extent_override is None:
        x_lo, x_hi = sorted((extent[0], extent[1]))
        y_lo, y_hi = sorted((extent[3], extent[2]))
        if XLIM is not None:
            ax.set_xlim(max(min(XLIM), x_lo), min(max(XLIM), x_hi))
        if YLIM is not None:
            ax.set_ylim(min(max(YLIM), y_hi), max(min(YLIM), y_lo))

    # --- colorbar ---
    if COLORBAR_ORIENTATION == "horizontal":
        cbar = fig.colorbar(im, ax=ax, orientation="horizontal", location="bottom",
                            fraction=0.08, pad=0.12, shrink=0.9)
    else:
        cbar = fig.colorbar(im, ax=ax, orientation="vertical", fraction=0.046, pad=0.04)
    cbar.set_label(cbar_label, fontsize=CBAR_LABEL_FONTSIZE)
    cbar.ax.tick_params(labelsize=CBAR_TICK_FONTSIZE)

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
    mode, tiff_files, output_folder = resolve_inputs()

    if not tiff_files:
        print("Aucun fichier .tif/.tiff trouvé.")
        return

    print(f"{len(tiff_files)} fichier(s) à traiter.\n")

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
