import os
import re
import tkinter as tk
from tkinter import filedialog, messagebox

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import matplotlib.colors as mcolors

from matplotlib.ticker import FuncFormatter
from matplotlib.patches import FancyBboxPatch

# ============================================================
# PARAMETERS
# ============================================================

NB_BINS = 30

# Porosity noise threshold
# Volume-Equivalent Diameter <= this value is considered noise
SEUIL_BRUIT_DIAMETRE = 0.01

# Columns never plotted in porosity mode
COLONNES_IGNOREES = [
    "time step",
    "label index",
    "label",
    "index",
    "none",
    "id"
]

# Optional unit conversions
# Example:
# CONVERSIONS_UNITES = {"mm": ("µm", 1000)}
CONVERSIONS_UNITES = {}

# ============================================================
# ROUGHNESS PARAMETERS
# ============================================================

METRIQUES_LONGUEUR = [
    "Sa", "Sq", "Sv", "Sp", "Sz",
    "Ra", "Rq", "Rv", "Rp", "Rz"
]

METRIQUES_SANS_UNITE = [
    "Ssk", "Sku", "Rsk", "Rku"
]

# ============================================================
# ENGLISH TITLES
# ============================================================

TITRES_POROSITE = {
    "distance to surface": "Distance to Surface",
    "aspect ratio": "Aspect Ratio",
    "center of mass x": "Center of Mass X",
    "center of mass y": "Center of Mass Y",
    "center of mass z": "Center of Mass Z",
    "sphericity": "Sphericity",
    "surface area": "Surface Area",
    "vertex count": "Vertex Count",
    "volume-equivalent diameter": "Volume-Equivalent Diameter",
    "volume equivalent diameter": "Volume-Equivalent Diameter",
    "volume": "Pore Volume",
    "elongation": "Elongation",
    "flatness": "Flatness",
    "anisotropy": "Anisotropy",
    "compactness": "Compactness"
}

# ============================================================
# POROSITY HISTOGRAM COLORS (vivid gradient: cyan -> blue -> violet -> pink)
# ============================================================

PALETTES_POROSITE = [
    ["#00B4D8", "#2D6CDF", "#7B2FF7", "#E91E8C"],  # cyan -> blue -> violet -> pink
    ["#FFC300", "#FF7B00", "#F72585", "#7209B7"],  # yellow -> orange -> pink -> purple
    ["#B5E61D", "#06D6A0", "#118AB2", "#073B8C"],  # lime -> green -> blue -> navy
    ["#FF5D8F", "#C77DFF", "#5A60F0", "#00C2E0"],  # pink -> lilac -> indigo -> cyan
    ["#FF9F1C", "#E63946", "#9D1FA8", "#3A0CA3"],  # orange -> red -> magenta -> indigo
    ["#2EC4B6", "#3A86FF", "#8338EC", "#FF006E"],  # teal -> blue -> violet -> pink
]

CMAPS_POROSITE = [
    mcolors.LinearSegmentedColormap.from_list(f"porosite_{i}", couleurs)
    for i, couleurs in enumerate(PALETTES_POROSITE)
]

# ============================================================
# GRAPHIC STYLE
# ============================================================

sns.set_theme(
    style="whitegrid",
    context="notebook"
)

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "axes.titleweight": "bold",
    "axes.labelweight": "bold",
    "axes.edgecolor": "#333333",
    "axes.linewidth": 0.8,
    "xtick.color": "#333333",
    "ytick.color": "#333333",
    "figure.facecolor": "white",
    "axes.facecolor": "#FAFBFC"
})


# ============================================================
# GENERAL UTILITIES
# ============================================================

def normaliser(texte):
    """Normalize text for robust column/metric detection."""
    texte = str(texte).strip().lower()

    remplacements = [
        ("é", "e"),
        ("è", "e"),
        ("ê", "e"),
        ("ë", "e"),
        ("à", "a"),
        ("â", "a"),
        ("ä", "a"),
        ("î", "i"),
        ("ï", "i"),
        ("ô", "o"),
        ("ö", "o"),
        ("ù", "u"),
        ("û", "u"),
        ("ü", "u"),
        ("ç", "c")
    ]

    for avant, apres in remplacements:
        texte = texte.replace(avant, apres)

    return texte


