import os
import tkinter as tk
from tkinter import filedialog, messagebox

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

from matplotlib.patches import FancyBboxPatch


# ============================================================
# PARAMETRES
# ============================================================

METRIQUES_LONGUEUR = [
    "Sa",
    "Sq",
    "Sv",
    "Sp",
    "Sz",
    "Ra",
    "Rq",
    "Rv",
    "Rp",
    "Rz"
]

METRIQUES_SANS_UNITE = [
    "Ssk",
    "Sku",
    "Rsk",
    "Rku"
]


# ============================================================
# STYLE GENERAL
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
# LECTURE CSV
# ============================================================

def lire_csv(chemin):

    try:

        df = pd.read_csv(
            chemin,
            sep=None,
            engine="python"
        )

        return df

    except Exception as erreur:

        print(
            f"Erreur lecture {chemin} : {erreur}"
        )

        return None


# ============================================================
# RECUPERATION DES METRIQUES
# ============================================================

def recuperer_metriques(df, liste_metriques):

    resultats = {}

    # --------------------------------------------------------
    # CAS : les métriques sont les colonnes
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # CAS : tableau Métrique / Valeur
    # --------------------------------------------------------

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


# ============================================================
# CREATION DU GRAPHIQUE
# ============================================================

def creer_graphique(
    donnees,
    titre,
    nom_fichier,
    unite,
    dossier_export
):

    if len(donnees) == 0:
        return

    # --------------------------------------------------------
    # DATAFRAME
    # --------------------------------------------------------

    df_graphique = pd.DataFrame({
        "Métrique": list(donnees.keys()),
        "Valeur": list(donnees.values())
    })

    # --------------------------------------------------------
    # PALETTE
    # --------------------------------------------------------

    if unite == "µm":

        # Palette bleu / cyan
        palette = sns.color_palette(
            "crest",
            n_colors=len(df_graphique)
        )

    else:

        # Palette violet / rose
        palette = sns.color_palette(
            "flare",
            n_colors=len(df_graphique)
        )

    # --------------------------------------------------------
    # FIGURE
    # --------------------------------------------------------

    fig, ax = plt.subplots(
        figsize=(12, 7),
        dpi=150,
        constrained_layout=True
    )

    # --------------------------------------------------------
    # DONNEES
    # --------------------------------------------------------

    positions = range(len(df_graphique))

    valeurs = df_graphique["Valeur"].values

    largeur = 0.68

    # --------------------------------------------------------
    # LIMITES Y (CALCULEES AVANT DESSIN)
    # --------------------------------------------------------

    if len(valeurs) > 0:

        vmin_val = float(min(valeurs))
        vmax_val = float(max(valeurs))

    else:

        vmin_val = 0.0
        vmax_val = 1.0

    # Échelle de référence pour les marges
    vmax_abs = max(abs(vmin_val), abs(vmax_val))

    if vmax_abs == 0:
        vmax_abs = 1.0

    # Marge relative de 15 %
    marge = vmax_abs * 0.15

    # Calcul des limites selon le signe des valeurs
    if vmin_val >= 0:

        # Toutes positives
        ax.set_ylim(0, vmax_val + marge)

    elif vmax_val <= 0:

        # Toutes négatives
        ax.set_ylim(vmin_val - marge, 0)

    else:

        # Mélange positif / négatif
        ax.set_ylim(vmin_val - marge, vmax_val + marge)

    # --------------------------------------------------------
    # BARRES AVEC COINS ARRONDIS
    # --------------------------------------------------------

    for i, (valeur, couleur) in enumerate(
        zip(valeurs, palette)
    ):

        # Cas positif
        if valeur >= 0:

            hauteur = valeur
            bas = 0

        # Cas négatif
        else:

            hauteur = abs(valeur)
            bas = valeur

        barre = FancyBboxPatch(
            (
                i - largeur / 2,
                bas
            ),
            largeur,
            hauteur,
            boxstyle="round,pad=0.015,rounding_size=0.045",
            linewidth=0,
            facecolor=couleur,
            edgecolor="none",
            zorder=3
        )

        ax.add_patch(barre)

    # --------------------------------------------------------
    # VALEURS AU-DESSUS DES BARRES
    # --------------------------------------------------------

    marge_valeur = vmax_abs * 0.025

    for i, valeur in enumerate(valeurs):

        if valeur >= 0:

            y = valeur + marge_valeur
            va = "bottom"

        else:

            y = valeur - marge_valeur
            va = "top"

        # Format intelligent
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

    # --------------------------------------------------------
    # LIMITES X
    # --------------------------------------------------------

    ax.set_xlim(
        -0.65,
        len(df_graphique) - 0.35
    )

    # --------------------------------------------------------
    # TITRE
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # SOUS-TITRE
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # AXES
    # --------------------------------------------------------

    ax.set_xlabel(
        "Métrique",
        fontsize=12,
        fontweight="bold",
        labelpad=12
    )

    ax.set_ylabel(
        f"Valeur ({unite})",
        fontsize=12,
        fontweight="bold",
        labelpad=12
    )

    # --------------------------------------------------------
    # LABELS X
    # --------------------------------------------------------

    ax.set_xticks(
        list(positions)
    )

    ax.set_xticklabels(
        df_graphique["Métrique"],
        fontsize=11,
        fontweight="bold"
    )

    ax.tick_params(
        axis="x",
        length=0,
        pad=8
    )

    ax.tick_params(
        axis="y",
        labelsize=10,
        length=0
    )

    # --------------------------------------------------------
    # GRILLE
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # BORDURES
    # --------------------------------------------------------

    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    ax.spines["left"].set_color("#D0D4D8")
    ax.spines["bottom"].set_color("#D0D4D8")

    # --------------------------------------------------------
    # PETITE LIGNE DE REFERENCE
    # --------------------------------------------------------

    ax.axhline(
        0,
        linewidth=1,
        color="#333333",
        alpha=0.7,
        zorder=2
    )

    # --------------------------------------------------------
    # FOND
    # --------------------------------------------------------

    ax.set_facecolor(
        "#FAFBFC"
    )

    # --------------------------------------------------------
    # NOM DU FICHIER
    # --------------------------------------------------------

    nom_base = os.path.splitext(
        nom_fichier
    )[0]

    if unite == "µm":

        suffixe = "metriques_longueur"

    else:

        suffixe = "parametres_forme"

    nom_image = (
        f"{nom_base}_{suffixe}.png"
    )

    chemin = os.path.join(
        dossier_export,
        nom_image
    )

    # --------------------------------------------------------
    # EXPORT
    # --------------------------------------------------------

    plt.savefig(
        chemin,
        dpi=300,
        bbox_inches="tight",
        facecolor="white"
    )

    plt.close()

    print(
        f"Créé : {nom_image}"
    )


