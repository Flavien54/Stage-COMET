%% ==================================================
%  Affichage carte surface TIFF en 3D - Version générique
%  (s'adapte automatiquement aux fichiers "aligned" et
%   "roughness" en fonction du nom de fichier)
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

[~, baseName, ~] = fileparts(fileName);


%% ==================================================
%  Détection du type de donnée (aligned / roughness)
%  à partir du nom de fichier
%  ==================================================
%  -> Ajoute simplement tes propres mots-clés dans les
%     regexp ci-dessous si tes fichiers utilisent une
%     autre convention de nommage.

if ~isempty(regexpi(baseName, 'rough|rugo', 'once'))
    dataType = 'roughness';
elseif ~isempty(regexpi(baseName, 'align', 'once'))
    dataType = 'aligned';
else
    warning(['Type de donnée non détecté dans le nom du fichier ' ...
             '("%s") -> "aligned" utilisé par défaut.'], baseName);
    dataType = 'aligned';
end

switch dataType
    case 'aligned'
        typeLabelFr   = 'Hauteur alignée';
        typeLabelTitre = 'aligned';
        unitLabel     = 'mm';
        unitFactor    = 1e3;   % conversion m -> mm
    case 'roughness'
        typeLabelFr   = 'Rugosité';
        typeLabelTitre = 'roughness';
        unitLabel     = '\mum';  % micromètres
        unitFactor    = 1e6;   % conversion m -> µm (à ajuster si les données
                                % sont déjà en µm : mettre unitFactor = 1)
end

% Nom d'échantillon "propre" : on retire le mot-clé de type du nom de fichier
sampleLabel = regexprep(baseName, '[-_ ]?(aligned|rough|rugo).*', '', 'ignorecase');
if isempty(sampleLabel)
    sampleLabel = baseName;
end


%% ==================================================
%  Lecture TIFF
%  ==================================================

img = imread(filename, 1);
img = double(img);

% Conversion selon le type de donnée détecté
img = img * unitFactor;

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

figTitle = sprintf('%s - Surface %s map', sampleLabel, typeLabelTitre);

fig = figure('Color', 'w', 'Position', [80 80 1000 700], ...
    'Name', [figTitle ' 3D']);

ax = axes('Parent', fig);

% Sous-échantillonnage POUR L'AFFICHAGE UNIQUEMENT (données img intactes).
% surf() devient très lourd / peut planter au-delà de quelques centaines
% de milliers de points -> on vise ~300x300 points affichés max.
maxPointsPerAxis = 300;
stepR = max(1, floor(nRows / maxPointsPerAxis));
stepC = max(1, floor(nCols / maxPointsPerAxis));

surf(ax, Y(1:stepR:end, 1:stepC:end), ...
         Z(1:stepR:end, 1:stepC:end), ...
         img(1:stepR:end, 1:stepC:end), ...
         'EdgeColor', 'none');

colormap(ax, jet);
caxis(ax, [vmin vmax]);

zLabelStr = sprintf('%s (%s)', typeLabelFr, unitLabel);

xlabel(ax, 'Y (mm)', 'Color', 'k');
ylabel(ax, 'Z (mm)', 'Color', 'k');
zlabel(ax, zLabelStr, 'Color', 'k');
title(ax, figTitle, 'Color', 'k', 'FontWeight', 'bold');

axis(ax, 'tight');
view(ax, 45, 30);
shading(ax, 'interp');

% Style MATLAB classique : fond blanc, grille grise claire, axes/texte noir pur
set(ax, 'Color', 'w', ...
    'XColor', 'k', ...
    'YColor', 'k', ...
    'ZColor', 'k', ...
    'GridColor', [0.5 0.5 0.5], ...
    'GridAlpha', 0.25, ...
    'Box', 'on');

set(get(ax, 'Title'), 'Color', 'k');
cb = colorbar;
cb.Color = 'k';
cb.Label.String = zLabelStr;
cb.Label.Color = 'k';
