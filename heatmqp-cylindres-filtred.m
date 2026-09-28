function tiff_to_png()
% =========================================================================
%  tiff_to_png.m
% -------------------------------------------------------------------------
%  Lit tous les fichiers .tif / .tiff d'un dossier, les visualise (heatmap)
%  selon leur type detecte a partir du nom de fichier, puis exporte en PNG.
%
%  Pipeline : crop auto des bords -> suppression des artefacts verticaux
%             (+ interpolation) -> fenetre XLIM/YLIM -> lissage bilateral
%             -> affichage.
%
%  Les donnees brutes sont en METRES -> converties en um a l'affichage.
%
%  Prerequis : Image Processing Toolbox (imdilate, imclose, imopen, bwlabel,
%              regionprops, imbilatfilt [R2018a+], imresize)
%              exportgraphics [R2020a+] (sinon repli sur print)
% =========================================================================

C = get_config();
[in_dir, out_dir] = resolve_folders(C);

fprintf('Lecture des fichiers .tif/.tiff dans : %s\n', in_dir);
files = find_tiff_files(in_dir, C.RECURSIVE);
if isempty(files)
    fprintf('Aucun fichier .tif/.tiff trouve.\n');
    return;
end
fprintf('%d fichier(s) trouve(s).\n\n', numel(files));

n_ok = 0; n_fail = 0;
for k = 1:numel(files)
    [~, nm, ext] = fileparts(files{k});
    fprintf('--- Traitement de %s%s ---\n', nm, ext);
    try
        out_path = plot_tiff_to_png(files{k}, out_dir, C);
        fprintf('[OK] %s%s  (type=%s)  -> %s\n\n', nm, ext, ...
                detect_file_type([nm ext]), out_path);
        n_ok = n_ok + 1;
    catch ME
        fprintf('[ERREUR] %s%s : %s\n', nm, ext, ME.message);
        disp(getReport(ME));
        n_fail = n_fail + 1;
    end
end
fprintf('Termine : %d succes, %d echec(s).\n', n_ok, n_fail);
fprintf('PNG exportes dans : %s\n', out_dir);
end


% =========================================================================
%                                  CONFIG
%  ([] equivaut a None en Python)
% =========================================================================
function C = get_config()

C.INPUT_FOLDER  = '';
C.OUTPUT_FOLDER = '';
C.RECURSIVE     = false;

C.UNIT_FACTOR = 1e6;
C.UNIT_LABEL  = '\mum';

C.PIXEL_SIZE_MM    = [];
C.SAMPLE_WIDTH_MM  = 10.31;
C.SAMPLE_HEIGHT_MM = 6.94;

% --- Lissage bilateral ---------------------------------------------------
%  SIGMA_COLOR   : preservation des intensites (echelle normalisee 0-1)
%  SIGMA_SPATIAL : taille spatiale du lissage (pixels)
%  WIN_SIZE      : voisinage (impair)
%  SMOOTH_FACTOR : facteur d'upsampling final
C.APPLY_SMOOTHING          = true;
C.BILATERAL_SIGMA_COLOR    = 0.10;
C.BILATERAL_SIGMA_SPATIAL  = 5.0;
C.BILATERAL_WIN_SIZE       = 11;
C.SMOOTH_FACTOR            = 3;
C.MAX_SMOOTHED_PIXELS      = 40e6;

% --- Crop des bords ------------------------------------------------------
%  'auto' | 'fraction' | 'pixels'
C.CROP_ENABLED = true;
C.CROP_MODE    = 'auto';

C.AUTO_CROP_SIGMA        = 2.0;
C.AUTO_CROP_MARGIN       = 15;
C.AUTO_CROP_MAX_FRACTION = 0.35;

C.CROP_TOP    = 0.15;
C.CROP_BOTTOM = 0.15;
C.CROP_LEFT   = 0.03;
C.CROP_RIGHT  = 0.03;

% --- Suppression des artefacts lineaires verticaux ----------------------
C.ARTIFACT_REMOVAL      = true;
C.ARTIFACT_FILE_FILTER  = {'-AB-'};   % {} => tous les fichiers
C.ART_BG_WINDOW_MM      = 0.20;
C.ART_K_SIGMA           = 3.5;
C.ART_CLOSE_MM          = 0.30;
C.ART_MIN_HEIGHT_MM     = 0.30;
C.ART_MAX_WIDTH_MM      = 0.08;
C.ART_MIN_ASPECT        = 6.0;
C.ART_MIN_FILL          = 0.20;
C.ART_DILATE_MM         = 0.02;
C.ART_V_MARGIN_MM       = 0.12;
C.ART_SAVE_MASK         = false;

