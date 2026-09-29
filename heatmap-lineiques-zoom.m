function tiff_to_png()
%==========================================================================
% tiff_to_png.m
%--------------------------------------------------------------------------
% Lit un fichier .tif/.tiff (mode "single") ou tous les fichiers d'un
% dossier (mode "batch"), les visualise (heatmap) selon leur type détecté à
% partir du nom de fichier :
%     - "roughness"  -> carte de rugosité (colormap divergente centrée sur 0)
%     - "aligned"    -> surface alignée (colormap séquentielle)
% puis exporte chaque figure en PNG dans un dossier de sortie.
%
% Les données brutes des TIFF sont en MÈTRES -> converties en µm à l'affichage.
%
% Pipeline de lissage :
%     1) Débruitage (filtre gaussien ou médian) pour effacer le "grillage".
%     2) Sur-échantillonnage bicubique pour un rendu lisse.
%==========================================================================

    % =====================================================================
    %                                CONFIG
    % =====================================================================

    cfg = struct();

    % --- Dossiers / fichiers --------------------------------------------
    % Laisser à '' : une fenêtre s'ouvrira au lancement du script.
    cfg.INPUT_FOLDER = '';        % ex : 'C:\Users\moi\Desktop\TIFF_a_traiter'
    cfg.INPUT_FILE   = '';        % ex : 'C:\Users\moi\Desktop\image.tif'
    cfg.OUTPUT_FOLDER = '';       % ex : 'C:\Users\moi\Desktop\PNG_export'
    cfg.RECURSIVE = false;

    % 'single', 'batch', ou '' => fenêtre de dialogue
    cfg.PROCESS_MODE = '';

    % --- Unité des données brutes ---------------------------------------
    cfg.UNIT_FACTOR = 1e6;        % m -> µm
    cfg.UNIT_LABEL  = 'µm';

    % --- Taille de pixel / dimensions physiques -------------------------
    cfg.PIXEL_SIZE_MM   = [];     % ex : 0.05 (mm/pixel)
    cfg.SAMPLE_WIDTH_MM  = 40.52;
    cfg.SAMPLE_HEIGHT_MM = 27.28;

    % --- Lissage / sur-échantillonnage ----------------------------------
    cfg.APPLY_SMOOTHING = true;

    % --- Étape 1 : filtre anti-bruit ------------------------------------
    cfg.DENOISE_METHOD = 'gaussian';   % 'gaussian', 'median', ou '' (aucun)
    cfg.DENOISE_SIGMA  = 1.5;
    cfg.DENOISE_SIZE   = 3;

    % --- Étape 2 : sur-échantillonnage ----------------------------------
    cfg.SMOOTH_FACTOR = 4;
    cfg.SMOOTH_ORDER  = 3;             % (non utilisé, imresize utilise bicubique)
    cfg.MAX_SMOOTHED_PIXELS = 40e6;

    % --- Plage de la barre de couleur (µm) ------------------------------
    cfg.VMIN = [];
    cfg.VMAX = [];

    % --- Zoom manuel ----------------------------------------------------
    cfg.XLIM = [6, 20];
    cfg.YLIM = [0, 3.5];

    % --- Colormaps ------------------------------------------------------
    cfg.CMAP_ROUGHNESS = 'jet';
    cfg.CMAP_ALIGNED   = 'jet';

    % --- Colorbar -------------------------------------------------------
    cfg.COLORBAR_ORIENTATION = 'horizontal';   % 'horizontal' ou 'vertical'

    % --- Habillage des figures ------------------------------------------
    cfg.DPI = 200;
    cfg.TARGET_LONG_SIDE_INCHES = 16.0;
    cfg.MIN_SHORT_SIDE_INCHES   = 9.0;
    cfg.MAX_PIXELS_DIM = 20000;

    cfg.TITLE_FONTSIZE      = 20;
    cfg.AXIS_LABEL_FONTSIZE = 16;
    cfg.TICK_FONTSIZE       = 14;
    cfg.CBAR_LABEL_FONTSIZE = 16;
    cfg.CBAR_TICK_FONTSIZE  = 14;

    % =====================================================================
    %                            FIN DE LA CONFIG
    % =====================================================================

    % Résolution des entrées
    [mode, tiff_files, output_folder] = resolve_inputs(cfg);
    if isempty(tiff_files)
        fprintf('Aucun fichier .tif/.tiff trouvé.\n');
        return;
    end

    fprintf('%d fichier(s) à traiter.\n\n', numel(tiff_files));

    n_ok = 0; n_fail = 0;
    for k = 1:numel(tiff_files)
        path = tiff_files{k};
        [~, name, ext] = fileparts(path);
        fprintf('--- Traitement de %s%s ---\n', name, ext);
        try
            out_path = plot_tiff_to_png(path, output_folder, cfg);
            ftype = detect_file_type([name ext]);
            fprintf('[OK] %s%s  (type=%s)  -> %s\n\n', name, ext, ftype, out_path);
            n_ok = n_ok + 1;
        catch e
            fprintf('[ERREUR] %s%s : %s\n', name, ext, e.message);
            fprintf('%s\n\n', getReport(e));
            n_fail = n_fail + 1;
        end
    end

    fprintf('Terminé : %d succès, %d échec(s).\n', n_ok, n_fail);
    fprintf('PNG exportés dans : %s\n', output_folder);