def lire_csv(chemin):
    """Read CSV using automatic separator detection."""

    try:
        df = pd.read_csv(
            chemin,
            sep=None,
            engine="python"
        )

        print(
            f"CSV loaded successfully: "
            f"{os.path.basename(chemin)}"
        )

        print(f"Number of rows: {len(df)}")

        return df

    except Exception as erreur:
        print(
            f"Error reading {chemin}: {erreur}"
        )
        return None


def separer_nom_unite(nom_colonne):
    """
    Split a column name such as:
        Volume (mm³)
    into:
        Volume
        mm³
    """

    nom = str(nom_colonne).strip()

    correspondance = re.match(
        r"^(.*?)\s*\(([^)]*)\)\s*$",
        nom
    )

    if correspondance:
        return (
            correspondance.group(1).strip(),
            correspondance.group(2).strip()
        )

    return nom, None


def trouver_colonne(df, alias):
    """Find a column using normalized aliases."""

    for colonne in df.columns:

        nom = normaliser(colonne)

        for fragment in alias:

            if fragment in nom:
                return colonne

    return None


# ============================================================
# ROUGHNESS (bar charts of mean metrics, single file or batch)
# ============================================================

def recuperer_metriques(df, liste_metriques):
    """
    Retrieve roughness metrics from a CSV.

    Case 1: metrics are columns (mean of each column is used)
    Case 2: table with a 'Metric' column and a 'Value' column
    """

    resultats = {}

    # --- Case 1: metrics are columns ---
    for metrique in liste_metriques:

        colonne_trouvee = None

        for colonne in df.columns:

            if str(colonne).strip().lower() == metrique.lower():
                colonne_trouvee = colonne
                break

        if colonne_trouvee is not None:

            valeurs = pd.to_numeric(
                df[colonne_trouvee],
                errors="coerce"
            ).dropna()

            if len(valeurs) > 0:
                resultats[metrique] = valeurs.mean()

    # --- Case 2: Metric / Value table ---
    if len(resultats) == 0:

        colonne_metrique = None
        colonne_valeur = None

        for colonne in df.columns:

            nom = str(colonne).strip().lower()

            if nom in [
                "métrique",
                "metrique",
                "metric",
                "metrics"
            ]:
                colonne_metrique = colonne

            if nom in [
                "valeur",
                "value",
                "val",
                "resultat"
            ]:
                colonne_valeur = colonne

        if (
                colonne_metrique is not None
                and colonne_valeur is not None
        ):

            for _, ligne in df.iterrows():

                nom = str(
                    ligne[colonne_metrique]
                ).strip()

                valeur = pd.to_numeric(
                    ligne[colonne_valeur],
                    errors="coerce"
                )

                for metrique in liste_metriques:

                    if nom.lower() == metrique.lower():

                        if pd.notna(valeur):
                            resultats[metrique] = float(
                                valeur
                            )

    return resultats


