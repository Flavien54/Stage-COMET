%% ==================================================
%  Affichage carte surface TIFF - Equivalent MATLAB
%  ==================================================
clear; clc; close all;

%% ==================================================
%  Sélection fichier TIFF
%  ==================================================

[fileName, filePath] = uigetfile({'*.tif;*.tiff', 'TIFF files (*.tif, *.tiff)'}, ...
    'Sélectionner la carte surface TIFF');

if isequal(fileName, 0)
    disp('Aucun fichier sélectionné');
    return;
end

filename = fullfile(filePath, fileName);

fprintf('Fichier chargé :\n%s\n', filename);


%% ==================================================
%  Lecture TIFF
%  ==================================================

tiffInfo = imfinfo(filename);
numFrames = numel(tiffInfo);

img = imread(filename, 1);

fprintf('\nInformations TIFF\n');
fprintf('----------------\n');
fprintf('Dimensions : %s\n', mat2str(size(img)));
fprintf('Type : %s\n', class(img));
fprintf('Min brut : %g\n', min(img(:), [], 'omitnan'));
fprintf('Max brut : %g\n', max(img(:), [], 'omitnan'));

if numFrames > 1
    disp('Stack 3D détecté -> slice 1');
end

img = double(img);

% Conversion m -> mm
img = img * 1e3;

fprintf('\nAprès conversion mm\n');
fprintf('-------------------\n');
fprintf('Min : %g mm\n', min(img(:), [], 'omitnan'));
fprintf('Max : %g mm\n', max(img(:), [], 'omitnan'));

% Gestion NaN
if any(isnan(img(:)))
    disp('NaN détectés');
    meanVal = mean(img(:), 'omitnan');
    img(isnan(img)) = meanVal;
end

% Sur-échantillonnage (équivalent scipy.ndimage.zoom, order=3 -> bicubic)
scale = 4;
img = imresize(img, scale, 'bicubic');
fprintf('Nouvelle résolution : %s\n', mat2str(size(img)));


%% ==================================================
%  Dimensions physiques
%  ==================================================

width_mm  = 34.96;
height_mm = 23.57;


%% ==================================================
%  Echelle couleur
%  ==================================================

vmin = -0.08;
vmax = 0.04;

imgMin = min(img(:), [], 'omitnan');
imgMax = max(img(:), [], 'omitnan');

if imgMin > vmin || imgMax < vmax
    vmin = imgMin;
    vmax = imgMax;
end


%% ==================================================
%  Figure
%  ==================================================

fig = figure('Color', 'k', 'Position', [80 80 1600 720], ...
    'Name', 'EchantillonCM-11 - Surface aligned map');

% --------------------------------------------------
% Panneau d'information (gauche)
% --------------------------------------------------
ax_info = axes('Parent', fig, 'Position', [0.02 0.10 0.11 0.84]);
axis(ax_info, 'off');
set(ax_info, 'Color', 'k');

infoStr = sprintf([ ...
    '%.2f x %.2f mm\n\n' ...
    'Range  Min: %.2f  Max: %.2f mm\n\n' ...
    'Slice 1 / 1\n\n\n' ...
    'Yaw:   90.0 deg\n\n' ...
    'Pitch: 90.0 deg\n\n' ...
    'Roll:  91.2 deg'], ...
    width_mm, height_mm, imgMin, imgMax);

text(ax_info, 0.0, 1.0, infoStr, ...
    'FontSize', 12, ...
    'Color', [0.31 0.76 0.97], ...
    'VerticalAlignment', 'top', ...
    'HorizontalAlignment', 'left', ...
    'FontName', 'Helvetica', ...
    'Units', 'normalized');

% --------------------------------------------------
% Carte principale (droite, large)
% --------------------------------------------------
ax = axes('Parent', fig, 'Position', [0.155 0.175 0.825 0.78]);

im = imagesc(ax, [0 width_mm], [0 height_mm], img);
set(ax, 'YDir', 'normal');
colormap(ax, jet);
caxis(ax, [vmin vmax]);
axis(ax, [0 width_mm 0 height_mm]);

xlabel(ax, 'Y (mm)', 'FontSize', 12, 'Color', 'w');
ylabel(ax, 'Z (mm)', 'FontSize', 12, 'Color', 'w');
title(ax, 'EchantillonCM-11 - Surface aligned map', 'FontSize', 15, 'Color', 'w');

set(ax, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'FontSize', 11);

% --------------------------------------------------
% Colorbar horizontale (bas)
% --------------------------------------------------
ax_cbar_pos = [0.155 0.08 0.825 0.035];
cbar = colorbar(ax, 'southoutside');
cbar.Label.String = 'Aligned (mm)';
cbar.Label.FontSize = 12;
cbar.Label.Color = 'w';
cbar.Color = 'w';
cbar.FontSize = 11;
set(ax, 'Position', [0.155 0.175 0.825 0.78]); % réajuste après colorbar

% --------------------------------------------------
% Annotation "Object Count" en bas à gauche
% --------------------------------------------------
annotation(fig, 'textbox', [0.01 0.005 0.3 0.04], ...
    'String', 'Object Count: 194', ...
    'FontSize', 12, ...
    'Color', [0.31 0.76 0.97], ...
    'EdgeColor', 'none', ...
    'HorizontalAlignment', 'left');


%% ==================================================
%  Coordonnées en mm au survol de la souris
%  (équivalent de format_coord de matplotlib)
%  ==================================================

coordText = uicontrol(fig, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.35 0.005 0.55 0.04], ...
    'BackgroundColor', 'k', ...
    'ForegroundColor', 'w', ...
    'FontSize', 10, ...
    'HorizontalAlignment', 'left', ...
    'String', '');

set(fig, 'WindowButtonMotionFcn', @(src, evt) updateCoord(ax, img, width_mm, height_mm, coordText));

fig.UserData.updateCoordFcn = @updateCoord; % conservé pour référence


%% ==================================================
%  Fonction locale : mise à jour des coordonnées
%  ==================================================

function updateCoord(ax, img, width_mm, height_mm, coordText)
    cp = get(ax, 'CurrentPoint');
    x = cp(1, 1);
    y = cp(1, 2);

    if x < 0 || x > width_mm || y < 0 || y > height_mm
        set(coordText, 'String', '');
        return;
    end

    [nRows, nCols] = size(img);
    col = min(max(round((x / width_mm) * nCols), 1), nCols);
    row = min(max(round((y / height_mm) * nRows), 1), nRows);

    value = img(row, col);

    str = sprintf('X=%.3f mm   Y=%.3f mm   Z=%.5f mm', x, y, value);
    set(coordText, 'String', str);
end