end


% =========================================================================
%  Fonctions utilitaires
% =========================================================================

function [mode, tiff_files, output_folder] = resolve_inputs(cfg)
    mode = cfg.PROCESS_MODE;
    if isempty(mode) && ~isempty(cfg.INPUT_FILE)
        mode = 'single';
    end
    if isempty(mode)
        mode = ask_mode();
    end
    if ~ismember(mode, {'single','batch'})
        fprintf('Aucun mode sélectionné. Arrêt.\n');
        error('Aucun mode sélectionné.');
    end

    if strcmp(mode, 'single')
        if ~isempty(cfg.INPUT_FILE)
            path = cfg.INPUT_FILE;
        else
            path = select_file('Sélectionner le fichier TIFF à traiter');
        end
        if isempty(path)
            fprintf('Aucun fichier sélectionné. Arrêt.\n');
            error('Aucun fichier sélectionné.');
        end
        fprintf('Mode : image unique -> %s\n', path);
        tiff_files = {path};
    else
        if ~isempty(cfg.INPUT_FOLDER)
            input_folder = cfg.INPUT_FOLDER;
        else
            input_folder = select_folder('Sélectionner le dossier contenant les fichiers TIFF');
        end
        if isempty(input_folder)
            fprintf('Aucun dossier d''entrée sélectionné. Arrêt.\n');
            error('Aucun dossier d''entrée sélectionné.');
        end
        fprintf('Mode : batch -> lecture des .tif/.tiff dans : %s\n', input_folder);
        tiff_files = find_tiff_files(input_folder, cfg.RECURSIVE);
    end

    if ~isempty(cfg.OUTPUT_FOLDER)
        output_folder = cfg.OUTPUT_FOLDER;
    else
        output_folder = select_folder('Sélectionner le dossier de destination des PNG');
    end
    if isempty(output_folder)
        fprintf('Aucun dossier de sortie sélectionné. Arrêt.\n');
        error('Aucun dossier de sortie sélectionné.');
    end
end


function folder = select_folder(title_str)
    folder = uigetdir(pwd, title_str);
    if isequal(folder, 0)
        folder = '';
    end
end


function path = select_file(title_str)
    [file, folder] = uigetfile( ...
        {'*.tif;*.tiff;*.TIF;*.TIFF','Fichiers TIFF'; '*.*','Tous les fichiers'}, ...
        title_str);
    if isequal(file, 0)
        path = '';
    else
        path = fullfile(folder, file);
    end
