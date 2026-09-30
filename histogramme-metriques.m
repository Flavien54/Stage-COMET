%% ============================================================
%  PROGRAMME PRINCIPAL
%  Génération d'histogrammes de métriques de surface
%  à partir de fichiers CSV
%  ============================================================

function main()

    clc;
    close all;

    % ========================================================
    % PARAMETRES
    % ========================================================

    METRIQUES_LONGUEUR = {
        'Sa', 'Sq', 'Sv', 'Sp', 'Sz', ...
        'Ra', 'Rq', 'Rv', 'Rp', 'Rz'
    };

    METRIQUES_SANS_UNITE = {
        'Ssk', 'Sku', 'Rsk', 'Rku'
    };

    % ========================================================
    % DOSSIER CSV
    % ========================================================

    fprintf('1/2 - Sélectionner le dossier contenant les CSV\n');

    dossier_csv = uigetdir(pwd, ...
        '1/2 - Sélectionner le dossier contenant les CSV');

    if isequal(dossier_csv, 0)
        uiwait(msgbox(...
            'Aucun dossier CSV sélectionné.', ...
            'Annulation', 'warn', 'modal'));
        return;
    end

    % ========================================================
    % DOSSIER EXPORT
    % ========================================================

    fprintf('2/2 - Sélectionner le dossier d''export\n');

    dossier_export = uigetdir(pwd, ...
        '2/2 - Sélectionner le dossier d''export');

    if isequal(dossier_export, 0)
        uiwait(msgbox(...
            'Aucun dossier d''export sélectionné.', ...
            'Annulation', 'warn', 'modal'));
        return;
    end

    % ========================================================
    % DOSSIER RESULTATS
    % ========================================================

    dossier_resultats = fullfile(dossier_export, 'Histogrammes');

    if ~exist(dossier_resultats, 'dir')
        mkdir(dossier_resultats);
    end

    % ========================================================
    % RECHERCHE DES CSV
    % ========================================================

    listing = dir(fullfile(dossier_csv, '*.csv'));

    if isempty(listing)
        uiwait(msgbox(...
            'Aucun fichier CSV trouvé.', ...
            'Aucun fichier', 'warn', 'modal'));
        return;
    end

    % ========================================================
    % TRAITEMENT
    % ========================================================

    nombre = 0;

    for k = 1:numel(listing)

        chemin = fullfile(dossier_csv, listing(k).name);

        traiter_fichier(chemin, dossier_resultats, ...
            METRIQUES_LONGUEUR, METRIQUES_SANS_UNITE);

        nombre = nombre + 1;
    end

    % ========================================================
    % FIN
    % ========================================================

    message = sprintf(...
        'Traitement terminé !\n\n%d fichier(s) traité(s).\n\nRésultats enregistrés dans :\n%s', ...
        nombre, dossier_resultats);

    uiwait(msgbox(message, 'Traitement terminé', 'help', 'modal'));

end


%% ============================================================
%  LECTURE CSV
%  ============================================================

function df = lire_csv(chemin)

    try
        % Détection automatique du séparateur
        opts = detectImportOptions(chemin);
        opts.VariableNamingRule = 'preserve';

        df = readtable(chemin, opts);

        % Convertir toutes les colonnes numériques possibles
        for c = 1:width(df)
            if ~isnumeric(df{:, c}) && ~iscell(df{:, c})
                try
                    df.(df.Properties.VariableNames{c}) = ...
                        str2double(string(df{:, c}));
                catch
                    % garder tel quel
                end
            end
        end

    catch erreur
        fprintf('Erreur lecture %s : %s\n', chemin, erreur.message);
        df = [];
    end

end


%% ============================================================
%  RECUPERATION DES METRIQUES
%  ============================================================