# ============================================================
# TRAITEMENT D'UN FICHIER
# ============================================================

def traiter_fichier(
    chemin_csv,
    dossier_export
):

    nom_fichier = os.path.basename(
        chemin_csv
    )

    print(
        f"\nTraitement : {nom_fichier}"
    )

    df = lire_csv(
        chemin_csv
    )

    if df is None:
        return

    # --------------------------------------------------------
    # METRIQUES DE LONGUEUR
    # --------------------------------------------------------

    longueurs = recuperer_metriques(
        df,
        METRIQUES_LONGUEUR
    )

    # Conversion m -> µm
    longueurs_um = {}

    for nom, valeur in longueurs.items():

        longueurs_um[nom] = valeur * 1e6

    # --------------------------------------------------------
    # PARAMETRES DE FORME
    # --------------------------------------------------------

    sans_unite = recuperer_metriques(
        df,
        METRIQUES_SANS_UNITE
    )

    # --------------------------------------------------------
    # GRAPHIQUE LONGUEUR
    # --------------------------------------------------------

    creer_graphique(
        longueurs_um,
        "Métriques de longueur (µm)",
        nom_fichier,
        "µm",
        dossier_export
    )

    # --------------------------------------------------------
    # GRAPHIQUE FORME
    # --------------------------------------------------------

    creer_graphique(
        sans_unite,
        "Paramètres de forme (sans unité)",
        nom_fichier,
        "sans unité",
        dossier_export
    )


# ============================================================
# PROGRAMME PRINCIPAL
# ============================================================

def main():

    root = tk.Tk()

    root.withdraw()

    # ========================================================
    # DOSSIER CSV
    # ========================================================

    dossier_csv = filedialog.askdirectory(
        title="1/2 - Sélectionner le dossier contenant les CSV"
    )

    if not dossier_csv:

        messagebox.showwarning(
            "Annulation",
            "Aucun dossier CSV sélectionné."
        )

        root.destroy()
        return

    # ========================================================
    # DOSSIER EXPORT
    # ========================================================

    dossier_export = filedialog.askdirectory(
        title="2/2 - Sélectionner le dossier d'export"
    )

    if not dossier_export:

        messagebox.showwarning(
            "Annulation",
            "Aucun dossier d'export sélectionné."
        )

        root.destroy()
        return

    # ========================================================
    # DOSSIER RESULTATS
    # ========================================================

    dossier_resultats = os.path.join(
        dossier_export,
        "Histogrammes"
    )

    os.makedirs(
        dossier_resultats,
        exist_ok=True
    )

    # ========================================================
    # RECHERCHE DES CSV
    # ========================================================

    fichiers_csv = [
        fichier
        for fichier in os.listdir(dossier_csv)
        if fichier.lower().endswith(".csv")
    ]

    if len(fichiers_csv) == 0:

        messagebox.showwarning(
            "Aucun fichier",
            "Aucun fichier CSV trouvé."
        )

        root.destroy()
        return

    # ========================================================
    # TRAITEMENT
    # ========================================================

    nombre = 0

    for fichier in fichiers_csv:

        chemin = os.path.join(
            dossier_csv,
            fichier
        )

        traiter_fichier(
            chemin,
            dossier_resultats
        )

        nombre += 1

    # ========================================================
    # FIN
    # ========================================================

    messagebox.showinfo(
        "Traitement terminé",
        f"Traitement terminé !\n\n"
        f"{nombre} fichier(s) traité(s).\n\n"
        f"Résultats enregistrés dans :\n"
        f"{dossier_resultats}"
    )

    root.destroy()


# ============================================================
# EXECUTION
# ============================================================

if __name__ == "__main__":
    main()