def creer_graphique_rugosite(
        donnees,
        titre,
        nom_fichier,
        unite,
        dossier_export
):
    """Create a bar chart (rounded bars) of roughness metrics."""

    if len(donnees) == 0:
        return False

    df_graphique = pd.DataFrame({
        "Metric": list(donnees.keys()),
        "Value": list(donnees.values())
    })

    if unite == "µm":
        palette = sns.color_palette(
            "crest",
            n_colors=len(df_graphique)
        )
    else:
        palette = sns.color_palette(
            "flare",
            n_colors=len(df_graphique)
        )

    fig, ax = plt.subplots(
        figsize=(12, 7),
        dpi=150,
        constrained_layout=True
    )

    positions = range(len(df_graphique))
    valeurs = df_graphique["Value"].values
    largeur = 0.68

    vmin_val = float(min(valeurs))
    vmax_val = float(max(valeurs))

    vmax_abs = max(abs(vmin_val), abs(vmax_val))

    if vmax_abs == 0:
        vmax_abs = 1.0

    marge = vmax_abs * 0.15

    if vmin_val >= 0:
        ax.set_ylim(0, vmax_val + marge)
    elif vmax_val <= 0:
        ax.set_ylim(vmin_val - marge, 0)
    else:
        ax.set_ylim(vmin_val - marge, vmax_val + marge)

    for i, (valeur, couleur) in enumerate(
            zip(valeurs, palette)
    ):

        if valeur >= 0:
            hauteur = valeur
            bas = 0
        else:
            hauteur = abs(valeur)
            bas = valeur

        barre = FancyBboxPatch(
            (i - largeur / 2, bas),
            largeur,
            hauteur,
            boxstyle="round,pad=0.015,rounding_size=0.045",
            linewidth=0,
            facecolor=couleur,
            edgecolor="none",
            zorder=3
        )

        ax.add_patch(barre)

    marge_valeur = vmax_abs * 0.025

    for i, valeur in enumerate(valeurs):

        if valeur >= 0:
            y = valeur + marge_valeur
            va = "bottom"
        else:
            y = valeur - marge_valeur
            va = "top"

        if abs(valeur) >= 100:
            texte = f"{valeur:.0f}"
        elif abs(valeur) >= 10:
            texte = f"{valeur:.1f}"
        else:
            texte = f"{valeur:.3g}"

        ax.text(
            i,
            y,
            texte,
            ha="center",
            va=va,
            fontsize=10,
            fontweight="bold",
            color="#222222",
            zorder=5
        )

    ax.set_xlim(
        -0.65,
        len(df_graphique) - 0.35
    )

    nom_propre = os.path.splitext(
        nom_fichier
    )[0]

    ax.set_title(
        titre,
        fontsize=18,
        fontweight="bold",
        color="#20252B",
        pad=22
    )

    ax.text(
        0.5,
        1.015,
        nom_propre,
        transform=ax.transAxes,
        ha="center",
        va="bottom",
        fontsize=10.5,
        color="#707780"
    )

    ax.set_xlabel(
        "Metric",
        fontsize=12,
        fontweight="bold",
        labelpad=12
    )

    ax.set_ylabel(
        f"Value ({unite})",
        fontsize=12,
        fontweight="bold",
        labelpad=12
    )

    ax.set_xticks(list(positions))

    ax.set_xticklabels(
        df_graphique["Metric"],
        fontsize=11,
        fontweight="bold"
    )

    ax.tick_params(axis="x", length=0, pad=8)
    ax.tick_params(axis="y", labelsize=10, length=0)

    ax.grid(
        axis="y",
        linestyle="-",
        linewidth=0.7,
        alpha=0.22,
        zorder=0
    )

    ax.grid(axis="x", visible=False)

    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_color("#D0D4D8")
    ax.spines["bottom"].set_color("#D0D4D8")

    ax.axhline(
        0,
        linewidth=1,
        color="#333333",
        alpha=0.7,
        zorder=2
    )

    ax.set_facecolor("#FAFBFC")

    if unite == "µm":
        suffixe = "length_metrics"
    else:
        suffixe = "shape_parameters"

    nom_image = f"{nom_propre}_{suffixe}.png"

    chemin = os.path.join(
        dossier_export,
        nom_image
    )

    plt.savefig(
        chemin,
        dpi=300,
        bbox_inches="tight",
        facecolor="white"
    )

    plt.close()

    print(f"Created: {nom_image}")

    return True


def traiter_fichier_rugosite(
        chemin_csv,
        dossier_export
):
    """Process one roughness CSV (length metrics + shape parameters)."""

    nom_fichier = os.path.basename(chemin_csv)

    print(f"\n[Roughness] Processing: {nom_fichier}")

    df = lire_csv(chemin_csv)

    if df is None:
        return False

    # Length metrics (m -> µm)
    longueurs = recuperer_metriques(
        df,
        METRIQUES_LONGUEUR
    )

    longueurs_um = {
        nom: valeur * 1e6
        for nom, valeur in longueurs.items()
    }

    # Dimensionless shape parameters
    sans_unite = recuperer_metriques(
        df,
        METRIQUES_SANS_UNITE
    )

    ok_1 = creer_graphique_rugosite(
        longueurs_um,
        "Length Metrics (µm)",
        nom_fichier,
        "µm",
        dossier_export
    )

    ok_2 = creer_graphique_rugosite(
        sans_unite,
        "Shape Parameters (dimensionless)",
        nom_fichier,
        "dimensionless",
        dossier_export
    )

    if not (ok_1 or ok_2):
        print("No roughness parameter found.")

    return ok_1 or ok_2


