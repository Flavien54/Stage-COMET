function tiff_to_png()
%==========================================================================
% tiff_to_png.m
%--------------------------------------------------------------------------
% Lit tous les fichiers .tif / .tiff d'un dossier, les visualise (heatmap)
% selon leur type détecté à partir du nom de fichier :
%     - "roughness"  -> carte de rugosité (colormap divergente centrée sur 0)
%     - "aligned"    -> surface alignée (colormap séquentielle)
% puis exporte chaque figure en PNG dans un dossier de sortie.
%
% Les données brutes des TIFF sont en MÈTRES -> converties en µm à
% l'affichage (comme dans le script de référence : UNIT_FACTOR = 1e6).
%
% Options réglables dans la section CONFIG ci-dessous :
%     - VMIN / VMAX : plage de la barre de couleur (en µm)
%     - XLIM / YLIM : zoom manuel sur une zone (mêmes unités que les axes)
%     - PIXEL_SIZE_MM : taille de pixel pour convertir les axes X/Y en mm
%
% Toutes ces options sont à [] par défaut (comportement automatique,
% pas de zoom, échelle de couleur auto-calée sur les données).
%
% Au lancement, une fenêtre s'ouvre pour choisir le dossier d'entrée puis
% le dossier de sortie (uigetdir), sauf si les chemins sont renseignés en
% dur dans INPUT_FOLDER / OUTPUT_FOLDER.
%
% Nécessite l'Image Processing Toolbox (imresize).
%==========================================================================

    %======================================================================
    %                               CONFIG
    %======================================================================

    % --- Dossiers --------------------------------------------------------
    % Laisser vide ('') : une fenêtre s'ouvrira au lancement pour choisir
    % le dossier d'entrée puis le dossier de sortie. Renseigner un chemin
    % en dur permet de sauter la fenêtre correspondante (utile en automatisé).
    cfg.INPUT_FOLDER  = '';          % ex : 'C:\Users\moi\Desktop\TIFF_a_traiter'
    cfg.OUTPUT_FOLDER = '';          % ex : 'C:\Users\moi\Desktop\PNG_export'
    cfg.RECURSIVE     = false;       % chercher aussi dans les sous-dossiers ?

    % --- Unité des données brutes -----------------------------------------
    cfg.UNIT_FACTOR = 1e6;           % m -> µm (mettre 1.0 si déjà en µm)
    cfg.UNIT_LABEL  = 'µm';

    % --- Taille de pixel / dimensions physiques -----------------------------
    % Utilisées pour afficher les axes X/Y en mm. Ordre de priorité :
    %   1) cfg.PIXEL_SIZE_MM, si renseigné (mm/pixel, pixels carrés) ;
    %   2) les métadonnées du TIFF (XResolution/ResolutionUnit), si présentes ;
    %   3) SAMPLE_WIDTH_MM / SAMPLE_HEIGHT_MM (dimensions physiques totales
    %      connues du champ scanné, appliquées à TOUS les fichiers du lot,
    %      indépendamment du nombre de pixels de chacun) ;
    %   4) à défaut, axes affichés en pixels (avertissement console).
    cfg.PIXEL_SIZE_MM    = [];       % ex : 0.05
    cfg.SAMPLE_WIDTH_MM  = [];       % ex : 34.96
    cfg.SAMPLE_HEIGHT_MM = [];       % ex : 23.57

    % --- Lissage / sur-échantillonnage (comme le script de référence) -------
    % Sur-échantillonnage par interpolation bicubique (équivalent
    % scipy.ndimage.zoom, order=3) avant affichage, pour un rendu lisse au
    % lieu du grain brut pixel par pixel. Activé par défaut.
    cfg.APPLY_SMOOTHING = true;
    cfg.SMOOTH_FACTOR = 4;           % facteur de sur-échantillonnage
    cfg.SMOOTH_METHOD = 'bicubic';   % équivalent order=3 de scipy.zoom
    % Garde-fou : si (n_lignes*facteur) x (n_colonnes*facteur) dépasse ce
    % nombre de pixels, le facteur est réduit automatiquement.
    cfg.MAX_SMOOTHED_PIXELS = 40000000;

    % --- Plage de la colorbar, en µm ---------------------------------------
    % [] = calage automatique (percentiles 1-99 des données).
    cfg.VMIN = [];                   % ex : -100
    cfg.VMAX = [];                   % ex : 100

    % --- Zoom manuel (mêmes unités que les axes : mm si taille de pixel
    %     connue, pixels sinon) ------------------------------------------
    cfg.XLIM = [];                   % ex : [5 20]  -> axe horizontal (Y)
    cfg.YLIM = [];                   % ex : [0 10]  -> axe vertical   (Z)

    % --- Colormaps -----------------------------------------------------------
    cfg.CMAP_ROUGHNESS = jet(256);   % colormap divergente centrée sur 0
    cfg.CMAP_ALIGNED   = jet(256);   % colormap séquentielle

    % --- Colorbar -------------------------------------------------------------
    cfg.COLORBAR_ORIENTATION = 'horizontal'; % 'horizontal' ou 'vertical'

    % --- Habillage des figures ------------------------------------------------
    cfg.DPI = 200;

    % Taille de figure : la plus grande dimension est fixée à
    % TARGET_LONG_SIDE_INCHES, l'autre suit le ratio des données (aspect
    % préservé), avec un minimum MIN_SHORT_SIDE_INCHES pour garder de la
    % place aux titres/labels/colorbar.
    cfg.TARGET_LONG_SIDE_INCHES = 16.0;
    cfg.MIN_SHORT_SIDE_INCHES   = 9.0;
    cfg.MAX_PIXELS_DIM          = 20000;

    % --- Tailles de police (points) --------------------------------------------
    cfg.TITLE_FONTSIZE      = 20;
    cfg.AXIS_LABEL_FONTSIZE = 16;
    cfg.TICK_FONTSIZE       = 14;
    cfg.CBAR_LABEL_FONTSIZE = 16;
    cfg.CBAR_TICK_FONTSIZE  = 14;

    %======================================================================
    %                            FIN DE LA CONFIG
    %======================================================================

    main_run(cfg);
