%% ==================================================
%  Affichage carte surface TIFF en 3D - Version simple
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

img = imread(filename, 1);
img = double(img);

% Conversion m -> mm
img = img * 1e3;

% Gestion NaN
if any(isnan(img(:)))
    meanVal = mean(img(:), 'omitnan');
    img(isnan(img)) = meanVal;
end

% Sur-échantillonnage (bicubique)
scale = 4;
img = imresize(img, scale, 'bicubic');


%% ==================================================
%  Dimensions physiques
%  ==================================================

width_mm  = 34.96;
height_mm = 23.57;

[nRows, nCols] = size(img);
y = linspace(0, width_mm, nCols);
z = linspace(0, height_mm, nRows);
[Y, Z] = meshgrid(y, z);


%% ==================================================
%  Echelle couleur
%  ==================================================

vmin = min(img(:), [], 'omitnan');
vmax = max(img(:), [], 'omitnan');


%% ==================================================
%  Figure 3D - fond blanc classique
%  ==================================================

fig = figure('Color', 'w', 'Position', [80 80 1000 700], ...
    'Name', 'EchantillonCM-11 - Surface aligned map 3D');

ax = axes('Parent', fig);
surf(ax, Y, Z, img, 'EdgeColor', 'none');

colormap(ax, jet);
caxis(ax, [vmin vmax]);
colorbar;

xlabel(ax, 'Y (mm)');
ylabel(ax, 'Z (mm)');
zlabel(ax, 'Aligned (mm)');
title(ax, 'EchantillonCM-11 - Surface aligned map');

axis(ax, 'tight');
view(ax, 45, 30);
shading(ax, 'interp');

% Style MATLAB classique : fond blanc, grille grise, axes noirs
set(ax, 'Color', 'w', ...
    'XColor', [0.15 0.15 0.15], ...
    'YColor', [0.15 0.15 0.15], ...
    'ZColor', [0.15 0.15 0.15], ...
    'GridColor', [0.15 0.15 0.15], ...
    'GridAlpha', 0.15, ...
    'Box', 'on');