def traiter_dossier_rugosite(
        dossier_csv,
        dossier_export
):
    """
    Batch mode: process every CSV of a folder.
    Returns (number of files processed OK, number of CSV found).
    """

    fichiers_csv = sorted(
        f for f in os.listdir(dossier_csv)
        if f.lower().endswith(".csv")
    )

    nb_ok = 0

    for fichier in fichiers_csv:

        chemin = os.path.join(dossier_csv, fichier)

        try:
            if traiter_fichier_rugosite(
                    chemin,
                    dossier_export
            ):
                nb_ok += 1
        except Exception as erreur:
            print(f"Error on {fichier}: {erreur}")

    return nb_ok, len(fichiers_csv)


# ============================================================
# POROSITY
# ============================================================

def construire_parametre_porosite(
        colonne,
        indice
):
    """Build metadata for a porosity parameter."""

    nom_base, unite_brute = (
        separer_nom_unite(colonne)
    )

    if unite_brute is None:

        unite = "dimensionless"
        facteur = 1.0

    elif unite_brute.lower() in CONVERSIONS_UNITES:

        unite, facteur = CONVERSIONS_UNITES[
            unite_brute.lower()
        ]

    else:

        unite = unite_brute
        facteur = 1.0

    nom_norm = normaliser(nom_base)

    titre = f"Distribution of {nom_base}"

    for fragment, titre_connu in TITRES_POROSITE.items():

        if fragment in nom_norm:
            titre = titre_connu
            break

    suffixe = re.sub(
        r"[^a-z0-9]+",
        "_",
        nom_norm
    ).strip("_")

    borne_01 = (
            "sphericity" in nom_norm
            or "sphericite" in nom_norm
    )

    centre_masse = "center of mass" in nom_norm

    return {
        "colonne": colonne,
        "titre": titre,
        "label_x": nom_base,
        "unite": unite,
        "facteur": facteur,
        "suffixe": suffixe,
        "borne_01": borne_01,
        "centre_masse": centre_masse,
        "indice": indice
    }


def detecter_parametres_porosite(df):
    """
    Automatically detect all numerical pore parameters.
    Identification columns are ignored.
    """

    parametres = []

    for colonne in df.columns:

        nom_base, _ = (
            separer_nom_unite(colonne)
        )

        nom_normalise = normaliser(
            nom_base
        )

        if nom_normalise in COLONNES_IGNOREES:
            continue

        valeurs = pd.to_numeric(
            df[colonne],
            errors="coerce"
        ).dropna()

        if len(valeurs) == 0:
            print(
                f"Non-numerical column ignored: "
                f"{colonne}"
            )

            continue

        if valeurs.nunique() <= 1:
            print(
                f"Constant column ignored: "
                f"{colonne}"
            )

            continue

        parametres.append(
            construire_parametre_porosite(
                colonne,
                len(parametres)
            )
        )

    return parametres


def filtrer_bruit(df):
    """
    Remove pores considered as noise.

    Criteria:
        Sphericity == 0
        OR
        Volume-Equivalent Diameter <= threshold
    """

    col_sph = trouver_colonne(
        df,
        [
            "sphericity",
            "sphericite"
        ]
    )

    col_diam = trouver_colonne(
        df,
        [
            "volume-equivalent diameter",
            "volume equivalent diameter"
        ]
    )

    masque_bruit = pd.Series(
        False,
        index=df.index
    )

    if col_sph is not None:
        sph = pd.to_numeric(
            df[col_sph],
            errors="coerce"
        )

        masque_bruit |= (
                sph == 0
        )

    if col_diam is not None:
        diam = pd.to_numeric(
            df[col_diam],
            errors="coerce"
        )

        masque_bruit |= (
                diam <= SEUIL_BRUIT_DIAMETRE
        )

    return df[
        ~masque_bruit
    ]