end


%% ------------------------------------------------------------------------
function main_run(cfg)
    [input_folder, output_folder] = resolve_folders(cfg);

    fprintf('Lecture des fichiers .tif/.tiff dans : %s\n', input_folder);
    tiff_files = find_tiff_files(input_folder, cfg.RECURSIVE);

    if isempty(tiff_files)
        fprintf('Aucun fichier .tif/.tiff trouvé.\n');
        return;
    end

    fprintf('%d fichier(s) trouvé(s).\n\n', numel(tiff_files));

    n_ok = 0;
    n_fail = 0;
    for k = 1:numel(tiff_files)
        path = tiff_files{k};
        try
            out_path = plot_tiff_to_png(path, output_folder, cfg);
            [~, name, ext] = fileparts(path);
            file_type = detect_file_type([name ext]);
            fprintf('[OK] %s%s  (type=%s)  -> %s\n', name, ext, file_type, out_path);
            n_ok = n_ok + 1;
        catch ME
            [~, name, ext] = fileparts(path);
            fprintf('[ERREUR] %s%s : %s\n', name, ext, ME.message);
            disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
            n_fail = n_fail + 1;
        end
    end

    fprintf('\nTerminé : %d succès, %d échec(s).\n', n_ok, n_fail);
    fprintf('PNG exportés dans : %s\n', output_folder);
end


%% ------------------------------------------------------------------------
function [input_folder, output_folder] = resolve_folders(cfg)
% Détermine le dossier d'entrée et le dossier de sortie : si renseignés en
% dur dans cfg, on les utilise directement (pas de fenêtre) ; sinon, on
% ouvre une fenêtre de sélection pour chacun.

    input_folder = cfg.INPUT_FOLDER;
    output_folder = cfg.OUTPUT_FOLDER;

    if isempty(input_folder)
        input_folder = uigetdir(pwd, 'Sélectionner le dossier contenant les fichiers TIFF');
        if isequal(input_folder, 0)
            error('Aucun dossier d''entrée sélectionné. Arrêt.');
        end
    end

    if isempty(output_folder)
        output_folder = uigetdir(pwd, 'Sélectionner le dossier de destination des PNG');
        if isequal(output_folder, 0)
            error('Aucun dossier de sortie sélectionné. Arrêt.');
        end
    end
end


%% ------------------------------------------------------------------------
function file_type = detect_file_type(filename)
% Détecte le type de fichier : 'roughness', 'aligned', ou 'unknown'.
    name_lower = lower(filename);
    if contains(name_lower, 'roughness') || contains(name_lower, 'rugosit')
        file_type = 'roughness';
    elseif contains(name_lower, 'aligned')
        file_type = 'aligned';
    else
        file_type = 'unknown';
    end
end


%% ------------------------------------------------------------------------
function arr = load_tiff(path, cfg)
% Charge un fichier .tif/.tiff en tableau 2D double, en mètres -> convertit
% selon UNIT_FACTOR.
    arr = imread(path);
    arr = double(arr);

    if ndims(arr) == 3
        arr = arr(:, :, 1);   % image multi-canaux -> on garde le 1er canal
    end

    arr = arr * cfg.UNIT_FACTOR;