% --- Deroulement cylindrique --------------------------------------------
C.UNWRAP_ENABLED   = false;
C.UNWRAP_CENTER_X  = [];
C.UNWRAP_CENTER_Y  = [];
C.UNWRAP_R_INNER   = [];
C.UNWRAP_R_OUTER   = [];
C.UNWRAP_N_ANGLES  = 1440;
C.UNWRAP_N_RADII   = 256;

% --- Barre de couleur ----------------------------------------------------
C.VMIN = [];
C.VMAX = [];

C.XLIM = [];
C.YLIM = [0.5 2.7];

% true => le tableau est decoupe a la fenetre XLIM/YLIM. Si les donnees sont
% plus courtes que la fenetre, elles sont etirees pour la remplir (pas de blanc).
C.FILL_AXES_LIMITS = true;

C.CMAP_ROUGHNESS = 'jet';
C.CMAP_ALIGNED   = 'jet';
C.COLORBAR_ORIENTATION = 'horizontal';   % 'horizontal' | 'vertical'

C.DPI = 200;
C.TARGET_LONG_SIDE_INCHES = 16.0;
C.MIN_SHORT_SIDE_INCHES   = 9.0;
C.MAX_PIXELS_DIM          = 20000;

C.TITLE_FONTSIZE      = 20;
C.AXIS_LABEL_FONTSIZE = 16;
C.TICK_FONTSIZE       = 14;
C.CBAR_LABEL_FONTSIZE = 16;
C.CBAR_TICK_FONTSIZE  = 14;
end


% =========================================================================
%                              ENTREES / SORTIES
% =========================================================================
function [in_dir, out_dir] = resolve_folders(C)
in_dir = C.INPUT_FOLDER;
out_dir = C.OUTPUT_FOLDER;
if isempty(in_dir)
    in_dir = uigetdir(pwd, 'Selectionner le dossier contenant les fichiers TIFF');
    if isequal(in_dir, 0), error('Aucun dossier d''entree selectionne. Arret.'); end
end
if isempty(out_dir)
    out_dir = uigetdir(pwd, 'Selectionner le dossier de destination des PNG');
    if isequal(out_dir, 0), error('Aucun dossier de sortie selectionne. Arret.'); end
end
end

function files = find_tiff_files(in_dir, recursive)
if recursive
    d = dir(fullfile(in_dir, '**', '*.tif*'));
else
    d = dir(fullfile(in_dir, '*.tif*'));
end
d = d(~[d.isdir]);
keep = ~cellfun(@isempty, regexpi({d.name}, '\.tiff?$', 'once'));
d = d(keep);
files = sort(fullfile({d.folder}, {d.name}));
end

function t = detect_file_type(filename)
n = lower(filename);
if contains(n, 'roughness') || contains(n, 'rugosit')
    t = 'roughness';
elseif contains(n, 'aligned')
    t = 'aligned';
else
    t = 'unknown';
end
end

function arr = load_tiff(path, C)
arr = double(imread(path));
if ndims(arr) == 3, arr = arr(:, :, 1); end
arr = arr * C.UNIT_FACTOR;
end


% =========================================================================
%                          OUTILS STATISTIQUES
% =========================================================================
function s = robust_sigma(v)
% Ecart-type robuste via MAD
v = v(:);
med = median(v);
mad_ = median(abs(v - med));
if mad_ > 0, s = 1.4826 * mad_; else, s = 0; end
end

function q = simple_quantile(x, p)
x = sort(x(:));
n = numel(x);
pos = (n - 1) * p + 1;
lo = floor(pos); hi = ceil(pos);
q = x(lo) + (pos - lo) * (x(hi) - x(lo));
end

function n = odd_(n)
n = max(3, round(n));
if mod(n, 2) == 0, n = n + 1; end
end


