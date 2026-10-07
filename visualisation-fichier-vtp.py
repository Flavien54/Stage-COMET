"""
Reconstitution de la Deviation Map (Dragonfly) à partir d'un fichier VTP / VTK.

Au lancement, le script demande :
  1. le mode : 3D (fenêtre PyVista) ou 2D (heatmap matplotlib)
  2. en 2D : le cadran du cylindre (1, 2, 3, 4) à "dérouler" en heatmap
  3. avec ou sans crop (pour zoomer sur une zone plus petite)

    uv pip install numpy scipy pyvista matplotlib
    (+ torch et pytorch3d pour la dernière partie, optionnelle)
"""

from pathlib import Path

import numpy as np
import pyvista as pv
import matplotlib
import matplotlib.pyplot as plt
from matplotlib.tri import Triangulation
from scipy.spatial import cKDTree

# ----------------------------------------------------------------------
# Paramètres
# ----------------------------------------------------------------------
MESH_PATH = r"D:\lineics-samples-2\visu\sample3D.vtp"   # .vtp, .vtk, .ply ...
ARRAY_NAME = None                # None = détection auto ; sinon nom exact du tableau
CLIM = (0.0, 0.93)               # plage de la colorbar Dragonfly (mm)
CMAP = "viridis"
OUT_DIR = Path(__file__).parent
DRAGONFLY_BLUE = "#3fa9f5"
COORD_SCALE = 1000.0             # coordonnées du fichier en m -> converties en mm

# Mettre à None pour être interrogé au lancement, ou fixer pour sauter les questions
MODE = None                      # "3D" | "2D" | None
CROP = None                      # True | False | None
QUADRANT = None                  # 2D uniquement : 1 | 2 | 3 | 4 | None
CYL_AXIS = None                  # axe du cylindre "X" | "Y" | "Z" ; None = axe le plus long
Y_UNIT = "mm"                    # axe vertical de la heatmap 2D : "mm" (arc) ou "deg" (angle)

DPI = 300                        # résolution de l'image enregistrée

# Tableaux à ignorer lors de la détection automatique
IGNORED = ("normal", "tcoord", "texturecoord")


# ----------------------------------------------------------------------
# Utilitaires d'interaction
# ----------------------------------------------------------------------
def ask_choice(question, choices, default):
    """choices : dict {touche: valeur}. Entrée = défaut."""
    keys = "/".join(k.upper() if choices[k] == default else k for k in choices)
    while True:
        r = input(f"{question} [{keys}] : ").strip().lower()
        if r == "":
            return default
        if r in choices:
            return choices[r]
        print("  Réponse non reconnue.")


def ask_float(label, default):
    while True:
        r = input(f"  {label} [{default:.4f}] : ").strip().replace(",", ".")
        if r == "":
            return float(default)
        try:
            return float(r)
        except ValueError:
            print("  Valeur invalide.")


def ask_range(label_lo, label_hi, lo, hi):
    a = ask_float(label_lo, lo)
    b = ask_float(label_hi, hi)
    return (b, a) if a > b else (a, b)


def crop_mesh_box(mesh, bounds):
    """Crop 3D par boîte englobante (utilisé en mode 3D)."""
    cropped = mesh.clip_box(bounds=bounds, invert=False)   # interpole les point_data
    cropped = cropped.extract_surface().triangulate()
    if cropped.n_points == 0:
        raise SystemExit("Le crop est vide : aucune surface dans cette zone.")
    return cropped