end


%% ------------------------------------------------------------------------
function arr_out = smooth_upsample(arr, cfg)
% Sur-échantillonne arr par interpolation bicubique (comme le script de
% référence : scipy.ndimage.zoom, order=3), pour un rendu lisse au lieu du
% grain brut pixel par pixel. Le facteur est réduit automatiquement si le
% résultat dépasserait MAX_SMOOTHED_PIXELS.
    if ~cfg.APPLY_SMOOTHING
        arr_out = arr;
        return;
    end

    % Gestion des NaN avant interpolation (comme le script de référence)
    if any(isnan(arr(:)))
        mean_val = mean(arr(~isnan(arr)));
        arr(isnan(arr)) = mean_val;
    end

    [n_rows, n_cols] = size(arr);
    factor = cfg.SMOOTH_FACTOR;
    total_pixels = (n_rows * factor) * (n_cols * factor);
    if total_pixels > cfg.MAX_SMOOTHED_PIXELS
        max_factor_sq = cfg.MAX_SMOOTHED_PIXELS / (n_rows * n_cols);
        factor = max(1.0, sqrt(max_factor_sq));
        fprintf('  [i] Facteur de lissage réduit automatiquement à %.2f (image %dx%d trop grande pour x%g).\n', ...
            factor, n_cols, n_rows, cfg.SMOOTH_FACTOR);
    end

    if factor <= 1
        arr_out = arr;
        return;
    end

    arr_out = imresize(arr, factor, cfg.SMOOTH_METHOD);
end


%% ------------------------------------------------------------------------
function pixel_size_mm = get_pixel_size_from_metadata(path)
% Essaie de lire la taille de pixel (en mm) depuis les tags TIFF standards
% (XResolution + ResolutionUnit). Retourne [] si l'info n'est pas présente
% ou pas exploitable.
    pixel_size_mm = [];
    try
        info = imfinfo(path);
        info = info(1);

        if ~isfield(info, 'XResolution') || isempty(info.XResolution) || info.XResolution == 0
            return;
        end
        pixels_per_unit = info.XResolution;

        if isfield(info, 'ResolutionUnit')
            unit_str = lower(info.ResolutionUnit);
        else
            unit_str = 'inch';   % 2 = inch par défaut, comme le script Python
        end

        if contains(unit_str, 'inch')
            mm_per_unit = 25.4;
        elseif contains(unit_str, 'centimeter') || contains(unit_str, 'cm')
            mm_per_unit = 10.0;
        else
            return;   % unité "None" ou inconnue
        end

        pixel_size_mm = mm_per_unit / pixels_per_unit;
    catch
        pixel_size_mm = [];
    end
end


%% ------------------------------------------------------------------------
function pixel_size_mm = resolve_pixel_size_mm(path, cfg)
% Détermine la taille de pixel en mm à utiliser pour ce fichier.
    if ~isempty(cfg.PIXEL_SIZE_MM)
        pixel_size_mm = cfg.PIXEL_SIZE_MM;
        return;
    end

    pixel_size_mm = get_pixel_size_from_metadata(path);
end


%% ------------------------------------------------------------------------
function [extent, is_mm] = resolve_extent(path, arr, cfg)
% Détermine l'extent [xmin xmax ymin ymax] (convention Python : ymin est en
% bas, ymax=0 en haut, axe Y "inversé") à utiliser pour l'affichage, et si
% les axes doivent être en mm ou en pixels.
% Ordre de priorité : PIXEL_SIZE_MM -> métadonnées TIFF ->
% SAMPLE_WIDTH_MM/SAMPLE_HEIGHT_MM -> pixels (avec avertissement).
    [n_rows, n_cols] = size(arr);

    pixel_size_mm = resolve_pixel_size_mm(path, cfg);
    if ~isempty(pixel_size_mm)
        extent = [0, n_cols * pixel_size_mm, n_rows * pixel_size_mm, 0];
        is_mm = true;
        return;
    end

    if ~isempty(cfg.SAMPLE_WIDTH_MM) && ~isempty(cfg.SAMPLE_HEIGHT_MM)
        % Dimensions physiques totales connues, appliquées telles quelles,
        % indépendamment du nombre de pixels.
        extent = [0, cfg.SAMPLE_WIDTH_MM, cfg.SAMPLE_HEIGHT_MM, 0];
        is_mm = true;
        return;
    end

    [~, name, ext] = fileparts(path);
    fprintf(['  [!] Taille de pixel introuvable (ni PIXEL_SIZE_MM, ni métadonnées, ' ...
        'ni SAMPLE_WIDTH_MM/SAMPLE_HEIGHT_MM) pour %s%s -> axes affichés en pixels.\n'], name, ext);
    extent = [0, n_cols, n_rows, 0];
    is_mm = false;