function resultats = recuperer_metriques(df, liste_metriques)

    resultats = struct();

    if isempty(df)
        return;
    end

    noms_colonnes = df.Properties.VariableNames;

    % --------------------------------------------------------
    % CAS 1 : les métriques sont les colonnes
    % --------------------------------------------------------

    for m = 1:numel(liste_metriques)

        metrique = liste_metriques{m};
        colonne_trouvee = '';

        for c = 1:numel(noms_colonnes)

            if strcmpi(strtrim(noms_colonnes{c}), metrique)
                colonne_trouvee = noms_colonnes{c};
                break;
            end
        end

        if ~isempty(colonne_trouvee)

            valeurs = df.(colonne_trouvee);

            if ~isnumeric(valeurs)
                valeurs = str2double(string(valeurs));
            end

            valeurs = valeurs(~isnan(valeurs));

            if ~isempty(valeurs)
                resultats.(metrique) = mean(valeurs);
            end
        end
    end

    % --------------------------------------------------------
    % CAS 2 : tableau Métrique / Valeur
    % --------------------------------------------------------

    if numel(fieldnames(resultats)) == 0

        colonne_metrique = '';
        colonne_valeur = '';

        noms_metrique = {'métrique', 'metrique', 'metric', 'metrics'};
        noms_valeur   = {'valeur', 'value', 'val', 'resultat'};

        for c = 1:numel(noms_colonnes)

            nom = lower(strtrim(noms_colonnes{c}));

            if any(strcmp(nom, noms_metrique))
                colonne_metrique = noms_colonnes{c};
            end

            if any(strcmp(nom, noms_valeur))
                colonne_valeur = noms_colonnes{c};
            end
        end

        if ~isempty(colonne_metrique) && ~isempty(colonne_valeur)

            col_m = df.(colonne_metrique);
            col_v = df.(colonne_valeur);

            for i = 1:numel(col_m)

                nom = strtrim(string(col_m{i}));

                if iscell(col_v)
                    valeur = str2double(string(col_v{i}));
                else
                    valeur = col_v(i);
                end

                for m = 1:numel(liste_metriques)

                    metrique = liste_metriques{m};

                    if strcmpi(nom, metrique)

                        if ~isnan(valeur)
                            resultats.(metrique) = double(valeur);
                        end
                    end
                end
            end
        end
    end

end


%% ============================================================
%  CREATION DU GRAPHIQUE
%  ============================================================