# ----------------------------------------------------------------------
# Géométrie du cylindre (pour la projection 2D)
# ----------------------------------------------------------------------
def cylinder_frame(m, axis_name=None):
    """
    Détecte l'axe du cylindre, son centre (uc, vc) dans le plan perpendiculaire
    et son rayon R, en ne gardant que la surface latérale (hors bouchons).
    """
    P = np.asarray(m.points)
    sizes = P.max(axis=0) - P.min(axis=0)
    ax = "XYZ".index(axis_name) if axis_name else int(np.argmax(sizes))
    u_i, v_i = [(1, 2), (2, 0), (0, 1)][ax]          # ordre cyclique des 2 autres axes

    tri = m.faces.reshape(-1, 4)[:, 1:]
    n = np.cross(P[tri[:, 1]] - P[tri[:, 0]], P[tri[:, 2]] - P[tri[:, 0]])
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-30
    lateral = np.abs(n[:, ax]) < 0.5                  # normale ⟂ axe = surface latérale
    used = np.unique(tri[lateral])
    if used.size == 0:
        raise SystemExit("Surface latérale introuvable : vérifie CYL_AXIS.")
    used = used[:: max(1, used.size // 300000)]       # sous-échantillon pour l'ajustement

    u, v = P[used, u_i], P[used, v_i]
    A = np.c_[2 * u, 2 * v, np.ones_like(u)]
    sol = np.linalg.lstsq(A, u ** 2 + v ** 2, rcond=None)[0]   # ajustement de cercle (Kåsa)
    uc, vc = sol[0], sol[1]
    R = float(np.sqrt(sol[2] + uc ** 2 + vc ** 2))
    return dict(ax=ax, u_i=u_i, v_i=v_i, uc=uc, vc=vc, R=R, tri=tri[lateral])


QUADRANT_RANGES = {1: (0.0, 90.0), 2: (90.0, 180.0), 3: (180.0, 270.0), 4: (270.0, 360.0)}


def render_unrolled_heatmap(m, values, frame, quadrant, crop_ranges, out_path):
    """Déroule un cadran du cylindre et trace la heatmap brute (aucun filtre)."""
    P = np.asarray(m.points)
    ax_i, u_i, v_i = frame["ax"], frame["u_i"], frame["v_i"]
    R = frame["R"]
    values = np.asarray(values)

    x = P[:, ax_i]                                                      # position axiale (mm)
    theta = np.degrees(np.arctan2(P[:, v_i] - frame["vc"], P[:, u_i] - frame["uc"])) % 360.0
    s = R * np.radians(theta)                                           # abscisse curviligne (mm)
    y = s if Y_UNIT == "mm" else theta                                  # un seul axe vertical

    (xmin, xmax), (tmin, tmax) = crop_ranges
    ok = (x >= xmin) & (x <= xmax) & (theta >= tmin) & (theta <= tmax)
    tri = frame["tri"]
    tri = tri[ok[tri].all(axis=1)]            # triangles entièrement dans la zone
    if tri.shape[0] == 0:
        raise SystemExit("Aucun triangle dans cette zone (cadran/crop vide).")
    used = np.unique(tri)

    fig, axp = plt.subplots(figsize=(12.7, 6))
    tpc = axp.tripcolor(Triangulation(x, y, tri), values, shading="gouraud", cmap=CMAP,
                        vmin=CLIM[0], vmax=CLIM[1], rasterized=True)
    axp.set_xlim(x[used].min(), x[used].max())
    axp.set_ylim(y[used].min(), y[used].max())
    axp.set_xlabel(f"Position le long de l'axe {'XYZ'[ax_i]} (mm)")
    if Y_UNIT == "mm":
        axp.set_aspect("equal")                  # mm sur les deux axes -> échelle réelle
        axp.set_ylabel(f"Arc sur le cylindre, R = {R:.2f} mm (mm)")
    else:
        axp.set_aspect("auto")                   # mm en x, degrés en y
        axp.set_ylabel("Angle (°)")
    axp.set_title(f"Deviation Map to Pores Mesh (mm) - cadran {quadrant}")
    cb = fig.colorbar(tpc, ax=axp, orientation="horizontal", pad=0.12, fraction=0.05)
    cb.set_label("Surface Mesh - Deviation Map to Pores Mesh (mm)")
    fig.savefig(out_path, dpi=DPI, bbox_inches="tight")
    print(f"Image enregistrée : {out_path}")
    plt.show()


# ----------------------------------------------------------------------
# 1. Lecture du maillage + diagnostic
# ----------------------------------------------------------------------
mesh = pv.read(MESH_PATH)
if not isinstance(mesh, pv.PolyData):
    mesh = mesh.extract_surface()
if not mesh.is_all_triangles:
    mesh = mesh.triangulate()   # conserve les point_data et cell_data
print(mesh)


def print_dimensions(m, title, unit):
    xmin, xmax, ymin, ymax, zmin, zmax = m.bounds
    print(f"\n--- {title} ---")
    print(f"X : min = {xmin:.4f} | max = {xmax:.4f} | taille = {xmax - xmin:.4f} {unit}")
    print(f"Y : min = {ymin:.4f} | max = {ymax:.4f} | taille = {ymax - ymin:.4f} {unit}")
    print(f"Z : min = {zmin:.4f} | max = {zmax:.4f} | taille = {zmax - zmin:.4f} {unit}")


# Dimensions du fichier de base (unités d'origine : m)
print_dimensions(mesh, "Dimensions du fichier de base (m)", "m")

# Conversion des coordonnées m -> mm
mesh.points = np.asarray(mesh.points) * COORD_SCALE
print_dimensions(mesh, "Dimensions après conversion (mm)", "mm")

print("\n--- Tableaux présents dans le fichier ---")
for label, store in (("POINT", mesh.point_data), ("CELL", mesh.cell_data)):
    for n in store.keys():
        a = np.asarray(store[n])
        print(f"{label:5s} {n[:40]!r:45s} shape={a.shape} dtype={a.dtype} "
              f"min={a.min():.6f} max={a.max():.6f}")
print("-----------------------------------------\n")

# ----------------------------------------------------------------------
# 2. Choix du tableau (sommets OU faces), en ignorant les normales
# ----------------------------------------------------------------------
candidates = []   # liste de (association, nom)
for assoc, store in (("point", mesh.point_data), ("cell", mesh.cell_data)):
    for n in store.keys():
        if not any(k in n.lower() for k in IGNORED):
            candidates.append((assoc, n))
print("Candidats :", candidates)

if not candidates:
    raise SystemExit(
        "Aucun tableau de valeurs exploitable : le fichier ne contient que la géométrie "
        "(et éventuellement des normales).\n"
        "Ré-exporte depuis Dragonfly avec la déviation/les couleurs, "
        "ou calcule la distance avec le maillage des pores."
    )


def get_array(assoc, name):
    store = mesh.point_data if assoc == "point" else mesh.cell_data
    return np.asarray(store[name])


def is_color(arr):
    return arr.ndim == 2 and arr.shape[1] in (3, 4)


if ARRAY_NAME is not None:
    chosen = next((c for c in candidates if c[1] == ARRAY_NAME), None)
    if chosen is None:
        raise SystemExit(f"Tableau '{ARRAY_NAME}' introuvable parmi {candidates}")
else:
    keywords = ("dev", "dist", "color", "rgb", "scalar", "value")
    # 1) un nom qui évoque la déviation ou la couleur
    chosen = next((c for c in candidates if any(k in c[1].lower() for k in keywords)), None)
    # 2) sinon un tableau uint8 à 3/4 colonnes (= très probablement des couleurs)
    if chosen is None:
        chosen = next((c for c in candidates
                       if is_color(get_array(*c)) and get_array(*c).dtype == np.uint8), None)
    # 3) sinon un scalaire 1D
    if chosen is None:
        chosen = next((c for c in candidates if get_array(*c).ndim == 1), candidates[0])

assoc, chosen_name = chosen
print(f"Tableau utilisé : '{chosen_name[:40]}...' (association : {assoc})")

data = get_array(assoc, chosen_name)
print("Forme :", data.shape, "| dtype :", data.dtype)

# ----------------------------------------------------------------------
# 3. Conversion en déviation (mm)
# ----------------------------------------------------------------------
if is_color(data):
    # Couleurs RGB(A) -> on inverse la colormap viridis
    rgb = data[:, :3].astype(np.float64)
    if data.dtype != np.uint8 and rgb.max() <= 1.0:
        rgb = rgb * 255.0
    rgb = np.clip(rgb, 0, 255).astype(np.float32)

    lut_values = np.linspace(0.0, 1.0, 1024)
    lut_rgb = (matplotlib.colormaps[CMAP](lut_values)[:, :3] * 255).astype(np.float32)
    err, idx = cKDTree(lut_rgb).query(rgb, workers=-1)

    deviation_mm = (CLIM[0] + lut_values[idx] * (CLIM[1] - CLIM[0])).astype(np.float32)
    print(f"Erreur d'inversion RGB : médiane = {np.median(err):.1f}, "
          f"99% = {np.percentile(err, 99):.1f}")
    print("(médiane < ~5 : les couleurs viennent bien de viridis)")
elif data.ndim == 1 or (data.ndim == 2 and data.shape[1] == 1):
    # Scalaire direct. L'export Dragonfly stocke la distance en mètres -> mm
    unit_factor = 1000.0 if "Meters" in chosen_name else 1.0
    print(f"Facteur d'unité appliqué : x{unit_factor:g}")
    deviation_mm = (data.reshape(-1) * unit_factor).astype(np.float32)
else:
    raise SystemExit(f"Tableau '{chosen_name}' de forme {data.shape} non exploitable.")

# Si la valeur est par face, on la stocke côté faces puis on interpole aux sommets
if assoc == "cell":
    mesh.cell_data["deviation_mm"] = deviation_mm
    mesh = mesh.cell_data_to_point_data(pass_cell_data=True)
    deviation_mm = np.asarray(mesh.point_data["deviation_mm"], dtype=np.float32)
    print("Valeurs par face converties en valeurs par sommet.")
else:
    mesh.point_data["deviation_mm"] = deviation_mm

print(f"Déviation : min = {deviation_mm.min():.3f}, max = {deviation_mm.max():.3f}")
np.save(OUT_DIR / "deviation_mm.npy", deviation_mm)
d = deviation_mm
print("min / max :", d.min(), d.max())
print("% exactement au max :", np.mean(d >= d.max() - 1e-6) * 100)
print("% exactement à 0    :", np.mean(d == 0) * 100)
print(np.histogram(d, bins=20))

# ----------------------------------------------------------------------
# 4. Choix utilisateur : 3D / 2D (cadran), avec / sans crop
# ----------------------------------------------------------------------
print("\n=== Options de visualisation ===")
mode = MODE or ask_choice("Visualisation 3D ou 2D (heatmap) ?",
                          {"3": "3D", "2": "2D"}, default="3D")

frame = None
quadrant = None
if mode == "2D":
    frame = cylinder_frame(mesh, CYL_AXIS)
    an = "XYZ"[frame["ax"]]
    un, vn = "XYZ"[frame["u_i"]], "XYZ"[frame["v_i"]]
    print(f"\nCylindre détecté : axe {an}, rayon ≈ {frame['R']:.2f} mm, "
          f"centre ({un}={frame['uc']:.2f}, {vn}={frame['vc']:.2f}) mm")
    print(f"Vu depuis +{an}, plan ({un}, {vn}) :")
    print(f"  cadran 1 : +{un}, +{vn}  (0° -> 90°)")
    print(f"  cadran 2 : -{un}, +{vn}  (90° -> 180°)")
    print(f"  cadran 3 : -{un}, -{vn}  (180° -> 270°)")
    print(f"  cadran 4 : +{un}, -{vn}  (270° -> 360°)")
    quadrant = QUADRANT or ask_choice(
        "Quel cadran projeter ?",
        {"1": 1, "2": 2, "3": 3, "4": 4}, default=1)

do_crop = CROP if CROP is not None else ask_choice(
    "Avec crop (zone réduite) ?", {"o": True, "n": False}, default=False)

if mode == "3D":
    if do_crop:
        b = list(mesh.bounds)   # xmin, xmax, ymin, ymax, zmin, zmax
        print("\nDéfinis la zone à conserver (Entrée = garder la valeur actuelle). Unités : mm.")
        for i, name in enumerate("XYZ"):
            b[2 * i], b[2 * i + 1] = ask_range(f"{name} min", f"{name} max", b[2 * i], b[2 * i + 1])
        mesh = crop_mesh_box(mesh, b)
        deviation_mm = np.asarray(mesh.point_data["deviation_mm"], dtype=np.float32)
        print(f"Crop appliqué : {mesh.n_points} sommets, {mesh.n_cells} faces conservés.")

    # ------------------------------------------------------------------
    # 5a. Rendu 3D (PyVista)
    # ------------------------------------------------------------------
    suffix = "3d" + ("_crop" if do_crop else "")
    screenshot = str(OUT_DIR / f"deviation_map_{suffix}.png")

    plotter = pv.Plotter(window_size=(1272, 825))
    plotter.set_background("lightgray", top="black")
    plotter.add_mesh(
        mesh,
        scalars="deviation_mm",
        cmap=CMAP,
        clim=CLIM,                # même échelle avec ou sans crop -> comparable
        smooth_shading=True,
        scalar_bar_args={
            "title": "Surface Mesh - Deviation Map to Pores Mesh (mm)",
            "color": DRAGONFLY_BLUE,
            "n_labels": 9,
            "fmt": "%.2f",
            "vertical": False,
            "position_x": 0.1,
            "position_y": 0.06,
            "width": 0.8,
            "height": 0.05,
            "title_font_size": 16,
            "label_font_size": 14,
        },
    )
    plotter.add_axes()
    plotter.camera_position = "iso"
    plotter.show(screenshot=screenshot)
    print(f"Image enregistrée : {screenshot}")

else:
    # ------------------------------------------------------------------
    # 5b. Heatmap 2D du cadran déroulé (matplotlib)
    # ------------------------------------------------------------------
    xs = np.asarray(mesh.points)[:, frame["ax"]]
    x_rng = (float(xs.min()), float(xs.max()))
    t_rng = QUADRANT_RANGES[quadrant]
    if do_crop:
        print("\nCrop 2D (Entrée = garder la valeur actuelle).")
        print(f"  Axial : position le long de l'axe {'XYZ'[frame['ax']]} en mm")
        x_rng = ask_range("Position min (mm)", "Position max (mm)", *x_rng)
        print(f"  Angulaire : à l'intérieur du cadran {quadrant} ({t_rng[0]:.0f}° -> {t_rng[1]:.0f}°)")
        a_lo, a_hi = ask_range("Angle min (°)", "Angle max (°)", *t_rng)
        t_rng = (max(a_lo, t_rng[0]), min(a_hi, t_rng[1]))

    suffix = f"2d_q{quadrant}" + ("_crop" if do_crop else "")
    render_unrolled_heatmap(mesh, deviation_mm, frame, quadrant,
                            (x_rng, t_rng), str(OUT_DIR / f"deviation_map_{suffix}.png"))

# ----------------------------------------------------------------------
# 6. (Optionnel) PyTorch3D  -- utilise le maillage affiché (cropé ou non)
# ----------------------------------------------------------------------
try:
    import torch
    from pytorch3d.structures import Meshes
    from pytorch3d.renderer import TexturesVertex

    device = "cuda" if torch.cuda.is_available() else "cpu"

    points = np.asarray(mesh.points, dtype=np.float32)
    faces = mesh.faces.reshape(-1, 4)[:, 1:].astype(np.int64)   # [3,i,j,k] -> [i,j,k]

    verts_t = torch.tensor(points, device=device)
    faces_t = torch.tensor(faces, device=device)

    colors01 = matplotlib.colormaps[CMAP](
        np.clip((deviation_mm - CLIM[0]) / (CLIM[1] - CLIM[0]), 0, 1))[:, :3].astype(np.float32)
    colors_t = torch.tensor(colors01, device=device)
    dev_t = torch.tensor(deviation_mm, device=device)           # valeur brute en mm

    p3d_mesh = Meshes(
        verts=[verts_t],
        faces=[faces_t],
        textures=TexturesVertex(verts_features=[colors_t]),
    )
    print("Mesh PyTorch3D créé :", p3d_mesh)

except ImportError:
    print("PyTorch3D non installé : étape 6 ignorée.")