end


function mode = ask_mode()
    % Petite fenêtre : une seule image ou batch
    mode = '';
    fig = uifigure('Name','Mode de traitement', 'Position',[500 400 460 200]);
    fig.WindowStyle = 'modal';

    uilabel(fig, 'Text','Que souhaitez-vous traiter ?', ...
        'FontWeight','bold','FontSize',14, ...
        'Position',[30 140 400 30]);

    uibutton(fig, 'Text','Une seule image', ...
        'Position',[50 50 160 60], 'FontSize',13, ...
        'ButtonPushedFcn', @(~,~) pick('single'));

    uibutton(fig, 'Text','Batch (tout un dossier)', ...
        'Position',[240 50 180 60], 'FontSize',13, ...
        'ButtonPushedFcn', @(~,~) pick('batch'));

    uiwait(fig);

    function pick(v)
        mode = v;
        delete(fig);
    end
end


function ftype = detect_file_type(filename)
    name_lower = lower(filename);
    if contains(name_lower, 'roughness') || contains(name_lower, 'rugosit')
        ftype = 'roughness';
    elseif contains(name_lower, 'aligned')
        ftype = 'aligned';
    else
        ftype = 'unknown';
    end
end


function arr = load_tiff(path, cfg)
    arr = imread(path);
    arr = double(arr);
    if ndims(arr) == 3
        arr = arr(:,:,1);
    end
    arr = arr * cfg.UNIT_FACTOR;
end


function arr = denoise(arr, cfg)
    if isempty(cfg.DENOISE_METHOD)
        return;
    end

    if any(isnan(arr(:)))
        mean_val = mean(arr(:), 'omitnan');
        arr(isnan(arr)) = mean_val;
    end

    switch lower(cfg.DENOISE_METHOD)
        case 'gaussian'
            if ~isempty(cfg.DENOISE_SIGMA) && cfg.DENOISE_SIGMA > 0
                arr = imgaussfilt(arr, cfg.DENOISE_SIGMA);
            end
        case 'median'
            sz = cfg.DENOISE_SIZE;
            if mod(sz,2) == 0, sz = sz + 1; end
            arr = medfilt2(arr, [sz sz], 'symmetric');
        otherwise
            fprintf('  [!] DENOISE_METHOD=''%s'' inconnu -> ignoré.\n', cfg.DENOISE_METHOD);
    end
end


function arr = smooth_upsample(arr, cfg)
    if ~cfg.APPLY_SMOOTHING
        return;
    end

    % Étape 1 : débruitage
    arr = denoise(arr, cfg);

    % Étape 2 : sur-échantillonnage
    [n_rows, n_cols] = size(arr);
    factor = cfg.SMOOTH_FACTOR;
    total_pixels = (n_rows * factor) * (n_cols * factor);
    if total_pixels > cfg.MAX_SMOOTHED_PIXELS
        max_factor_sq = cfg.MAX_SMOOTHED_PIXELS / (n_rows * n_cols);
        factor = max(1.0, sqrt(max_factor_sq));
        fprintf('  [i] Facteur de lissage réduit automatiquement à %.2f ', factor);
        fprintf('(image %dx%d trop grande pour x%d).\n', n_cols, n_rows, cfg.SMOOTH_FACTOR);
    end

    if factor <= 1
        return;
    end

    new_size = [round(n_rows*factor), round(n_cols*factor)];
    arr = imresize(arr, new_size, 'bicubic');
end