def creer_histogramme_porosite(
        valeurs,
        parametre,
        nom_fichier,
        dossier_export,
        exclusion_active
):
    """Create an English porosity histogram."""

    valeurs = np.asarray(
        valeurs,
        dtype=float
    )

    valeurs = valeurs[
        np.isfinite(valeurs)
    ]

    if len(valeurs) == 0:
        return

    moyenne = float(np.mean(valeurs))
    mediane = float(np.median(valeurs))

    if len(valeurs) > 1:
        ecart_type = float(
            np.std(
                valeurs,
                ddof=1
            )
        )
    else:
        ecart_type = 0.0

    vmin = float(np.min(valeurs))
    vmax = float(np.max(valeurs))

    fig, ax = plt.subplots(
        figsize=(12, 7),
        dpi=150,
        constrained_layout=True
    )

    # A different palette for each parameter (cycles through the list)
    cmap_param = CMAPS_POROSITE[
        parametre["indice"] % len(CMAPS_POROSITE)
        ]

    couleur = mcolors.to_hex(cmap_param(0.5))

    if exclusion_active and vmax > vmin:

        bins = np.linspace(
            vmin,
            vmax,
            NB_BINS + 1
        )

    elif parametre["borne_01"]:

        bins = np.linspace(
            0,
            1,
            NB_BINS + 1
        )

    elif vmax > vmin:

        bins = np.linspace(
            vmin,
            vmax,
            NB_BINS + 1
        )

    else:

        bins = np.histogram_bin_edges(
            valeurs,
            bins=NB_BINS
        )

    sns.histplot(
        valeurs,
        bins=bins,
        color=couleur,
        edgecolor="white",
        linewidth=0.8,
        alpha=0.90,
        ax=ax,
        zorder=3
    )

    # Vivid gradient: each bar is colored by its position along x
    barres = [p for p in ax.patches if p.get_width() > 0]

    if len(barres) > 0:

        centres = np.array([
            p.get_x() + p.get_width() / 2
            for p in barres
        ])

        c_min, c_max = centres.min(), centres.max()

        if c_max > c_min:
            positions_norm = (centres - c_min) / (c_max - c_min)
        else:
            positions_norm = np.full(len(barres), 0.5)

        for barre, t in zip(barres, positions_norm):
            barre.set_facecolor(cmap_param(t))

    ax.axvline(
        moyenne,
        color="#20252B",
        linestyle="--",
        linewidth=1.8,
        zorder=5,
        label=f"Mean = {moyenne:.4g}"
    )

    ax.axvline(
        mediane,
        color="#D68A27",
        linestyle="-",
        linewidth=1.8,
        zorder=5,
        label=f"Median = {mediane:.4g}"
    )

    ax2 = ax.twinx()

    couleur_courbe = tuple(
        0.55 * c
        for c in mcolors.to_rgb(couleur)
    )

    if len(valeurs) > 1 and np.std(valeurs) > 0:

        try:

            sns.kdeplot(
                valeurs,
                ax=ax2,
                color=couleur_courbe,
                linewidth=2.5,
                cut=0,
                clip=(vmin, vmax),
                zorder=6
            )

            if len(ax2.lines) > 0:
                ligne = ax2.lines[-1]

                x_k, y_k = ligne.get_data()

                ligne.remove()

                y_k = np.asarray(
                    y_k,
                    dtype=float
                )

                ax2.plot(
                    x_k,
                    y_k,
                    color=couleur_courbe,
                    linewidth=2.5,
                    label="Probability density",
                    zorder=6
                )

                ax2.fill_between(
                    x_k,
                    y_k,
                    color=couleur_courbe,
                    alpha=0.15,
                    zorder=5
                )

        except Exception as erreur:

            print(
                "KDE could not be calculated: "
                f"{erreur}"
            )

    if parametre["unite"] == "dimensionless":

        label_densite = "Probability density"

    else:

        label_densite = (
            "Probability density "
            f"(1/{parametre['unite']})"
        )

    ax2.set_ylabel(
        label_densite,
        fontsize=12,
        fontweight="bold",
        labelpad=12
    )

    ax2.set_ylim(bottom=0)
    ax2.grid(False)

    ax2.tick_params(
        axis="y",
        labelsize=10,
        length=0
    )

    ax2.spines["top"].set_visible(False)
    ax2.spines["left"].set_visible(False)
    ax2.spines["right"].set_color("#D0D4D8")

    handles_1, labels_1 = (
        ax.get_legend_handles_labels()
    )

    handles_2, labels_2 = (
        ax2.get_legend_handles_labels()
    )

    if mediane > (vmin + vmax) / 2:
        position_legende = "upper left"
    else:
        position_legende = "upper right"

    ax2.legend(
        handles_1 + handles_2,
        labels_1 + labels_2,
        loc=position_legende,
        frameon=True,
        framealpha=0.95,
        edgecolor="#D0D4D8",
        fontsize=10
    ).set_zorder(10)

    if exclusion_active:

        xmax = vmax

        if parametre["borne_01"]:
            xmax = min(
                xmax,
                1.0
            )

        ax.set_xlim(
            vmin,
            xmax
        )

        if xmax > vmin:

            pas_min = (
                    0.06 *
                    (xmax - vmin)
            )

            graduations = []

            for t in ax.get_xticks():

                if (
                        vmin + pas_min
                        <= t
                        <= xmax
                ):
                    graduations.append(t)

            ax.set_xticks(
                [vmin] +
                graduations
            )

            def formatter_x(v, position):
                return f"{v:.3g}"

            ax.xaxis.set_major_formatter(
                FuncFormatter(formatter_x)
            )

    elif parametre["centre_masse"]:

        # Center of mass: start at the minimum of the series
        # (no forced zero, avoids empty white space)
        if vmax > vmin:
            marge = 0.01 * (vmax - vmin)
            ax.set_xlim(vmin - marge, vmax + marge)

    elif vmin >= 0:

        ax.set_xlim(left=0)

    ax.set_title(
        parametre["titre"],
        fontsize=19,
        fontweight="bold",
        color="#20252B",
        pad=22
    )

    sous_titre = (
        f"{nom_fichier}  |  "
        f"n = {len(valeurs)} pores"
    )

    if exclusion_active:
        sous_titre += "  |  Noise excluded"

    ax.text(
        0.5,
        1.015,
        sous_titre,
        transform=ax.transAxes,
        ha="center",
        va="bottom",
        fontsize=10.5,
        color="#707780"
    )

    if parametre["unite"] == "dimensionless":

        label_x = parametre["label_x"]

    else:

        label_x = (
            f"{parametre['label_x']} "
            f"({parametre['unite']})"
        )

    ax.set_xlabel(
        label_x,
        fontsize=12,
        fontweight="bold",
        labelpad=12
    )

    ax.set_ylabel(
        "Number of Pores",
        fontsize=12,
        fontweight="bold",
        labelpad=12
    )

    ax.tick_params(
        axis="both",
        labelsize=10,
        length=0
    )

    ax.grid(
        axis="y",
        linestyle="-",
        linewidth=0.7,
        alpha=0.22,
        zorder=0
    )

    ax.grid(
        axis="x",
        visible=False
    )

    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_color("#D0D4D8")
    ax.spines["bottom"].set_color("#D0D4D8")

    ax.set_facecolor("#FAFBFC")

    nom_image = (
        f"{nom_fichier}_"
        f"{parametre['suffixe']}.png"
    )

    chemin = os.path.join(
        dossier_export,
        nom_image
    )

    plt.savefig(
        chemin,
        dpi=300,
        bbox_inches="tight",
        facecolor="white"
    )

    plt.close()

    print(
        f"Created: {nom_image} | "
        f"Mean={moyenne:.4g} | "
        f"Median={mediane:.4g} | "
        f"Std={ecart_type:.4g}"
    )


