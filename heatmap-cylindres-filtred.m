function tiff_to_png()
%==========================================================================
% tiff_to_png.m
%--------------------------------------------------------------------------
% Lit un fichier .tif/.tiff (mode "single") ou tous les fichiers d'un
% dossier (mode "batch"), les visualise (heatmap) selon leur type détecté
% à partir du nom de fichier, puis exporte en PNG.
%
% Adapté aux ÉCHANTILLONS CYLINDRIQUES découpés en tranches de 90° :
%   - crop automatique des bords (divergence capteur / bandes saturées)
%   - suppression des artefacts linéaires verticaux + interpolation
%   - lissage par filtre bilatéral (préserve les pics isolés)
%
% Les données brutes des TIFF sont en MÈTRES -> converties en µm.
%==========================================================================

    % =====================================================================
    %                                CONFIG
    % =====================================================================

    cfg = struct();

    % --- Dossiers / fichiers --------------------------------------------
    cfg.INPUT_FOLDER  = '';
    cfg.INPUT_FILE    = '';       % Chemin d'un fichier unique (mode "single")
    cfg.OUTPUT_FOLDER = '';
    cfg.RECURSIVE     = false;

    % 'single', 'batch', ou '' => fenêtre de dialogue
    cfg.PROCESS_MODE = '';

    cfg.UNIT_FACTOR = 1e6;
    cfg.UNIT_LABEL  = 'µm';

    cfg.PIXEL_SIZE_MM    = [];
    cfg.SAMPLE_WIDTH_MM  = 10.31;
    cfg.SAMPLE_HEIGHT_MM = 6.94;

    % --- Lissage bilatéral ----------------------------------------------
    % sigma_color   : préservation des intensités (typique 0.05 – 0.2)
    % sigma_spatial : rayon spatial en pixels      (typique 2 – 10)
    % win_size      : voisinage impair >= 2*sigma_spatial+1 (5,7,9,11,13)
    cfg.APPLY_SMOOTHING        = true;
    cfg.BILATERAL_SIGMA_COLOR  = 0.10;
    cfg.BILATERAL_SIGMA_SPATIAL= 5.0;
    cfg.BILATERAL_WIN_SIZE     = 11;
    cfg.SMOOTH_FACTOR          = 3;
    cfg.MAX_SMOOTHED_PIXELS    = 40e6;

    % --- Crop des bords -------------------------------------------------
    cfg.CROP_ENABLED = true;
    cfg.CROP_MODE    = 'auto';   % 'auto', 'fraction' ou 'pixels'

    % Paramètres du crop AUTO
    cfg.AUTO_CROP_SIGMA        = 2.0;
    cfg.AUTO_CROP_MARGIN       = 15;
    cfg.AUTO_CROP_MAX_FRACTION = 0.35;

    % Paramètres du crop FRACTION / PIXELS
    cfg.CROP_TOP    = 0.15;
    cfg.CROP_BOTTOM = 0.15;
    cfg.CROP_LEFT   = 0.03;
    cfg.CROP_RIGHT  = 0.03;

    % --- Suppression des artefacts linéaires verticaux ------------------
    cfg.ARTIFACT_REMOVAL     = true;
    cfg.ARTIFACT_FILE_FILTER = {'-AB-'};   % {} = tous ; cellstr

    cfg.ART_BG_WINDOW_MM  = 0.20;
    cfg.ART_K_SIGMA       = 3.5;
    cfg.ART_CLOSE_MM      = 0.30;
    cfg.ART_MIN_HEIGHT_MM = 0.30;
    cfg.ART_MAX_WIDTH_MM  = 0.08;
    cfg.ART_MIN_ASPECT    = 6.0;
    cfg.ART_MIN_FILL      = 0.20;
    cfg.ART_DILATE_MM     = 0.02;
    cfg.ART_V_MARGIN_MM   = 0.12;
    cfg.ART_SAVE_MASK     = false;

    % --- Déroulement cylindrique ----------------------------------------
    cfg.UNWRAP_ENABLED  = false;
    cfg.UNWRAP_CENTER_X = [];
    cfg.UNWRAP_CENTER_Y = [];
    cfg.UNWRAP_R_INNER  = [];
    cfg.UNWRAP_R_OUTER  = [];
    cfg.UNWRAP_N_ANGLES = 1440;
    cfg.UNWRAP_N_RADII  = 256;

    % --- Barre de couleur -----------------------------------------------
    cfg.VRANGE_PERCENTILE_LOW  = 1.0;
    cfg.VRANGE_PERCENTILE_HIGH = 99.5;

    cfg.VMIN = [];
    cfg.VMAX = [];

    cfg.XLIM = [];
    cfg.YLIM = [0.5, 2.7];

    % Recadre le tableau à la fenêtre XLIM/YLIM (mm)
    cfg.FILL_AXES_LIMITS = true;

    cfg.CMAP_ROUGHNESS = 'viridis';
    cfg.CMAP_ALIGNED   = 'viridis';

    cfg.COLORBAR_ORIENTATION = 'horizontal';

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

    [~, tiff_files, output_folder] = resolve_inputs(cfg);
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
%  Résolution des entrées
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
            input_folder = select_folder( ...
                'Sélectionner le dossier contenant les fichiers TIFF');
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
    if isequal(folder, 0), folder = ''; end
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
    mode = '';
    fig = uifigure('Name','Mode de traitement', ...
                   'Position',[500 400 460 200]);
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