function creer_graphique(donnees, titre, nom_fichier, unite, dossier_export)

    if numel(fieldnames(donnees)) == 0
        return;
    end

    % --------------------------------------------------------
    % DATAFRAME (tableau)
    % --------------------------------------------------------

    noms = fieldnames(donnees);
    valeurs = zeros(numel(noms), 1);

    for i = 1:numel(noms)
        valeurs(i) = donnees.(noms{i});
    end

    % --------------------------------------------------------
    % PALETTE
    % --------------------------------------------------------

    n = numel(valeurs);

    if strcmp(unite, 'µm')
        % Palette bleu / cyan (similaire à "crest")
        palette = palette_crest(n);
    else
        % Palette violet / rose (similaire à "flare")
        palette = palette_flare(n);
    end

    % --------------------------------------------------------
    % FIGURE
    % --------------------------------------------------------

    fig = figure('Units', 'pixels', ...
                 'Position', [100 100 1200 700], ...
                 'Color', 'white', ...
                 'Visible', 'off');

    ax = axes('Parent', fig, ...
              'Color', [0.98 0.984 0.988], ...
              'Box', 'off', ...
              'TickDir', 'out', ...
              'XColor', [0.2 0.2 0.2], ...
              'YColor', [0.2 0.2 0.2], ...
              'FontName', 'Helvetica', ...
              'FontSize', 10);

    hold(ax, 'on');

    % --------------------------------------------------------
    % BARRES
    % --------------------------------------------------------

    positions = 1:n;
    largeur = 0.68;

    % --------------------------------------------------------
    % LIMITES Y (CALCULEES AVANT DESSIN)
    % --------------------------------------------------------

    vmin_val = min(valeurs);
    vmax_val = max(valeurs);

    vmax_abs = max(abs(vmin_val), abs(vmax_val));

    if vmax_abs == 0
        vmax_abs = 1;
    end

    marge = vmax_abs * 0.15;

    if vmin_val >= 0
        ylim(ax, [0, vmax_val + marge]);
    elseif vmax_val <= 0
        ylim(ax, [vmin_val - marge, 0]);
    else
        ylim(ax, [vmin_val - marge, vmax_val + marge]);
    end

    % --------------------------------------------------------
    % BARRES AVEC COINS ARRONDIS
    % --------------------------------------------------------

    for i = 1:n

        valeur = valeurs(i);
        couleur = palette(i, :);

        if valeur >= 0
            hauteur = valeur;
            bas = 0;
        else
            hauteur = abs(valeur);
            bas = valeur;
        end

        % Rectangle avec coins arrondis
        rectangle_arrondi(ax, ...
            i - largeur/2, bas, ...
            largeur, hauteur, ...
            0.045, couleur);

    end

    % --------------------------------------------------------
    % VALEURS AU-DESSUS DES BARRES
    % --------------------------------------------------------

    marge_valeur = vmax_abs * 0.025;

    for i = 1:n

        valeur = valeurs(i);

        if valeur >= 0
            y = valeur + marge_valeur;
            va = 'bottom';
        else
            y = valeur - marge_valeur;
            va = 'top';
        end

        % Format intelligent
        if abs(valeur) >= 100
            texte = sprintf('%.0f', valeur);
        elseif abs(valeur) >= 10
            texte = sprintf('%.1f', valeur);
        else
            texte = sprintf('%.3g', valeur);
        end

        text(ax, i, y, texte, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', va, ...
            'FontSize', 10, ...
            'FontWeight', 'bold', ...
            'Color', [0.13 0.13 0.13]);
    end

    % --------------------------------------------------------
    % LIMITES X
    % --------------------------------------------------------

    xlim(ax, [-0.65, n + 0.65]);

    % --------------------------------------------------------
    % TITRE
    % --------------------------------------------------------

    [~, nom_base, ~] = fileparts(nom_fichier);

    title(ax, titre, ...
        'FontSize', 18, ...
        'FontWeight', 'bold', ...
        'Color', [0.13 0.14 0.17]);

    % --------------------------------------------------------
    % SOUS-TITRE
    % --------------------------------------------------------

    text(ax, 0.5, 1.015, nom_base, ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', ...
        'FontSize', 10.5, ...
        'Color', [0.44 0.47 0.50]);

    % --------------------------------------------------------
    % AXES
    % --------------------------------------------------------

    xlabel(ax, 'Métrique', ...
        'FontSize', 12, ...
        'FontWeight', 'bold');

    ylabel(ax, sprintf('Valeur (%s)', unite), ...
        'FontSize', 12, ...
        'FontWeight', 'bold');

    % --------------------------------------------------------
    % LABELS X
    % --------------------------------------------------------

    set(ax, 'XTick', positions);
    set(ax, 'XTickLabel', noms);
    set(ax, 'TickLabelInterpreter', 'none');
    set(ax, 'FontSize', 11);
    set(ax, 'FontWeight', 'bold');

    % --------------------------------------------------------
    % GRILLE
    % --------------------------------------------------------

    grid(ax, 'on');
    set(ax, 'GridAlpha', 0.22);
    set(ax, 'GridLineStyle', '-');
    set(ax, 'GridColor', [0.8 0.8 0.8]);
    set(ax, 'XGrid', 'off');
    set(ax, 'YGrid', 'on');
    set(ax, 'Layer', 'bottom');

    % --------------------------------------------------------
    % BORDURES
    % --------------------------------------------------------

    ax.Box = 'off';

    % --------------------------------------------------------
    % LIGNE DE REFERENCE A 0
    % --------------------------------------------------------

    plot(ax, xlim(ax), [0 0], ...
        'Color', [0.2 0.2 0.2 0.7], ...
        'LineWidth', 1);

    hold(ax, 'off');

    % --------------------------------------------------------
    % NOM DU FICHIER
    % --------------------------------------------------------

    if strcmp(unite, 'µm')
        suffixe = 'metriques_longueur';
    else
        suffixe = 'parametres_forme';
    end

    nom_image = sprintf('%s_%s.png', nom_base, suffixe);
    chemin = fullfile(dossier_export, nom_image);

    % --------------------------------------------------------
    % EXPORT
    % --------------------------------------------------------

    exportgraphics(fig, chemin, 'Resolution', 300, ...
        'BackgroundColor', 'white');

    close(fig);

    fprintf('Créé : %s\n', nom_image);