% =========================================================================
%                       CROP INTELLIGENT DES BORDS
% =========================================================================
function [top, bottom, left, right] = detect_aberrant_edges(arr, C)
top = 0; bottom = 0; left = 0; right = 0;
fin = isfinite(arr);
if ~any(fin(:)), return; end

gmed = median(arr(fin));
gsig = robust_sigma(arr(fin));
if gsig <= 0, return; end
thr_hi = gmed + C.AUTO_CROP_SIGMA * gsig;
thr_lo = gmed - C.AUTO_CROP_SIGMA * gsig;

[nr, nc] = size(arr);
row_meds = median(arr, 2, 'omitnan');
col_meds = median(arr, 1, 'omitnan').';

f = C.AUTO_CROP_MAX_FRACTION;
top    = count_edge(row_meds,        thr_hi, thr_lo, f);
bottom = count_edge(flipud(row_meds), thr_hi, thr_lo, f);
left   = count_edge(col_meds,        thr_hi, thr_lo, f);
right  = count_edge(flipud(col_meds), thr_hi, thr_lo, f);

m = C.AUTO_CROP_MARGIN;
top = min(top + m, floor(nr / 3));
bottom = min(bottom + m, floor(nr / 3));
left = min(left + m, floor(nc / 3));
right = min(right + m, floor(nc / 3));
end

function n = count_edge(meds, thr_hi, thr_lo, max_frac)
max_n = floor(numel(meds) * max_frac);
n = 0;
for i = 1:max_n
    v = meds(i);
    if ~isfinite(v)
        n = n + 1;
    elseif v > thr_hi || v < thr_lo
        n = n + 1;
    else
        break;
    end
end
end

function arr = crop_borders(arr, C)
if ~C.CROP_ENABLED, return; end
[nr, nc] = size(arr);
switch C.CROP_MODE
    case 'auto'
        [t, b, l, r] = detect_aberrant_edges(arr, C);
    case 'fraction'
        t = round(C.CROP_TOP * nr);    b = round(C.CROP_BOTTOM * nr);
        l = round(C.CROP_LEFT * nc);   r = round(C.CROP_RIGHT * nc);
    otherwise   % 'pixels'
        t = round(C.CROP_TOP);  b = round(C.CROP_BOTTOM);
        l = round(C.CROP_LEFT); r = round(C.CROP_RIGHT);
end
r1 = nr - b; c1 = nc - r;
if r1 <= t || c1 <= l
    fprintf('  [!] Crop trop agressif, ignore.\n');
    return;
end
old = size(arr);
arr = arr(t+1:r1, l+1:c1);
fprintf('  [i] Crop (%s) : %dx%d -> %dx%d (t=%d, b=%d, l=%d, r=%d)\n', ...
        C.CROP_MODE, old(1), old(2), size(arr, 1), size(arr, 2), t, b, l, r);
end


% =========================================================================
%                  SUPPRESSION DES ARTEFACTS VERTICAUX
% =========================================================================
function mask = detect_vertical_artifacts(arr, C)
% Deux detecteurs combines :
%   A) par forme : objets fins et allonges (apres retrait des parties larges)
%   B) par profil de colonne : exces de pixels tres negatifs sur une colonne
%      (rattrape les traces collees a un pore/blob)
[nr, nc] = size(arr);
px = C.SAMPLE_WIDTH_MM / nc;
pz = C.SAMPLE_HEIGHT_MM / nr;

filled = arr;
filled(~isfinite(filled)) = median(arr(isfinite(arr)));

% fond local : median horizontal, puis residu
win = odd_(C.ART_BG_WINDOW_MM / px);
bg = movmedian(filled, win, 2);
res = filled - bg;
sigma = robust_sigma(res(:));
mask = false(nr, nc);
if sigma <= 0, return; end
strong = res < -C.ART_K_SIGMA * sigma;

max_w     = max(2, round(C.ART_MAX_WIDTH_MM / px));
close_len = odd_(C.ART_CLOSE_MM / pz);
min_h     = C.ART_MIN_HEIGHT_MM / pz;

% ---- A) detecteur par forme ----
sd   = imdilate(strong, ones(1, 3));
cand = imclose(sd, ones(close_len, 1));
wide = imopen(cand, ones(1, max_w + 1));
wide = imdilate(wide, ones(1, 3));
cand = cand & ~wide;