def traiter_fichier_porosite(
        chemin_csv,
        dossier_export,
        exclure_nuls=False
):
    """Process one porosity CSV."""

    nom_fichier = os.path.splitext(
        os.path.basename(chemin_csv)
    )[0]

    print(
        f"\n[Porosity] Processing: "
        f"{nom_fichier}"
    )

    df = lire_csv(chemin_csv)

    if df is None:
        return False

    if exclure_nuls:
        avant = len(df)

        df = filtrer_bruit(df)

        print(
            f"Noise excluded: "
            f"{avant - len(df)} / {avant}"
        )

    parametres = detecter_parametres_porosite(
        df
    )

    if len(parametres) == 0:
        print(
            "No usable measurement "
            "columns found."
        )

        return False

    print("\nParameters plotted:")

    for p in parametres:
        print(
            f"  - {p['colonne']}"
        )

    nb_graphiques = 0

    for parametre in parametres:
        valeurs = pd.to_numeric(
            df[parametre["colonne"]],
            errors="coerce"
        ).dropna()

        valeurs = (
                valeurs *
                parametre["facteur"]
        )

        creer_histogramme_porosite(
            valeurs,
            parametre,
            nom_fichier,
            dossier_export,
            exclure_nuls
        )

        nb_graphiques += 1

    return nb_graphiques > 0