end


%% ============================================================
%  TRAITEMENT D'UN FICHIER
%  ============================================================

function traiter_fichier(chemin_csv, dossier_export, ...
                         METRIQUES_LONGUEUR, METRIQUES_SANS_UNITE)

    [~, nom_fichier, ext] = fileparts(chemin_csv);
    nom_fichier = [nom_fichier ext];

    fprintf('\nTraitement : %s\n', nom_fichier);

    df = lire_csv(chemin_csv);

    if isempty(df)
        return;
    end

    % --------------------------------------------------------
    % METRIQUES DE LONGUEUR
    % --------------------------------------------------------

    longueurs = recuperer_metriques(df, METRIQUES_LONGUEUR);

    % Conversion m -> µm
    longueurs_um = struct();
    noms = fieldnames(longueurs);

    for i = 1:numel(noms)
        longueurs_um.(noms{i}) = longueurs.(noms{i}) * 1e6;
    end

    % --------------------------------------------------------
    % PARAMETRES DE FORME
    % --------------------------------------------------------

    sans_unite = recuperer_metriques(df, METRIQUES_SANS_UNITE);

    % --------------------------------------------------------
    % GRAPHIQUE LONGUEUR
    % --------------------------------------------------------

    creer_graphique(longueurs_um, ...
        'Métriques de longueur (µm)', ...
        nom_fichier, 'µm', dossier_export);

    % --------------------------------------------------------
    % GRAPHIQUE FORME
    % --------------------------------------------------------

    creer_graphique(sans_unite, ...
        'Paramètres de forme (sans unité)', ...
        nom_fichier, 'sans unité', dossier_export);

end


%% ============================================================
%  UTILITAIRES : RECTANGLE ARRONDI
%  ============================================================

function rectangle_arrondi(ax, x, y, w, h, r, couleur)

    % Crée un rectangle avec coins arrondis (similaire à FancyBboxPatch)

    if h <= 0
        return;
    end

    theta = linspace(pi/2, pi, 20);
    xs1 = x + r + r*cos(theta);
    ys1 = y + r + r*sin(theta);

    theta = linspace(pi, 3*pi/2, 20);
    xs2 = x + r + r*cos(theta);
    ys2 = y + h - r + r*sin(theta);

    theta = linspace(3*pi/2, 2*pi, 20);
    xs3 = x + w - r + r*cos(theta);
    ys3 = y + h - r + r*sin(theta);

    theta = linspace(0, pi/2, 20);
    xs4 = x + w - r + r*cos(theta);
    ys4 = y + r + r*sin(theta);

    X = [xs1, xs2, xs3, xs4];
    Y = [ys1, ys2, ys3, ys4];

    fill(ax, X, Y, couleur, ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 1);
end


%% ============================================================
%  UTILITAIRES : PALETTES DE COULEURS
%  ============================================================

function palette = palette_crest(n)

    % Approximation de la palette seaborn "crest"
    % du vert clair au bleu foncé

    if n == 1
        palette = [0.32 0.70 0.55];
        return;
    end

    t = linspace(0, 1, n)';

    % Points de contrôle (inspirés de "crest")
    r = interp1([0 0.5 1], [0.42 0.20 0.05], t);
    g = interp1([0 0.5 1], [0.78 0.55 0.25], t);
    b = interp1([0 0.5 1], [0.60 0.60 0.55], t);

    palette = [r, g, b];
end


function palette = palette_flare(n)

    % Approximation de la palette seaborn "flare"
    % du rose saumon au violet foncé

    if n == 1
        palette = [0.75 0.35 0.45];
        return;
    end

    t = linspace(0, 1, n)';

    r = interp1([0 0.5 1], [0.95 0.80 0.40], t);
    g = interp1([0 0.5 1], [0.55 0.35 0.15], t);
    b = interp1([0 0.5 1], [0.45 0.55 0.55], t);

    palette = [r, g, b];
end