lab = bwlabel(cand, 4);
stats = regionprops(lab, 'BoundingBox', 'PixelIdxList');
for i = 1:numel(stats)
    bb = stats(i).BoundingBox;
    w = bb(3); h = bb(4);
    if h < min_h || h / max(w, 1) < C.ART_MIN_ASPECT, continue; end
    idx = stats(i).PixelIdxList;
    fill = nnz(strong(idx)) / numel(idx);
    if fill < C.ART_MIN_FILL, continue; end
    mask(idx) = true;
end

% ---- B) detecteur par profil de colonne ----
cnt0 = sum(strong, 1);
cnt = movmean(cnt0, 3, 'Endpoints', 'shrink') * 3;
base = movmedian(cnt, odd_(0.3 / px));
excess = cnt - base;
clab = bwlabel(excess >= 0.5 * min_h, 4);
for j = 1:max(clab)
    idx = find(clab == j);
    ex = excess(idx);
    keep = find(ex >= 0.5 * max(ex));
    c0 = max(idx(1) + keep(1) - 1 - 1, 1);
    c1 = min(idx(1) + keep(end) - 1 + 1, nc);
    rows = any(strong(:, c0:c1), 2);
    rows = imclose(rows, ones(close_len, 1));
    rl = bwlabel(rows, 4);
    for k = 1:max(rl)
        r = find(rl == k);
        if numel(r) >= min_h
            mask(r(1):r(end), c0:c1) = true;
        end
    end
end

% ---- elargit pour couvrir les bords et les bouts pales ----
dx = max(1, round(C.ART_DILATE_MM / px));
dz = max(0, round(C.ART_V_MARGIN_MM / pz));
mask = imdilate(mask, ones(2 * dz + 1, 2 * dx + 1));
end

function out = inpaint_rows(arr, mask)
% Interpolation lineaire horizontale des pixels masques, ligne par ligne
out = arr;
xs = 1:size(arr, 2);
rows = find(any(mask, 2)).';
for r = rows
    bad = mask(r, :) | ~isfinite(arr(r, :));
    good = ~bad;
    if nnz(good) < 2, continue; end
    v = interp1(xs(good), arr(r, good), xs(bad), 'linear');
    nanv = isnan(v);                       % hors bornes -> valeur la plus proche
    if any(nanv)
        xb = xs(bad);
        v(nanv) = interp1(xs(good), arr(r, good), xb(nanv), 'nearest', 'extrap');
    end
    out(r, bad) = v;
end
end

function arr = remove_artifacts(arr, base_name, mask_path, C)
if ~C.ARTIFACT_REMOVAL, return; end
if ~isempty(C.ARTIFACT_FILE_FILTER) && ~any(contains(base_name, C.ARTIFACT_FILE_FILTER))
    return;
end
mask = detect_vertical_artifacts(arr, C);
fprintf('  [i] Artefacts : %d px masques (%.2f %%)\n', nnz(mask), 100 * mean(mask(:)));
if C.ART_SAVE_MASK
    imwrite(mask, mask_path);
end
arr = inpaint_rows(arr, mask);
end


% =========================================================================
%                       DEROULEMENT CYLINDRIQUE
% =========================================================================
function [arr_u, extent_px] = maybe_unwrap(arr, C)
arr_u = arr; extent_px = [];
if ~C.UNWRAP_ENABLED, return; end

[nr, nc] = size(arr);
cx = C.UNWRAP_CENTER_X; if isempty(cx), cx = (nc + 1) / 2; end
cy = C.UNWRAP_CENTER_Y; if isempty(cy), cy = (nr + 1) / 2; end
r_in = C.UNWRAP_R_INNER; r_out = C.UNWRAP_R_OUTER;

if isempty(r_in) || isempty(r_out)
    m = isfinite(arr) & (arr ~= 0);
    if nnz(m) < 100
        fprintf('  [!] UNWRAP active mais impossible d''estimer le cylindre -> ignore.\n');
        return;
    end
    [ys, xs] = find(m);
    if isempty(C.UNWRAP_CENTER_X), cx = mean(xs); end
    if isempty(C.UNWRAP_CENTER_Y), cy = mean(ys); end
    rr = sqrt((xs - mean(xs)).^2 + (ys - mean(ys)).^2);
    if isempty(r_in),  r_in  = simple_quantile(rr, 0.05); end
    if isempty(r_out), r_out = simple_quantile(rr, 0.95); end
    fprintf('  [i] Parametres cylindre estimes : centre=(%.0f,%.0f), R in [%.0f,%.0f] px\n', ...
            cx, cy, r_in, r_out);