function pixel_size_mm = get_pixel_size_from_metadata(path)
    pixel_size_mm = [];
    try
        info = imfinfo(path);
        if isfield(info, 'XResolution') && ~isempty(info.XResolution)
            x_res = info.XResolution;
            if iscell(x_res), x_res = x_res{1}; end
            if isnumeric(x_res) && numel(x_res) == 2
                pixels_per_unit = x_res(1) / x_res(2);
            else
                pixels_per_unit = double(x_res);
            end

            if ~pixels_per_unit || pixels_per_unit <= 0
                return;
            end

            unit_code = 2;
            if isfield(info, 'ResolutionUnit')
                unit_code = info.ResolutionUnit;
            end

            if ischar(unit_code) || isstring(unit_code)
                switch lower(char(unit_code))
                    case 'inch', mm_per_unit = 25.4;
                    case 'centimeter', mm_per_unit = 10.0;
                    otherwise, return;
                end
            else
                switch unit_code
                    case 2, mm_per_unit = 25.4;   % inch
                    case 3, mm_per_unit = 10.0;   % cm
                    otherwise, return;
                end
            end

            pixel_size_mm = mm_per_unit / pixels_per_unit;
        end
    catch
        pixel_size_mm = [];
    end
end


function ps = resolve_pixel_size_mm(path, cfg)
    if ~isempty(cfg.PIXEL_SIZE_MM)
        ps = cfg.PIXEL_SIZE_MM;
        return;
    end
    ps = get_pixel_size_from_metadata(path);
end


function [extent, is_mm] = resolve_extent(path, arr, cfg)
    [n_rows, n_cols] = size(arr);

    ps = resolve_pixel_size_mm(path, cfg);
    if ~isempty(ps)
        extent = [0, n_cols*ps, n_rows*ps, 0];
        is_mm = true;
        return;
    end

    if ~isempty(cfg.SAMPLE_WIDTH_MM) && ~isempty(cfg.SAMPLE_HEIGHT_MM)
        extent = [0, cfg.SAMPLE_WIDTH_MM, cfg.SAMPLE_HEIGHT_MM, 0];
        is_mm = true;
        return;
    end

    [~, name, ext] = fileparts(path);
    fprintf('  [!] Taille de pixel introuvable pour %s%s -> axes affichés en pixels.\n', ...
        name, ext);
    extent = [0, n_cols, n_rows, 0];
    is_mm = false;
end


function figsize = compute_figsize(extent, cfg)
    x_span = abs(extent(2) - extent(1));
    y_span = abs(extent(3) - extent(4));
    if x_span == 0 || y_span == 0
        figsize = [cfg.TARGET_LONG_SIDE_INCHES, cfg.TARGET_LONG_SIDE_INCHES*3/4];
        return;
    end

    ratio = x_span / y_span;

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


function dpi = get_effective_dpi(figsize, cfg)
    largest_inches = max(figsize);
    dpi = cfg.DPI;
    if largest_inches * dpi > cfg.MAX_PIXELS_DIM
        dpi = cfg.MAX_PIXELS_DIM / largest_inches;
    end
end


function [vmin, vmax] = get_vrange(arr, cfg)
    if ~isempty(cfg.VMIN)
        vmin = cfg.VMIN;
    else
        vmin = prctile(arr(:), 1);
    end
    if ~isempty(cfg.VMAX)
        vmax = cfg.VMAX;
    else
        vmax = prctile(arr(:), 99);
    end
end


