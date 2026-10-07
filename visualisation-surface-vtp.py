"""
Visualisation d'un maillage de surface seul (VTP / VTK / PLY...), sans tableau de valeurs.

    pip install numpy pyvista

Usage :
    python view_surface.py                 -> fenêtre interactive
    python view_surface.py --save          -> enregistre l'image sans ouvrir de fenêtre
"""

import sys
from pathlib import Path

import numpy as np
import pyvista as pv

# ----------------------------------------------------------------------
# Paramètres
# ----------------------------------------------------------------------
MESH_PATH = None                # None = fenêtre de sélection ; ou un chemin complet entre r"..."
COORD_SCALE = 1000.0            # coordonnées du fichier en m -> mm
COULEUR = "#8fb4c9"             # couleur uniforme de la surface
OUT_PATH = Path(__file__).parent / "surface_3d.png"
SAVE = "--save" in sys.argv     # True = rendu hors-écran + enregistrement

# ----------------------------------------------------------------------
# Lecture + diagnostic
# ----------------------------------------------------------------------
def choisir_fichier():
    """Chemin : argument en ligne de commande, MESH_PATH, ou fenêtre de sélection."""
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if args:
        return args[0]
    if MESH_PATH and Path(MESH_PATH).exists():
        return MESH_PATH
    if MESH_PATH:
        print(f"Fichier introuvable : {MESH_PATH}")
    import tkinter as tk
    from tkinter import filedialog
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    chemin = filedialog.askopenfilename(
        title="Sélectionner le maillage (.vtp, .vtk, .ply, .stl...)",
        filetypes=[("Maillages", "*.vtp *.vtk *.ply *.stl *.obj"), ("Tous", "*.*")])
    root.destroy()
    if not chemin:
        raise SystemExit("Aucun fichier sélectionné.")
    return chemin


MESH_FILE = choisir_fichier()
print(f"Fichier : {MESH_FILE}")
mesh = pv.read(MESH_FILE)
if not isinstance(mesh, pv.PolyData):
    mesh = mesh.extract_surface()
if not mesh.is_all_triangles:
    mesh = mesh.triangulate()

mesh.points = np.asarray(mesh.points) * COORD_SCALE      # m -> mm
xmin, xmax, ymin, ymax, zmin, zmax = mesh.bounds
print(f"Sommets : {mesh.n_points:,} | Faces : {mesh.n_cells:,}")
print(f"X : {xmin:.3f} -> {xmax:.3f} mm (taille {xmax - xmin:.3f})")
print(f"Y : {ymin:.3f} -> {ymax:.3f} mm (taille {ymax - ymin:.3f})")
print(f"Z : {zmin:.3f} -> {zmax:.3f} mm (taille {zmax - zmin:.3f})")
print(f"Tableaux de valeurs : {list(mesh.point_data.keys()) + list(mesh.cell_data.keys()) or 'aucun (géométrie seule)'}")

mesh = mesh.compute_normals(auto_orient_normals=False, split_vertices=False)

# ----------------------------------------------------------------------
# Rendu : vue iso + vue le long de l'axe le plus long
# ----------------------------------------------------------------------
sizes = np.array([xmax - xmin, ymax - ymin, zmax - zmin])
axe = int(np.argmax(sizes))
vue_axe = ["yz", "xz", "xy"][axe]            # regarde le long de l'axe long

pl = pv.Plotter(shape=(1, 2), window_size=(1600, 800), off_screen=SAVE)

for col, titre in enumerate(("Vue isométrique", f"Vue le long de {'XYZ'[axe]}")):
    pl.subplot(0, col)
    pl.set_background("lightgray", top="black")
    pl.add_mesh(mesh, color=COULEUR, smooth_shading=True,
                specular=0.4, specular_power=20, show_edges=False)
    pl.add_axes()
    pl.add_text(titre, font_size=11, color="white", position="upper_left")
    if col == 0:
        pl.camera_position = "iso"
    else:
        pl.camera_position = vue_axe
    pl.reset_camera()

if SAVE:
    pl.screenshot(str(OUT_PATH))
    print(f"Image enregistrée : {OUT_PATH}")
else:
    pl.show(screenshot=str(OUT_PATH))