% =========================================================================
%  Détection de type et chargement
% =========================================================================

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


% =========================================================================
%  Utilitaires statistiques robustes
% =========================================================================

function s = robust_sigma(values)
    values = values(:);
    values = values(isfinite(values));
    if isempty(values), s = 0; return; end
    med = median(values);
    mad = median(abs(values - med));
    if mad > 0
        s = 1.4826 * mad;
    else
        s = 0;
    end
end


% =========================================================================
%  Crop intelligent des bords
% =========================================================================

function [top, bottom, left, right] = detect_aberrant_edges(arr, cfg)
    top = 0; bottom = 0; left = 0; right = 0;

    finite = isfinite(arr);
    if ~any(finite(:)), return; end

    global_med   = median(arr(finite));
    global_sigma = robust_sigma(arr(finite));
    if global_sigma <= 0, return; end

    thr_hi = global_med + cfg.AUTO_CROP_SIGMA * global_sigma;
    thr_lo = global_med - cfg.AUTO_CROP_SIGMA * global_sigma;

    [n_rows, n_cols] = size(arr);

    row_meds = median(arr, 2, 'omitnan');
    col_meds = median(arr, 1, 'omitnan');

    top    = count_from_start(row_meds(:), thr_hi, thr_lo, cfg.AUTO_CROP_MAX_FRACTION);
    bottom = count_from_end(row_meds(:),   thr_hi, thr_lo, cfg.AUTO_CROP_MAX_FRACTION);
    left   = count_from_start(col_meds(:), thr_hi, thr_lo, cfg.AUTO_CROP_MAX_FRACTION);
    right  = count_from_end(col_meds(:),   thr_hi, thr_lo, cfg.AUTO_CROP_MAX_FRACTION);

    top    = top    + cfg.AUTO_CROP_MARGIN;
    bottom = bottom + cfg.AUTO_CROP_MARGIN;
    left   = left   + cfg.AUTO_CROP_MARGIN;
    right  = right  + cfg.AUTO_CROP_MARGIN;

    top    = min(top,    floor(n_rows/3));
    bottom = min(bottom, floor(n_rows/3));
    left   = min(left,   floor(n_cols/3));
    right  = min(right,  floor(n_cols/3));
end


function n = count_from_start(meds, thr_hi, thr_lo, max_frac)
    max_n = floor(numel(meds) * max_frac);
    n = 0;
    for k = 1:max_n
        v = meds(k);
        if ~isfinite(v)
            n = n + 1; continue;
        end
        if v > thr_hi || v < thr_lo
            n = n + 1;
        else
            break;
        end
    end
end


function n = count_from_end(meds, thr_hi, thr_lo, max_frac)
    max_n = floor(numel(meds) * max_frac);
    n = 0;
    for k = 1:max_n
        v = meds(end - k + 1);
        if ~isfinite(v)
            n = n + 1; continue;
        end
        if v > thr_hi || v < thr_lo
            n = n + 1;
        else
            break;
        end
    end
end


