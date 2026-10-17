function ExportFigure(fig, savename, FigureWidth, FigureHeight)
%EXPORTFIGURE Save a figure as .fig, .eps (vector) and .png (300 dpi).
%
%   EXPORTFIGURE(FIG, SAVENAME, FIGUREWIDTH) resizes FIG to a square of
%   FIGUREWIDTH inches, sets every font to 10 pt and writes
%   Figures/SAVENAME.fig, Figures/SAVENAME.eps and Figures/SAVENAME.png in
%   the current folder. The Figures folder is created if needed.
%
%   EXPORTFIGURE(FIG, SAVENAME, FIGUREWIDTH, FIGUREHEIGHT) uses a
%   FIGUREWIDTH by FIGUREHEIGHT inch figure instead of a square one.
%
%   Requires MATLAB R2022a or later. In R2025a and later, the figure is
%   also set to the light theme so exports look the same in any desktop
%   theme.

arguments
    fig
    savename string
    FigureWidth double
    FigureHeight double = FigureWidth
end

% Output folder
figDir = fullfile(pwd, 'Figures');
if ~isfolder(figDir)
    [success, msg] = mkdir(figDir);
    if ~success
        error('ExportFigure:DirectoryError', ...
            'Could not create the Figures folder at:\n%s\n\nMATLAB error: %s', figDir, msg);
    end
end

% Size and fonts
fontsize(fig, 10, 'points');
set(fig, 'Units', 'inches', 'Position', [5, 5, FigureWidth, FigureHeight]);
if isprop(fig, 'Theme')   % figure themes exist in R2025a and later
    fig.Theme = 'light';
end

% Set every font size explicitly as well, so the EPS export keeps 10 pt text
set(findall(fig, '-property', 'FontSize'), 'FontSize', 10);

% Write the three files
saveas(fig, char(fullfile(figDir, savename + ".fig")));
exportgraphics(fig, char(fullfile(figDir, savename + ".eps")), 'ContentType', 'vector');
exportgraphics(fig, char(fullfile(figDir, savename + ".png")), 'Resolution', 300);

end