end


%% ------------------------------------------------------------------------
function figsize = compute_figsize(extent, cfg)
% Calcule une taille de figure [largeur hauteur] en pouces en respectant le
% ratio largeur/hauteur des données (aspect préservé, pas de déformation),
% MAIS mise à l'échelle pour que la plus grande dimension soit
% TARGET_LONG_SIDE_INCHES.
%
% - La plus grande dimension est fixée à TARGET_LONG_SIDE_INCHES.
% - L'autre dimension suit le ratio, mais reste >= MIN_SHORT_SIDE_INCHES
%   pour garder de la place aux titres/labels/colorbar.
    x_span = abs(extent(2) - extent(1));
    y_span = abs(extent(3) - extent(4));

    if x_span == 0 || y_span == 0
        figsize = [cfg.TARGET_LONG_SIDE_INCHES, cfg.TARGET_LONG_SIDE_INCHES * 3 / 4];
        return;
    end

    ratio = x_span / y_span;   % > 1 si plus large que haut

    if ratio >= 1
        width = cfg.TARGET_LONG_SIDE_INCHES;
        height = width / ratio;
        if height < cfg.MIN_SHORT_SIDE_INCHES
            height = cfg.MIN_SHORT_SIDE_INCHES;
            width = height * ratio;
        end
    else
        height = cfg.TARGET_LONG_SIDE_INCHES;
        width = height * ratio;
        if width < cfg.MIN_SHORT_SIDE_INCHES
            width = cfg.MIN_SHORT_SIDE_INCHES;
            height = width / ratio;
        end
    end

    figsize = [width, height];
end


%% ------------------------------------------------------------------------
function dpi = get_effective_dpi(figsize, cfg)
% Réduit le DPI si nécessaire pour que la plus grande dimension du PNG
% final ne dépasse pas MAX_PIXELS_DIM pixels (évite des fichiers énormes
% sur les échantillons très allongés).
    largest_inches = max(figsize);
    dpi = cfg.DPI;
    if largest_inches * dpi > cfg.MAX_PIXELS_DIM
        dpi = cfg.MAX_PIXELS_DIM / largest_inches;
    end
end


%% ------------------------------------------------------------------------
function [vmin, vmax] = get_vrange(arr, cfg)
% Retourne (vmin, vmax) à utiliser pour la colorbar, en µm.
    valid = arr(~isnan(arr));
    if isempty(cfg.VMIN)
        vmin = prctile(valid, 1);
    else
        vmin = cfg.VMIN;
    end
    if isempty(cfg.VMAX)
        vmax = prctile(valid, 99);
    else
        vmax = cfg.VMAX;
    end
end


%% ------------------------------------------------------------------------
function norm_data = two_slope_normalize(arr, vmin, vcenter, vmax)
% Équivalent de matplotlib.colors.TwoSlopeNorm(vmin, vcenter, vmax) :
% mappe [vmin, vcenter] -> [0, 0.5] et [vcenter, vmax] -> [0.5, 1],
% linéairement de part et d'autre, pour centrer la colormap sur vcenter
% (typiquement 0) même si vmin/vmax ne sont pas symétriques.
    norm_data = zeros(size(arr));

    below = arr <= vcenter;
    above = ~below;

    if vcenter > vmin
        norm_data(below) = 0.5 * (arr(below) - vmin) / (vcenter - vmin);
    else
        norm_data(below) = 0.5;
    end

    if vmax > vcenter
        norm_data(above) = 0.5 + 0.5 * (arr(above) - vcenter) / (vmax - vcenter);
    else
        norm_data(above) = 0.5;
    end

    norm_data = min(max(norm_data, 0), 1);
end