function arr = crop_borders(arr, cfg)
    if ~cfg.CROP_ENABLED, return; end
    [n_rows, n_cols] = size(arr);

    switch cfg.CROP_MODE
        case 'auto'
            [top, bottom, left, right] = detect_aberrant_edges(arr, cfg);
        case 'fraction'
            top    = round(cfg.CROP_TOP    * n_rows);
            bottom = round(cfg.CROP_BOTTOM * n_rows);
            left   = round(cfg.CROP_LEFT   * n_cols);
            right  = round(cfg.CROP_RIGHT  * n_cols);
        otherwise  % 'pixels'
            top    = round(cfg.CROP_TOP);
            bottom = round(cfg.CROP_BOTTOM);
            left   = round(cfg.CROP_LEFT);
            right  = round(cfg.CROP_RIGHT);
    end

    r0 = top + 1;         r1 = n_rows - bottom;
    c0 = left + 1;        c1 = n_cols - right;

    if r1 <= r0 || c1 <= c0
        fprintf('  [!] Crop trop agressif, ignoré.\n');
        return;
    end

    cropped = arr(r0:r1, c0:c1);
    fprintf('  [i] Crop (%s) : %dx%d -> %dx%d (t=%d, b=%d, l=%d, r=%d)\n', ...
        cfg.CROP_MODE, n_rows, n_cols, size(cropped,1), size(cropped,2), ...
        top, bottom, left, right);
    arr = cropped;
end


% =========================================================================
%  Suppression des artefacts verticaux
% =========================================================================

function n = odd_(n)
    n = int32(max(3, round(n)));
    if mod(n, 2) == 0, n = n + 1; end
    n = double(n);
end