end

angles = linspace(0, 2 * pi, C.UNWRAP_N_ANGLES + 1); angles(end) = [];
radii  = linspace(r_in, r_out, C.UNWRAP_N_RADII);
[R, A] = meshgrid(radii, angles);          % n_angles x n_radii
X = min(max(cx + R .* cos(A), 1), nc);
Y = min(max(cy + R .* sin(A), 1), nr);
filled = arr; filled(~isfinite(filled)) = 0;
sampled = interp2(filled, X, Y, 'cubic');
% transpose : angle en abscisse, rayon en ordonnee
arr_u = sampled.';
extent_px = [0 360 r_out r_in];            % [left right bottom top]
end


% =========================================================================
%                          TRAITEMENTS GENERIQUES
% =========================================================================
function out = smooth_upsample(arr, C)
out = arr;
if ~C.APPLY_SMOOTHING, return; end
if exist('imbilatfilt', 'file') == 0
    fprintf('  [!] imbilatfilt indisponible -> lissage ignore.\n');
    return;
end

nanm = isnan(arr);
if any(nanm(:)), arr(nanm) = mean(arr(~nanm)); end

vmin = min(arr(:)); vmax = max(arr(:));
if vmax - vmin < 1e-12, out = arr; return; end
an = (arr - vmin) / (vmax - vmin);

% imbilatfilt attend une VARIANCE pour le lissage d'intensite (sigma^2)
af = imbilatfilt(an, C.BILATERAL_SIGMA_COLOR ^ 2, C.BILATERAL_SIGMA_SPATIAL, ...
                 'NeighborhoodSize', C.BILATERAL_WIN_SIZE);
af = af * (vmax - vmin) + vmin;
af = min(max(af, vmin), vmax);            % evite les valeurs hors plage

[nr, nc] = size(af);
factor = C.SMOOTH_FACTOR;
if (nr * factor) * (nc * factor) > C.MAX_SMOOTHED_PIXELS
    factor = max(1, sqrt(C.MAX_SMOOTHED_PIXELS / (nr * nc)));
    fprintf('  [i] Facteur d''upsampling reduit a %.2f.\n', factor);
end
if factor > 1
    af = imresize(af, factor, 'bilinear');
end
out = af;
end

function px = get_pixel_size_from_metadata(path)
px = [];
try
    t = Tiff(path, 'r');
    cleaner = onCleanup(@() close(t));
    xres = double(t.getTag('XResolution'));
    try
        unit = double(t.getTag('ResolutionUnit'));
    catch
        unit = 2;
    end
    if ~isfinite(xres) || xres <= 0, return; end
    if unit == 2
        mm_per_unit = 25.4;
    elseif unit == 3
        mm_per_unit = 10.0;
    else
        return;
    end
    px = mm_per_unit / xres;
catch
    px = [];
end
end

function [extent, is_mm] = resolve_extent(path, arr, extent_override, C)
% extent = [left right bottom top]
[nr, nc] = size(arr);
if ~isempty(extent_override)
    extent = extent_override; is_mm = false; return;
end
px = C.PIXEL_SIZE_MM;
if isempty(px), px = get_pixel_size_from_metadata(path); end
if ~isempty(px)
    extent = [0, nc * px, nr * px, 0]; is_mm = true; return;
end
if ~isempty(C.SAMPLE_WIDTH_MM) && ~isempty(C.SAMPLE_HEIGHT_MM)
    extent = [0, C.SAMPLE_WIDTH_MM, C.SAMPLE_HEIGHT_MM, 0]; is_mm = true; return;
end
[~, nm] = fileparts(path);
fprintf('  [!] Taille de pixel introuvable pour %s -> axes en pixels.\n', nm);
extent = [0, nc, nr, 0]; is_mm = false;
end

function [arr, extent] = crop_to_window(arr, extent, C)
% Decoupe le tableau a la fenetre XLIM/YLIM (mm). Si le tableau est plus court
% que la fenetre, la partie disponible est etiree pour la remplir.
[nr, nc] = size(arr);
x_left = extent(1); x_right = extent(2); y_bot = extent(3); y_top = extent(4);
dx = (x_right - x_left) / nc;
dz = (y_bot - y_top) / nr;