# ============================================================
# USER INTERFACE
# ============================================================

def demander_mode(root):
    """Ask roughness / porosity, and single file / batch (roughness)."""

    choix = {
        "valide": False,
        "mode": None,
        "exclure_nuls": False,
        "batch": False
    }

    fenetre = tk.Toplevel(root)

    fenetre.title(
        "Data Visualization"
    )

    fenetre.resizable(
        False,
        False
    )

    mode_var = tk.StringVar(
        value="roughness"
    )

    var_exclure = tk.BooleanVar(
        value=False
    )

    var_batch = tk.StringVar(
        value="single"
    )

    cadre = tk.Frame(
        fenetre,
        padx=25,
        pady=20
    )

    cadre.pack()

    tk.Label(
        cadre,
        text="Histogram Generator",
        font=("DejaVu Sans", 14, "bold")
    ).grid(
        row=0,
        column=0,
        sticky="w",
        pady=(0, 15)
    )

    tk.Label(
        cadre,
        text="Select the type of data to process:",
        font=("DejaVu Sans", 10)
    ).grid(
        row=1,
        column=0,
        sticky="w",
        pady=(0, 8)
    )

    tk.Radiobutton(
        cadre,
        text="Roughness",
        variable=mode_var,
        value="roughness",
        font=("DejaVu Sans", 10)
    ).grid(
        row=2,
        column=0,
        sticky="w"
    )

    # Roughness: single file or batch
    cadre_batch = tk.Frame(cadre)

    cadre_batch.grid(
        row=3,
        column=0,
        sticky="w",
        padx=(25, 0),
        pady=(0, 6)
    )

    rb_single = tk.Radiobutton(
        cadre_batch,
        text="Single file",
        variable=var_batch,
        value="single",
        font=("DejaVu Sans", 9)
    )

    rb_single.pack(anchor="w")

    rb_batch = tk.Radiobutton(
        cadre_batch,
        text="Batch (all CSV files of a folder)",
        variable=var_batch,
        value="batch",
        font=("DejaVu Sans", 9)
    )

    rb_batch.pack(anchor="w")

    tk.Radiobutton(
        cadre,
        text="Porosity",
        variable=mode_var,
        value="porosity",
        font=("DejaVu Sans", 10)
    ).grid(
        row=4,
        column=0,
        sticky="w",
        pady=(0, 8)
    )

    chk_exclure = tk.Checkbutton(
        cadre,
        text=(
            "Exclude porosity noise\n"
            f"(Sphericity = 0 or "
            f"Volume-Equivalent Diameter "
            f"≤ {SEUIL_BRUIT_DIAMETRE} mm)"
        ),
        variable=var_exclure,
        justify="left",
        font=("DejaVu Sans", 9)
    )

    chk_exclure.grid(
        row=5,
        column=0,
        sticky="w",
        pady=(5, 15)
    )

    def maj_etat(*_):
        """Enable only the options relevant to the selected mode."""
        if mode_var.get() == "roughness":
            rb_single.config(state="normal")
            rb_batch.config(state="normal")
            chk_exclure.config(state="disabled")
        else:
            rb_single.config(state="disabled")
            rb_batch.config(state="disabled")
            chk_exclure.config(state="normal")

    mode_var.trace_add("write", maj_etat)
    maj_etat()

    cadre_boutons = tk.Frame(
        cadre
    )

    cadre_boutons.grid(
        row=6,
        column=0,
        sticky="e"
    )

    def valider():

        choix["valide"] = True
        choix["mode"] = mode_var.get()
        choix["exclure_nuls"] = (
            var_exclure.get()
            if mode_var.get() == "porosity"
            else False
        )
        choix["batch"] = (
                var_batch.get() == "batch"
                and mode_var.get() == "roughness"
        )

        fenetre.destroy()

    tk.Button(
        cadre_boutons,
        text="Cancel",
        width=10,
        command=fenetre.destroy
    ).pack(
        side="left",
        padx=5
    )

    tk.Button(
        cadre_boutons,
        text="Continue",
        width=10,
        command=valider
    ).pack(
        side="left",
        padx=5
    )

    fenetre.protocol(
        "WM_DELETE_WINDOW",
        fenetre.destroy
    )

    fenetre.grab_set()
    fenetre.lift()
    fenetre.focus_force()

    root.wait_window(
        fenetre
    )

    if choix["valide"]:
        return choix

    return None