function mask = detect_vertical_artifacts(arr, cfg)
    [n_rows, n_cols] = size(arr);
    px = cfg.SAMPLE_WIDTH_MM  / n_cols;
    pz = cfg.SAMPLE_HEIGHT_MM / n_rows;

    med_all = median(arr(isfinite(arr)));
    if isempty(med_all), med_all = 0; end
    filled = arr;
    filled(~isfinite(filled)) = med_all;

    % Fond local (médian horizontal)
    win = odd_(cfg.ART_BG_WINDOW_MM / px);
    bg  = medfilt2(filled, [1 win], 'symmetric');
    res = filled - bg;
    sigma = robust_sigma(res(:));
    if sigma <= 0
        mask = false(size(arr));
        return;
    end
    strong = res < -cfg.ART_K_SIGMA * sigma;

    max_w      = max(2, round(cfg.ART_MAX_WIDTH_MM / px));
    close_len  = odd_(cfg.ART_CLOSE_MM / pz);
    min_h      = cfg.ART_MIN_HEIGHT_MM / pz;

    mask = false(size(arr));

    % --- A) Détecteur par forme ----------------------------------------
    se_h3   = strel('arbitrary', ones(1,3));
    se_vN   = strel('arbitrary', ones(close_len, 1));
    se_hW   = strel('arbitrary', ones(1, max_w+1));

    sd   = imdilate(strong, se_h3);
    cand = imclose(sd, se_vN);
    wide = imopen(cand, se_hW);
    wide = imdilate(wide, se_h3);
    cand = cand & ~wide;

    [lab, n] = bwlabel(cand);
    stats = regionprops(lab, 'BoundingBox', 'PixelIdxList');
    for i = 1:n
        bb = stats(i).BoundingBox;   % [x y w h]
        h = bb(4); w = bb(3);
        if h < min_h || h / max(w, 1) < cfg.ART_MIN_ASPECT
            continue;
        end
        obj = false(size(arr));
        obj(stats(i).PixelIdxList) = true;
        fill_ratio = sum(strong(stats(i).PixelIdxList)) / max(numel(stats(i).PixelIdxList),1);
        if fill_ratio < cfg.ART_MIN_FILL
            continue;
        end
        mask = mask | obj;
    end

    % --- B) Détecteur par profil de colonne ----------------------------
    col_sum  = sum(strong, 1);
    cnt      = conv(col_sum(:), ones(3,1)/3, 'same');
    base     = medfilt2(cnt, [odd_(0.3/px) 1], 'symmetric');
    excess   = cnt - base;
    bin_exc  = excess >= 0.5 * min_h;

    [clab, cn] = bwlabel(bin_exc(:).');
    for i = 1:cn
        cols = find(clab == i);
        if isempty(cols), continue; end
        ex = excess(cols);
        keep = find(ex >= 0.5 * max(ex));
        if isempty(keep), continue; end
        c0 = max(cols(keep(1))   - 1, 1);
        c1 = min(cols(keep(end)) + 2, n_cols);
        rows = any(strong(:, c0:c1), 2);
        rows = imclose(rows(:).', strel('arbitrary', ones(1, close_len)));
        [rlab, rn] = bwlabel(rows);
        for j = 1:rn
            rlist = find(rlab == j);
            if numel(rlist) >= min_h
                mask(rlist, c0:c1) = true;
            end
        end
    end

    % --- Dilatation finale ---------------------------------------------
    dx = max(1, round(cfg.ART_DILATE_MM / px));
    dz = max(0, round(cfg.ART_V_MARGIN_MM / pz));
    if dx > 0 || dz > 0
        se = strel('arbitrary', ones(2*dz+1, 2*dx+1));
        mask = imdilate(mask, se);
    end
end


function out = inpaint_rows(arr, mask)
    out = arr;
    n_cols = size(arr, 2);
    xs = 1:n_cols;
    rows = find(any(mask, 2));
    for k = 1:numel(rows)
        r = rows(k);
        bad = mask(r, :) | ~isfinite(arr(r, :));
        good = ~bad;
        if sum(good) < 2, continue; end
        out(r, bad) = interp1(xs(good), arr(r, good), xs(bad), 'linear', 'extrap');
    end
end


function arr = remove_artifacts(arr, base_name, save_mask_path, cfg)
    if ~cfg.ARTIFACT_REMOVAL, return; end
    if ~isempty(cfg.ARTIFACT_FILE_FILTER)
        matched = false;
        for k = 1:numel(cfg.ARTIFACT_FILE_FILTER)
            if contains(base_name, cfg.ARTIFACT_FILE_FILTER{k})
                matched = true; break;
            end
        end
        if ~matched, return; end
    end

    mask = detect_vertical_artifacts(arr, cfg);
    fprintf('  [i] Artefacts : %d px masqués (%.2f %%)\n', ...
        sum(mask(:)), 100 * mean(mask(:)));

    if ~isempty(save_mask_path) && cfg.ART_SAVE_MASK
        imwrite(uint8(mask) * 255, save_mask_path);
    end
    arr = inpaint_rows(arr, mask);
end


% =========================================================================
%  Déroulement cylindrique
% =========================================================================

function params = estimate_cylinder_params(arr)
    mask = isfinite(arr) & (arr ~= 0);
    if sum(mask(:)) < 100
        params = [];
        return;
    end
    [ys, xs] = find(mask);
    cx = mean(xs);
    cy = mean(ys);
    r  = sqrt((xs - cx).^2 + (ys - cy).^2);
    r_inner = prctile(r, 5);
    r_outer = prctile(r, 95);
    params = [cx, cy, r_inner, r_outer];
end


function [sampled, extent] = unwrap_cylindrical(arr, cx, cy, r_inner, r_outer, ...
                                                 n_angles, n_radii)
    angles = linspace(0, 2*pi, n_angles+1);
    angles(end) = [];
    radii = linspace(r_inner, r_outer, n_radii);

    [A, R] = meshgrid(angles, radii);      % size n_radii x n_angles
    X = cx + R .* cos(A);
    Y = cy + R .* sin(A);

    arr_f = arr;
    arr_f(~isfinite(arr_f)) = 0;

    sampled = interp2(arr_f, X, Y, 'cubic', 0);
    sampled = sampled.';                    % n_angles x n_radii

    extent = [0, 360, r_outer, r_inner];
end


function [arr, extent_override] = maybe_unwrap(arr, path, cfg)
    extent_override = [];
    if ~cfg.UNWRAP_ENABLED, return; end

    [n_rows, n_cols] = size(arr);
    cx = cfg.UNWRAP_CENTER_X;
    cy = cfg.UNWRAP_CENTER_Y;
    if isempty(cx), cx = n_cols / 2; end
    if isempty(cy), cy = n_rows / 2; end

    r_in  = cfg.UNWRAP_R_INNER;
    r_out = cfg.UNWRAP_R_OUTER;

    if isempty(r_in) || isempty(r_out)
        params = estimate_cylinder_params(arr);
        if isempty(params)
            [~, n, e] = fileparts(path);
            fprintf('  [!] UNWRAP activé mais impossible d''estimer le cylindre pour %s%s -> ignoré.\n', n, e);
            return;
        end
        cx_auto = params(1); cy_auto = params(2);
        r_in_auto = params(3); r_out_auto = params(4);
        if isempty(cfg.UNWRAP_CENTER_X), cx = cx_auto; end
        if isempty(cfg.UNWRAP_CENTER_Y), cy = cy_auto; end
        if isempty(r_in),  r_in  = r_in_auto;  end
        if isempty(r_out), r_out = r_out_auto; end
        fprintf('  [i] Paramètres cylindre estimés : centre=(%.0f,%.0f), R∈[%.0f,%.0f] px\n', ...
            cx, cy, r_in, r_out);
    end

    [arr, extent_override] = unwrap_cylindrical(arr, cx, cy, r_in, r_out, ...
        cfg.UNWRAP_N_ANGLES, cfg.UNWRAP_N_RADII);
end


% =========================================================================
%  Lissage bilatéral + upsampling
% =========================================================================

function arr = smooth_upsample(arr, cfg)
    if ~cfg.APPLY_SMOOTHING, return; end

    if any(isnan(arr(:)))
        mean_val = mean(arr(:), 'omitnan');
        arr(isnan(arr)) = mean_val;
    end

    vmin = min(arr(:));
    vmax = max(arr(:));
    if vmax - vmin < 1e-12, return; end

    arr_norm = (arr - vmin) / (vmax - vmin);

    % --- Filtre bilatéral (imbilatfilt, R2018a+) -----------------------
    try
        arr_filt = imbilatfilt(arr_norm, ...
            'DegreeOfSmoothing', cfg.BILATERAL_SIGMA_COLOR, ...
            'SpatialSigma',     cfg.BILATERAL_SIGMA_SPATIAL, ...
            'NeighborhoodSize', cfg.BILATERAL_WIN_SIZE);
    catch
        % Fallback : filtre gaussien classique
        fprintf('  [!] imbilatfilt indisponible -> filtre gaussien utilisé.\n');
        arr_filt = imgaussfilt(arr_norm, cfg.BILATERAL_SIGMA_SPATIAL);
    end

    arr_filt = arr_filt * (vmax - vmin) + vmin;
    arr_filt = min(max(arr_filt, vmin), vmax);

    % --- Upsampling final ----------------------------------------------
    [n_rows, n_cols] = size(arr_filt);
    factor = cfg.SMOOTH_FACTOR;
    total_pixels = (n_rows * factor) * (n_cols * factor);
    if total_pixels > cfg.MAX_SMOOTHED_PIXELS
        max_factor_sq = cfg.MAX_SMOOTHED_PIXELS / (n_rows * n_cols);
        factor = max(1.0, sqrt(max_factor_sq));
        fprintf('  [i] Facteur d''upsampling réduit à %.2f.\n', factor);
    end

    if factor > 1
        new_size = [round(n_rows*factor), round(n_cols*factor)];
        arr_filt = imresize(arr_filt, new_size, 'bilinear');
    end

    arr = arr_filt;
end


% =========================================================================
%  Taille de pixel / extent / crop fenêtre
% =========================================================================

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

            if ~pixels_per_unit || pixels_per_unit <= 0, return; end

            unit_code = 2;
            if isfield(info, 'ResolutionUnit'), unit_code = info.ResolutionUnit; end

            if ischar(unit_code) || isstring(unit_code)
                switch lower(char(unit_code))
                    case 'inch',       mm_per_unit = 25.4;
                    case 'centimeter', mm_per_unit = 10.0;
                    otherwise,         return;
                end
            else
                switch unit_code
                    case 2, mm_per_unit = 25.4;
                    case 3, mm_per_unit = 10.0;
                    otherwise, return;
                end
            end

            pixel_size_mm = mm_per_unit / pixels_per_unit;
        end
    catch
        pixel_size_mm = [];
    end
end


function [extent, is_mm] = resolve_extent(path, arr, extent_override, cfg)
    [n_rows, n_cols] = size(arr);

    if ~isempty(extent_override)
        extent = extent_override;
        is_mm = false;
        return;
    end

    if ~isempty(cfg.PIXEL_SIZE_MM)
        ps = cfg.PIXEL_SIZE_MM;
    else
        ps = get_pixel_size_from_metadata(path);
    end

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
    fprintf('  [!] Taille de pixel introuvable pour %s%s -> axes en pixels.\n', name, ext);
    extent = [0, n_cols, n_rows, 0];
    is_mm = false;
end


function figsize = compute_figsize(extent, cfg)
    x_span = abs(extent(2) - extent(1));
    y_span = abs(extent(3) - extent(4));
    if x_span == 0 || y_span == 0
        figsize = [cfg.TARGET_LONG_SIDE_INCHES, ...
                   cfg.TARGET_LONG_SIDE_INCHES * 3 / 4];
        return;
    end

    ratio = x_span / y_span;

    if ratio >= 1
        width  = cfg.TARGET_LONG_SIDE_INCHES;
        height = width / ratio;
        if height < cfg.MIN_SHORT_SIDE_INCHES
            height = cfg.MIN_SHORT_SIDE_INCHES;
            width  = height * ratio;
        end
    else
        height = cfg.TARGET_LONG_SIDE_INCHES;
        width  = height * ratio;
        if width < cfg.MIN_SHORT_SIDE_INCHES
            width  = cfg.MIN_SHORT_SIDE_INCHES;
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
    finite = arr(isfinite(arr));
    if isempty(finite), vmin = 0; vmax = 1; return; end

    if ~isempty(cfg.VMIN) && ~isempty(cfg.VMAX)
        vmin = cfg.VMIN; vmax = cfg.VMAX; return;
    end

    q1  = prctile(finite, 25);
    q3  = prctile(finite, 75);
    iqr = q3 - q1;

    FACTOR = 3.0;
    vmin_auto = q1 - FACTOR * iqr;
    vmax_auto = q3 + FACTOR * iqr;

    vmin_auto = max(vmin_auto, min(finite));
    vmax_auto = min(vmax_auto, max(finite));

    if ~isempty(cfg.VMIN), vmin = cfg.VMIN; else, vmin = vmin_auto; end
    if ~isempty(cfg.VMAX), vmax = cfg.VMAX; else, vmax = vmax_auto; end

    fprintf('  [debug] min=%.2f  Q1=%.2f  med=%.2f  Q3=%.2f  max=%.2f  -> vmin=%.2f  vmax=%.2f\n', ...
        min(finite), q1, median(finite), q3, max(finite), vmin, vmax);

    if vmin >= vmax, vmax = vmin + 1.0; end
end


function [arr, extent] = crop_to_window(arr, extent, cfg)
    [n_rows, n_cols] = size(arr);
    x_left = extent(1); x_right = extent(2);
    y_bot  = extent(3); y_top   = extent(4);
    dx = (x_right - x_left) / n_cols;
    dz = (y_bot   - y_top)  / n_rows;

    r0 = 1; r1 = n_rows; c0 = 1; c1 = n_cols;
    new_x0 = x_left; new_x1 = x_right; new_y0 = y_top; new_y1 = y_bot;

    if ~isempty(cfg.YLIM) && dz > 0
        z0 = max(min(cfg.YLIM), y_top);
        z1 = min(max(cfg.YLIM), y_bot);
        if z1 > z0
            r0 = round((z0 - y_top) / dz) + 1;
            r1 = round((z1 - y_top) / dz);
            new_y0 = min(cfg.YLIM);
            new_y1 = max(cfg.YLIM);
        end
    end
    if ~isempty(cfg.XLIM) && dx > 0
        x0 = max(min(cfg.XLIM), x_left);
        x1 = min(max(cfg.XLIM), x_right);
        if x1 > x0
            c0 = round((x0 - x_left) / dx) + 1;
            c1 = round((x1 - x_left) / dx);
            new_x0 = min(cfg.XLIM);
            new_x1 = max(cfg.XLIM);
        end
    end

    r0 = max(r0, 1); r1 = min(r1, n_rows);
    c0 = max(c0, 1); c1 = min(c1, n_cols);

    if (r1 - r0) < 1 || (c1 - c0) < 1
        return;
    end

    fprintf('  [i] Fenêtre : lignes %d:%d / %d, colonnes %d:%d / %d\n', ...
        r0, r1, n_rows, c0, c1, n_cols);

    arr    = arr(r0:r1, c0:c1);
    extent = [new_x0, new_x1, new_y1, new_y0];
end


% =========================================================================
%  Rendu + export
% =========================================================================

function out_path = plot_tiff_to_png(tiff_path, output_folder, cfg)
    [~, base_name, ext] = fileparts(tiff_path);
    filename  = [base_name ext];
    file_type = detect_file_type(filename);

    if ~exist(output_folder, 'dir'), mkdir(output_folder); end

    % --- Chargement ---
    arr = load_tiff(tiff_path, cfg);

    % --- Crop des bords aberrants ---
    arr = crop_borders(arr, cfg);

    % --- Suppression des artefacts verticaux ---
    mask_path = fullfile(output_folder, [base_name '_mask.png']);
    arr = remove_artifacts(arr, base_name, mask_path, cfg);

    % --- Déroulement cylindrique éventuel ---
    [arr, extent_override] = maybe_unwrap(arr, tiff_path, cfg);

    % --- Extent + recadrage fenêtre ---
    [extent, is_mm] = resolve_extent(tiff_path, arr, extent_override, cfg);

    if cfg.FILL_AXES_LIMITS && isempty(extent_override)
        [arr, extent] = crop_to_window(arr, extent, cfg);
    end

    % --- Plage de couleurs + lissage ---
    [vmin, vmax] = get_vrange(arr, cfg);
    arr_plot = smooth_upsample(arr, cfg);

    figsize = compute_figsize(extent, cfg);
    effective_dpi = get_effective_dpi(figsize, cfg);

    fig = figure('Visible','off', 'Units','inches', ...
        'Position',[1 1 figsize(1) figsize(2)], ...
        'PaperPositionMode','auto', 'Color','w');
    ax = axes('Parent', fig); %#ok<LAXES>

    switch file_type
        case 'roughness'
            if vmin < 0 && vmax > 0
                max_abs = max(abs(vmin), abs(vmax));
                imagesc(ax, arr_plot, [-max_abs, max_abs]);
            else
                imagesc(ax, arr_plot, [vmin vmax]);
            end
            colormap(ax, cfg.CMAP_ROUGHNESS);
            cbar_label = sprintf('Rugosité (%s)', cfg.UNIT_LABEL);
            title_str  = sprintf('%s - Surface roughness map (vue de dessus)', base_name);

        case 'aligned'
            imagesc(ax, arr_plot, [vmin vmax]);
            colormap(ax, cfg.CMAP_ALIGNED);
            cbar_label = sprintf('Hauteur (%s)', cfg.UNIT_LABEL);
            title_str  = sprintf('%s - Aligned surface map (vue de dessus)', base_name);

        otherwise
            imagesc(ax, arr_plot, [vmin vmax]);
            colormap(ax, 'jet');
            cbar_label = sprintf('Valeur (%s)', cfg.UNIT_LABEL);
            title_str  = sprintf('%s', base_name);
    end

    axis(ax, 'image');
    set(ax, 'YDir', 'reverse');

    xlim(ax, [extent(1), extent(2)]);
    ylim(ax, [extent(3), extent(4)]);

    % --- axes ---
    if ~isempty(extent_override)
        xlabel(ax, 'Angle (°)',   'FontSize', cfg.AXIS_LABEL_FONTSIZE);
        ylabel(ax, 'Rayon (px)',  'FontSize', cfg.AXIS_LABEL_FONTSIZE);
    elseif is_mm
        xlabel(ax, 'Y (mm)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
        ylabel(ax, 'Z (mm)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
    else
        xlabel(ax, 'Y (px)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
        ylabel(ax, 'Z (px)', 'FontSize', cfg.AXIS_LABEL_FONTSIZE);
    end

    title(ax, title_str, 'FontSize', cfg.TITLE_FONTSIZE, 'FontWeight','bold');
    set(ax, 'FontSize', cfg.TICK_FONTSIZE);

    % --- Limites d'axes bornées à l'étendue réelle ---
    if isempty(extent_override)
        x_lo = min(extent(1:2)); x_hi = max(extent(1:2));
        y_lo = min(extent(3:4)); y_hi = max(extent(3:4));
        if ~isempty(cfg.XLIM)
            xlim(ax, [max(min(cfg.XLIM), x_lo), min(max(cfg.XLIM), x_hi)]);
        end
        if ~isempty(cfg.YLIM)
            ylim(ax, [min(max(cfg.YLIM), y_hi), max(min(cfg.YLIM), y_lo)]);
        end
    end

    % --- colorbar ---
    cb = colorbar(ax, 'Location', cfg.COLORBAR_ORIENTATION);
    cb.Label.String   = cbar_label;
    cb.Label.FontSize = cfg.CBAR_LABEL_FONTSIZE;
    cb.FontSize       = cfg.CBAR_TICK_FONTSIZE;

    out_path = fullfile(output_folder, [base_name '.png']);
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