r0 = 0; r1 = nr; c0 = 0; c1 = nc;
nx0 = x_left; nx1 = x_right; ny0 = y_top; ny1 = y_bot;

if ~isempty(C.YLIM) && dz > 0
    z0 = max(min(C.YLIM), y_top);
    z1 = min(max(C.YLIM), y_bot);
    if z1 > z0
        r0 = round((z0 - y_top) / dz);
        r1 = round((z1 - y_top) / dz);
        ny0 = min(C.YLIM); ny1 = max(C.YLIM);
    end
end
if ~isempty(C.XLIM) && dx > 0
    x0 = max(min(C.XLIM), x_left);
    x1 = min(max(C.XLIM), x_right);
    if x1 > x0
        c0 = round((x0 - x_left) / dx);
        c1 = round((x1 - x_left) / dx);
        nx0 = min(C.XLIM); nx1 = max(C.XLIM);
    end
end

if r1 - r0 < 2 || c1 - c0 < 2, return; end
fprintf('  [i] Fenetre : lignes %d:%d / %d, colonnes %d:%d / %d\n', ...
        r0 + 1, r1, nr, c0 + 1, c1, nc);
arr = arr(r0+1:r1, c0+1:c1);
extent = [nx0, nx1, ny1, ny0];
end

function fs = compute_figsize(extent, C)
x_span = abs(extent(2) - extent(1));
y_span = abs(extent(3) - extent(4));
L = C.TARGET_LONG_SIDE_INCHES; S = C.MIN_SHORT_SIDE_INCHES;
if x_span == 0 || y_span == 0
    fs = [L, L * 3 / 4]; return;
end
ratio = x_span / y_span;
if ratio >= 1
    w = L; h = w / ratio;
    if h < S, h = S; w = h * ratio; end
else
    h = L; w = h * ratio;
    if w < S, w = S; h = w / ratio; end
end
fs = [w, h];
end

function dpi = get_effective_dpi(fs, C)
dpi = C.DPI;
if max(fs) * dpi > C.MAX_PIXELS_DIM
    dpi = C.MAX_PIXELS_DIM / max(fs);
end
end

function [vmin, vmax] = get_vrange(arr, C)
% Plage de couleurs automatique et robuste (methode de Tukey, facteur 3)
f = arr(isfinite(arr));
if isempty(f), vmin = 0; vmax = 1; return; end
if ~isempty(C.VMIN) && ~isempty(C.VMAX)
    vmin = C.VMIN; vmax = C.VMAX; return;
end
q1 = simple_quantile(f, 0.25);
q3 = simple_quantile(f, 0.75);
iqr_ = q3 - q1;
FACTOR = 3.0;
vmin_auto = max(q1 - FACTOR * iqr_, min(f));
vmax_auto = min(q3 + FACTOR * iqr_, max(f));
vmin = vmin_auto; vmax = vmax_auto;
if ~isempty(C.VMIN), vmin = C.VMIN; end
if ~isempty(C.VMAX), vmax = C.VMAX; end
fprintf('  [debug] min=%.2f  Q1=%.2f  med=%.2f  Q3=%.2f  max=%.2f  -> vmin=%.2f  vmax=%.2f\n', ...
        min(f), q1, median(f), q3, max(f), vmin, vmax);
if vmin >= vmax, vmax = vmin + 1; end
end

function cm = two_slope_colormap(name, vmin, vmax, n)
% Equivalent de TwoSlopeNorm(vcenter=0) : le centre de la palette est en 0
base = feval(name, 256);
v = linspace(vmin, vmax, n).';
u = zeros(n, 1);
neg = v < 0;
u(neg)  = 0.5 * (v(neg) - vmin) / (0 - vmin);
u(~neg) = 0.5 + 0.5 * v(~neg) / vmax;
cm = interp1(linspace(0, 1, 256), base, u);
end


% =========================================================================
%                                 TRACE
% =========================================================================
function out_path = plot_tiff_to_png(tiff_path, out_dir, C)
[~, base_name] = fileparts(tiff_path);
file_type = detect_file_type(base_name);
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