# ============================================================
# MAIN
# ============================================================

def main():
    root = tk.Tk()
    root.withdraw()

    choix = demander_mode(
        root
    )

    if choix is None:
        root.destroy()
        return

    mode = choix["mode"]

    exclure_nuls = (
        choix["exclure_nuls"]
    )

    batch = choix["batch"]

    # --------------------------------------------------------
    # SELECT FILE OR FOLDER
    # --------------------------------------------------------

    chemin_fichier = None
    dossier_csv = None

    if mode == "roughness" and batch:

        dossier_csv = filedialog.askdirectory(
            title="1/2 - Select the folder containing the CSV files"
        )

        if not dossier_csv:
            messagebox.showwarning(
                "Cancelled",
                "No CSV folder selected."
            )

            root.destroy()
            return

    else:

        chemin_fichier = filedialog.askopenfilename(
            title="1/2 - Select CSV file",
            filetypes=[
                (
                    "CSV files",
                    "*.csv"
                ),
                (
                    "All files",
                    "*.*"
                )
            ]
        )

        if not chemin_fichier:
            messagebox.showwarning(
                "Cancelled",
                "No CSV file selected."
            )

            root.destroy()
            return

    # --------------------------------------------------------
    # SELECT EXPORT DIRECTORY
    # --------------------------------------------------------

    dossier_export = filedialog.askdirectory(
        title="2/2 - Select output folder"
    )

    if not dossier_export:
        messagebox.showwarning(
            "Cancelled",
            "No output folder selected."
        )

        root.destroy()
        return

    # --------------------------------------------------------
    # OUTPUT DIRECTORY
    # --------------------------------------------------------

    if mode == "roughness":

        dossier_resultats = os.path.join(
            dossier_export,
            "Roughness_Histograms"
        )

    else:

        dossier_resultats = os.path.join(
            dossier_export,
            "Porosity_Histograms"
        )

    os.makedirs(
        dossier_resultats,
        exist_ok=True
    )

    # --------------------------------------------------------
    # PROCESS
    # --------------------------------------------------------

    nb_ok = 0
    nb_total = 0

    try:

        if mode == "roughness":

            if batch:

                nb_ok, nb_total = traiter_dossier_rugosite(
                    dossier_csv,
                    dossier_resultats
                )

                reussi = nb_ok > 0

                if nb_total == 0:
                    messagebox.showwarning(
                        "No file",
                        "No CSV file found in the selected folder."
                    )

                    root.destroy()
                    return

            else:

                reussi = traiter_fichier_rugosite(
                    chemin_fichier,
                    dossier_resultats
                )

        else:

            reussi = traiter_fichier_porosite(
                chemin_fichier,
                dossier_resultats,
                exclure_nuls
            )

    except Exception as erreur:

        print(
            f"Processing error: {erreur}"
        )

        reussi = False

        messagebox.showerror(
            "Processing error",
            f"An error occurred:\n\n{erreur}"
        )

    # --------------------------------------------------------
    # FINAL MESSAGE
    # --------------------------------------------------------

    if reussi:

        if mode == "roughness":

            if batch:
                detail = (
                    f"{nb_ok} / {nb_total} file(s) "
                    f"processed.\n\n"
                )
            else:
                detail = ""

            message = (
                "Roughness processing completed "
                "successfully!\n\n"
                f"{detail}"
                f"Results saved in:\n"
                f"{dossier_resultats}"
            )

        else:

            message = (
                "Porosity processing completed "
                "successfully!\n\n"
                "All numerical pore parameters "
                "were converted into histograms.\n\n"
                f"Results saved in:\n"
                f"{dossier_resultats}"
            )

        messagebox.showinfo(
            "Processing completed",
            message
        )

    elif mode == "roughness":

        messagebox.showerror(
            "Processing error",
            "No roughness parameter could be plotted."
        )

    else:

        messagebox.showerror(
            "Processing error",
            "No usable numerical pore parameter "
            "could be plotted."
        )

    root.destroy()


# ============================================================
# EXECUTION
# ============================================================

if __name__ == "__main__":
    main()
