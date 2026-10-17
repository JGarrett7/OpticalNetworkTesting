%% LossProcessing.m
% Cutback test of the molded Clear Flex 30 waveguides (paper Figure 11).
%
% Each data_*.csv file in .\data is one waveguide length. The length in mm
% is the number before "mm" at the end of the file name (050, 070, 090,
% 110). The figure keeps the file name Optical_TPU_Signal_Characteristics
% used in the paper source, although the specimens are Clear Flex 30. For
% each file, the median of every histogram column is taken over all frames
% and the largest median is the received signal. A straight line is fit to
% log10(signal) versus length, and the attenuation is reported in dB/mm.
%
% Requirements: MATLAB R2024a or later and Curve Fitting Toolbox. The
% figure is written to .\Figures by ExportFigure.m.

close all
clear

% Work in the folder that contains this script so relative paths resolve
scriptFolder = fileparts(mfilename('fullpath'));
if ~isempty(scriptFolder)
    cd(scriptFolder);
end

%% Settings %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
figureWidth = 3.4;            % exported figure size in inches
c1 = [0 0.4470 0.7410];       % blue (data)
c2 = [0.8500 0.3250 0.0980];  % orange (fit)

%% Data Loading %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
folderLocation = fullfile(pwd, 'data');
if ~isfolder(folderLocation)
    folderLocation = uigetdir(pwd, 'Select the folder that contains the cutback CSV files');
    if isequal(folderLocation, 0)
        disp('User canceled folder selection.');
        return;
    end
end

files = dir(fullfile(folderLocation, 'data_*.csv'));
numFiles = numel(files);
if numFiles == 0
    error('No data_*.csv files found in %s', folderLocation);
end

signals = zeros(numFiles, 1);
NominalDistances = zeros(numFiles, 1);   % waveguide length in mm

for fileIndex = 1:numFiles
    filePath = fullfile(files(fileIndex).folder, files(fileIndex).name);
    tbl = readtable(filePath, 'VariableNamingRule', 'Preserve');

    % Histogram columns start at cnh__hist_bin_0_a0 and run to the last column
    histStart = find(strcmp(tbl.Properties.VariableNames, 'cnh__hist_bin_0_a0'), 1);
    if isempty(histStart)
        error('Column cnh__hist_bin_0_a0 not found in %s', files(fileIndex).name);
    end

    % Median of each histogram column over all frames, then the largest median
    signals(fileIndex) = max(median(tbl{:, histStart:end}, 'omitmissing'));

    % Waveguide length (mm) from the file name, for example ..._050mm.csv
    lengthToken = regexp(files(fileIndex).name, '(\d+)mm\.csv$', 'tokens', 'once', 'ignorecase');
    if isempty(lengthToken)
        error('No length such as 050mm at the end of %s', files(fileIndex).name);
    end
    NominalDistances(fileIndex) = str2double(lengthToken{1});
end

%% Curve Fitting %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% log10(signal) = slope * length + intercept, so loss (dB/mm) = -10 * slope
l = fit(NominalDistances, log10(signals), 'poly1');
coeffs = coeffvalues(l);
dbloss = -10 * coeffs(1);
fprintf('Linear estimate of loss is %.4f dB/mm\n', dbloss);
fprintf('Fit with length in cm: signal = 10^(%.3f x %+.3f) kcps\n', coeffs(1)*10, coeffs(2));

%% Plotting %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fig = figure('Name', 'Optical TPU Signal Characteristics', 'Color', 'w');
ax = axes('Parent', fig);
hold(ax, 'on');

% Measured signal at each length
plot(ax, NominalDistances/10, signals, 'o', 'Color', c1, 'MarkerFaceColor', c1, 'MarkerSize', 6, 'DisplayName', 'Raw Data');

% Fitted line
plot(ax, NominalDistances/10, 10.^(coeffs(1)*NominalDistances + coeffs(2)), '--', 'Color', c2, 'LineWidth', 2, 'DisplayName', 'Log Fit');

% Formatting
set(ax, 'YScale', 'log');
xlim(ax, [min(NominalDistances)/10, max(NominalDistances)/10]);
xticks(ax, [5, 7, 9, 11])

ax.YAxis.FontSize = 12;
ax.TickLength = [0.05, 0.05];
xlabel(ax, 'Waveguide Length (cm)', 'FontWeight', 'bold');
ylabel(ax, 'Signal [Kcps]', 'FontWeight', 'bold');

set(ax, 'Box', 'off', 'XGrid', 'off', 'YGrid', 'off', 'XColor', 'k', 'YColor', 'k', 'FontSize', 11);
lgd = legend(ax, 'show', 'Location', 'northeast');
set(lgd, 'EdgeColor', [0.8 0.8 0.8]);

%% Export %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ExportFigure(fig, 'Optical_TPU_Signal_Characteristics', figureWidth);
hold(ax, 'off');