% --- pipeline ---
arr = load_tiff(tiff_path, C);
arr = crop_borders(arr, C);
arr = remove_artifacts(arr, base_name, fullfile(out_dir, [base_name '_mask.png']), C);
[arr, extent_override] = maybe_unwrap(arr, C);

[extent, is_mm] = resolve_extent(tiff_path, arr, extent_override, C);
if C.FILL_AXES_LIMITS && isempty(extent_override)
    [arr, extent] = crop_to_window(arr, extent, C);
end
[vmin, vmax] = get_vrange(arr, C);
arr_plot = smooth_upsample(arr, C);

fs  = compute_figsize(extent, C);
dpi = get_effective_dpi(fs, C);

fig = figure('Visible', 'off', 'Units', 'inches', 'Color', 'w', ...
             'Position', [1 1 fs(1) fs(2)]);
ax = axes(fig);

% coordonnees des centres de pixels
[nr2, nc2] = size(arr_plot);
dxp = (extent(2) - extent(1)) / nc2;
dzp = (extent(3) - extent(4)) / nr2;
xdata = [extent(1) + dxp / 2, extent(2) - dxp / 2];
ydata = [extent(4) + dzp / 2, extent(3) - dzp / 2];
imagesc(ax, xdata, ydata, arr_plot);
set(ax, 'YDir', 'reverse');
daspect(ax, [1 1 1]);

switch file_type
    case 'roughness'
        if vmin < 0 && vmax > 0
            colormap(ax, two_slope_colormap(C.CMAP_ROUGHNESS, vmin, vmax, 256));
        else
            colormap(ax, feval(C.CMAP_ROUGHNESS, 256));
        end
        cbar_label = sprintf('Rugosit%c (%s)', 233, C.UNIT_LABEL);
        ttl = sprintf('%s - Surface roughness map (vue de dessus)', base_name);
    case 'aligned'
        colormap(ax, feval(C.CMAP_ALIGNED, 256));
        cbar_label = sprintf('Hauteur (%s)', C.UNIT_LABEL);
        ttl = sprintf('%s - Aligned surface map (vue de dessus)', base_name);
    otherwise
        colormap(ax, jet(256));
        cbar_label = sprintf('Valeur (%s)', C.UNIT_LABEL);
        ttl = base_name;
end
caxis(ax, [vmin vmax]);

% --- axes ---
if ~isempty(extent_override)
    xlabel(ax, 'Angle (\circ)', 'FontSize', C.AXIS_LABEL_FONTSIZE);
    ylabel(ax, 'Rayon (px)',    'FontSize', C.AXIS_LABEL_FONTSIZE);
elseif is_mm
    xlabel(ax, 'Y (mm)', 'FontSize', C.AXIS_LABEL_FONTSIZE);
    ylabel(ax, 'Z (mm)', 'FontSize', C.AXIS_LABEL_FONTSIZE);
else
    xlabel(ax, 'Y (px)', 'FontSize', C.AXIS_LABEL_FONTSIZE);
    ylabel(ax, 'Z (px)', 'FontSize', C.AXIS_LABEL_FONTSIZE);
end
title(ax, ttl, 'FontSize', C.TITLE_FONTSIZE, 'FontWeight', 'bold', 'Interpreter', 'none');
ax.FontSize = C.TICK_FONTSIZE;
ax.Box = 'on';
ax.TickDir = 'out';

% limites d'axes = etendue affichee
xlim(ax, sort([extent(1) extent(2)]));
ylim(ax, sort([extent(3) extent(4)]));

% --- colorbar ---
if strcmp(C.COLORBAR_ORIENTATION, 'horizontal')
    cb = colorbar(ax, 'southoutside');
else
    cb = colorbar(ax, 'eastoutside');
end
cb.Label.String = cbar_label;
cb.Label.FontSize = C.CBAR_LABEL_FONTSIZE;
cb.FontSize = C.CBAR_TICK_FONTSIZE;
cb.Label.Interpreter = 'tex';

out_path = fullfile(out_dir, [base_name '.png']);
if exist('exportgraphics', 'file') == 2 || exist('exportgraphics', 'builtin') == 5
    exportgraphics(fig, out_path, 'Resolution', dpi, 'BackgroundColor', 'white');
else
    print(fig, out_path, '-dpng', sprintf('-r%d', round(dpi)));
end
close(fig);
end