%% ------------------------------------------------------------------------
function out_path = plot_tiff_to_png(tiff_path, output_folder, cfg)
% Lit un fichier tiff, le visualise selon son type, exporte en PNG.
    [~, base_name, ext] = fileparts(tiff_path);
    file_type = detect_file_type([base_name ext]);

    arr = load_tiff(tiff_path, cfg);
    [extent, is_mm] = resolve_extent(tiff_path, arr, cfg);
    [vmin, vmax] = get_vrange(arr, cfg);
    arr_plot = smooth_upsample(arr, cfg);

    figsize = compute_figsize(extent, cfg);
    effective_dpi = get_effective_dpi(figsize, cfg);

    fig = figure('Units', 'inches', 'Position', [1 1 figsize(1) figsize(2)], ...
        'Color', 'w', 'Visible', 'off');
    ax = axes('Parent', fig);
    hold(ax, 'on');

    x_data = [extent(1), extent(2)];
    y_data = [extent(4), extent(3)];   % extent(4)=0 (haut), extent(3)=bas

    use_two_slope = strcmp(file_type, 'roughness') && vmin < 0 && vmax > 0;

    switch file_type
        case 'roughness'
            cmap = cfg.CMAP_ROUGHNESS;
            cbar_label = sprintf('Rugosité (%s)', cfg.UNIT_LABEL);
            title_str = sprintf('%s - Surface roughness map (vue de dessus)', base_name);
        case 'aligned'
            cmap = cfg.CMAP_ALIGNED;
            cbar_label = sprintf('Hauteur (%s)', cfg.UNIT_LABEL);
            title_str = sprintf('%s - Aligned surface map (vue de dessus)', base_name);
        otherwise
            cmap = jet(256);
            cbar_label = sprintf('Valeur (%s)', cfg.UNIT_LABEL);
            title_str = sprintf('%s (type non reconnu)', base_name);
    end

    if use_two_slope
        % Colormap divergente centrée sur 0 (équivalent TwoSlopeNorm)
        norm_data = two_slope_normalize(arr_plot, vmin, 0, vmax);
        imagesc(ax, x_data, y_data, norm_data);
        clim(ax, [0 1]);
        colormap(ax, cmap);
    else
        imagesc(ax, x_data, y_data, arr_plot);
        clim(ax, [vmin vmax]);
        colormap(ax, cmap);
    end

    set(ax, 'YDir', 'reverse');   % origine en haut, comme imshow (origin='upper')
    axis(ax, 'equal');
    axis(ax, 'tight');

    % --- axes ---
    if is_mm
        xlabel(ax, 'Y (mm)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
        ylabel(ax, 'Z (mm)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
    else
        xlabel(ax, 'Y (px)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
        ylabel(ax, 'Z (px)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
    end

    title(ax, title_str, 'FontSize', cfg.TITLE_FONTSIZE, 'FontWeight', 'bold', ...
        'Interpreter', 'none');
    set(ax, 'FontSize', cfg.TICK_FONTSIZE);

    % --- zoom manuel ---
    if ~isempty(cfg.XLIM)
        xlim(ax, cfg.XLIM);
    end
    if ~isempty(cfg.YLIM)
        % l'axe Y est inversé (origine en haut) -> ylim prend juste
        % [min max], YDir='reverse' se charge de l'affichage.
        ylim(ax, sort(cfg.YLIM));
    end

    % --- colorbar ---
    if strcmpi(cfg.COLORBAR_ORIENTATION, 'horizontal')
        cb = colorbar(ax, 'southoutside');
    else
        cb = colorbar(ax, 'eastoutside');
    end
    cb.Label.String = cbar_label;
    cb.Label.FontSize = cfg.CBAR_LABEL_FONTSIZE;
    cb.FontSize = cfg.CBAR_TICK_FONTSIZE;

    if use_two_slope
        % La colorbar est en échelle normalisée [0,1] : on ré-étiquette les
        % graduations avec les vraies valeurs (µm) pour rester lisible.
        tick_vals = [vmin, vmin/2, 0, vmax/2, vmax];
        tick_pos = two_slope_normalize(tick_vals, vmin, 0, vmax);
        cb.Ticks = tick_pos;
        cb.TickLabels = arrayfun(@(v) sprintf('%.3g', v), tick_vals, 'UniformOutput', false);
    end

    % --- export ---
    if ~exist(output_folder, 'dir')
        mkdir(output_folder);
    end
    out_path = fullfile(output_folder, [base_name '.png']);

    exportgraphics(fig, out_path, 'Resolution', round(effective_dpi));
    close(fig);
end


%% ------------------------------------------------------------------------
function files = find_tiff_files(input_folder, recursive)
    patterns = {'*.tif', '*.tiff', '*.TIF', '*.TIFF'};
    files = {};
    for p = 1:numel(patterns)
        if recursive
            d = dir(fullfile(input_folder, '**', patterns{p}));
        else
            d = dir(fullfile(input_folder, patterns{p}));
        end
        for k = 1:numel(d)
            if ~d(k).isdir
                files{end+1} = fullfile(d(k).folder, d(k).name); %#ok<AGROW>
            end
        end
    end
    files = unique(files);
    files = sort(files);
end