function out_path = plot_tiff_to_png(tiff_path, output_folder, cfg)
    [~, base_name, ext] = fileparts(tiff_path);
    filename = [base_name ext];
    file_type = detect_file_type(filename);

    arr = load_tiff(tiff_path, cfg);
    [extent, is_mm] = resolve_extent(tiff_path, arr, cfg);
    [vmin, vmax] = get_vrange(arr, cfg);

    arr_plot = smooth_upsample(arr, cfg);

    figsize = compute_figsize(extent, cfg);
    effective_dpi = get_effective_dpi(figsize, cfg);

    fig = figure('Visible','off', 'Units','inches', ...
        'Position',[1 1 figsize(1) figsize(2)], ...
        'PaperPositionMode','auto', ...
        'Color','w');

    ax = axes('Parent', fig);

    switch file_type
        case 'roughness'
            if vmin < 0 && vmax > 0
                % Colormap divergente centrée sur 0
                n = 256;
                neg = round(n * (-vmin) / (vmax - vmin));
                pos = n - neg;
                cmap = [flipud(jet(neg)); jet(pos)];
                % Simpler : utiliser jet direct + caxis symétrique
                max_abs = max(abs(vmin), abs(vmax));
                imagesc(ax, arr_plot, [-max_abs, max_abs]);
            else
                imagesc(ax, arr_plot, [vmin vmax]);
            end
            colormap(ax, cfg.CMAP_ROUGHNESS);
            cbar_label = sprintf('Rugosité (%s)', cfg.UNIT_LABEL);
            title_str = sprintf('%s - Surface roughness map (vue de dessus)', base_name);

        case 'aligned'
            imagesc(ax, arr_plot, [vmin vmax]);
            colormap(ax, cfg.CMAP_ALIGNED);
            cbar_label = sprintf('Hauteur (%s)', cfg.UNIT_LABEL);
            title_str = sprintf('%s - Aligned surface map (vue de dessus)', base_name);

        otherwise
            imagesc(ax, arr_plot, [vmin vmax]);
            colormap(ax, 'jet');
            cbar_label = sprintf('Valeur (%s)', cfg.UNIT_LABEL);
            title_str = sprintf('%s (type non reconnu)', base_name);
    end

    axis(ax, 'image');
    set(ax, 'YDir', 'reverse');

    % Appliquer l'extent
    xlim(ax, [extent(1), extent(2)]);
    ylim(ax, [extent(3), extent(4)]);

    % --- axes ---
    if is_mm
        xlabel(ax, 'Y (mm)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
        ylabel(ax, 'Z (mm)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
    else
        xlabel(ax, 'Y (px)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
        ylabel(ax, 'Z (px)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
    end

    title(ax, title_str, 'FontSize', cfg.TITLE_FONTSIZE, 'FontWeight','bold');
    set(ax, 'FontSize', cfg.TICK_FONTSIZE);

    % --- zoom manuel ---
    if ~isempty(cfg.XLIM)
        xl = cfg.XLIM;
        if xl(1) < xl(2)
            xlim(ax, xl);
        else
            fprintf('  [!] XLIM=[%g %g] invalide -> ignoré.\n', xl(1), xl(2));
        end
    end
    if ~isempty(cfg.YLIM)
        yl = cfg.YLIM;
        if yl(1) < yl(2)
            ylim(ax, [yl(2), yl(1)]);  % inversé car YDir='reverse'
        else
            fprintf('  [!] YLIM=[%g %g] invalide -> ignoré.\n', yl(1), yl(2));
        end
    end

    % --- colorbar ---
    cb = colorbar(ax, 'Location', cfg.COLORBAR_ORIENTATION);
    cb.Label.String = cbar_label;
    cb.Label.FontSize = cfg.CBAR_LABEL_FONTSIZE;
    cb.FontSize = cfg.CBAR_TICK_FONTSIZE;

    % --- export PNG ---
    if ~exist(output_folder, 'dir')
        mkdir(output_folder);
    end
    out_path = fullfile(output_folder, [base_name '.png']);

    % exportgraphics est plus fiable pour les résolutions élevées
    try
        exportgraphics(fig, out_path, 'Resolution', effective_dpi);
    catch
        print(fig, out_path, '-dpng', sprintf('-r%d', round(effective_dpi)));
    end
    close(fig);
end


function files = find_tiff_files(input_folder, recursive)
    patterns = {'*.tif','*.tiff','*.TIF','*.TIFF'};
    files = {};
    for p = 1:numel(patterns)
        if recursive
            d = dir(fullfile(input_folder, '**', patterns{p}));
        else
            d = dir(fullfile(input_folder, patterns{p}));
        end
        for k = 1:numel(d)
            files{end+1} = fullfile(d(k).folder, d(k).name); %#ok<AGROW>
        end
    end
    files = unique(files);
    files = sort(files);
end
