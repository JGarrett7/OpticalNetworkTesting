%% PeakLossShape.m
% Two-path resolution test (paper section "Multiplexing Resolution Limit").
%
% Part 1 builds a normalized pulse shape (master curve) from the
% single-path recordings in "Changing Amplitude". Part 2 fits every
% recording in "Two Path Experiment" as the sum of two copies of that
% shape, converts each fitted position to a path length and compares it
% with the known lengths. The file names give the two lengths, for example
% ..._95cmx5cm.csv is a 95 cm path and a 5 cm path.
%
% The Command Window lists the predicted lengths and errors for every
% configuration and ends with a summary table. The paper's failure
% criterion is an error above 5 mm on either path.
%
% Outputs in this folder: normalized_curve_fit.mat, curve_peak_width.mat,
% ManyCurves, CurveFitting and NormalizedCurve figures, and one
% CurveFitting_<short>-<long> figure per configuration (lengths in mm).
%
% Requirements: MATLAB R2024a or later, Curve Fitting Toolbox and Signal
% Processing Toolbox.

close all hidden
clear

% Work in the folder that contains this script so relative paths resolve
scriptFolder = fileparts(mfilename('fullpath'));
if ~isempty(scriptFolder)
    cd(scriptFolder);
end

%% Settings %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
FigureWidth = 5.5;     % size of the saved figures in inches (not paper figures)

% Linear conversion from fitted bin position to path length:
% length (mm) = mmPerBin * position (bins) + offsetMm
mmPerBin = 47.2182125410147;
offsetMm = -2017.7111947878700;

% Failure criterion used in the paper (mm)
errorLimitMm = 5;

num_detectors = 16;    % the GUI writes 16 aggregate columns per bin; only a0 holds data
floor_threshold = 15;  % median values below this (kcps) are set to zero

%% Part 1: Pulse Shape from Single-Path Recordings %%%%%%%%%%%%%%%%%%%%%%%%%%
directory = fullfile(pwd, 'Changing Amplitude');
folderContents = fileDatastore(fullfile(directory, 'data*'), 'ReadFcn', @importdata);

init_table = readtable(string(folderContents.Files(1)), 'VariableNamingRule', 'Preserve');

% Histogram columns for aggregate a0 (75 bins in these recordings)
cnhstop = find(string(init_table.Properties.VariableNames) == "cnh__hist_bin_74_a15");
cnhstart = find(string(init_table.Properties.VariableNames) == "cnh__hist_bin_0_a0");
hist_cols = cnhstart:num_detectors:cnhstop;
n_hist_bins = numel(hist_cols);

data_var_names = init_table.Properties.VariableNames(hist_cols);
data_var_types = varfun(@class, init_table(:, hist_cols), 'OutputFormat', 'cell');

% Stack the frames of every file into one table
single_curve_data = table('Size', [0, n_hist_bins], 'VariableTypes', data_var_types, 'VariableNames', data_var_names);

stop = 0;
for fileIndex = 1:length(folderContents.Files)
    fileTable = readtable(string(folderContents.Files(fileIndex)), 'VariableNamingRule', 'Preserve');

    nRows = height(fileTable);
    start = stop + 1;
    stop = stop + nRows;

    for histidx = 1:n_hist_bins
        single_curve_data(start:stop, histidx) = fileTable(:, hist_cols(histidx));
    end
end

% Diagnostic figure: every frame normalized to its own maximum
fig = figure();
for rowidx = 1:height(single_curve_data)
    m = max(single_curve_data{rowidx, :});
    plot(0:(width(single_curve_data) - 1), transpose(single_curve_data{rowidx, :})./m)
    hold on
end
grid on;
xlabel('Histogram Bin')
ylabel('Normalized Amplitude');
save_figure(fig, 'ManyCurves', FigureWidth, 10);

% Median of all frames, values below the floor set to zero, normalized to 1
median_data = median(single_curve_data, 1, 'omitmissing');

m_floored_data = median_data;
m_floored_data{1, table2array(m_floored_data < floor_threshold)} = zeros(1, width(m_floored_data(1, table2array(m_floored_data < floor_threshold))));

m = max(table2array(m_floored_data), [], 'all');
m_f_normalized_data = m_floored_data./m;

x = 0:74;

% Pad with zeros on both sides so the curve is zero when shifted
m_f_n_spread_data = horzcat(horzcat(zeros(1, width(m_f_normalized_data)), table2array(m_f_normalized_data)), zeros(1, width(m_f_normalized_data)));

% Shape-preserving (pchip) interpolant centered so the peak is at x = 0
ft = 'pchipinterp';
opts = fitoptions( 'Method', 'PchipInterpolant' );
opts.ExtrapolationMethod = 'pchip';
opts.Normalize = 'on';

[~, idx] = max(m_f_n_spread_data, [], 'all');

normalized_curve = fit(transpose(-(idx - 1):(width(m_f_n_spread_data)) - 1 - (idx - 1)), transpose(m_f_n_spread_data), ft, opts);

save('normalized_curve_fit.mat', 'normalized_curve');

% Diagnostic figure: the interpolant and the padded median data
fig = figure();
plot(normalized_curve)
hold on
plot(0:width(m_f_n_spread_data) - 1, transpose(m_f_n_spread_data));
text(0 , 0.75, evalc('disp(normalized_curve)'), 'FontSize',10)
grid on;
xlabel('Histogram Bin')
ylabel('Normalized Amplitude');
save_figure(fig, 'CurveFitting', FigureWidth, 10);

% Diagnostic figure: the curve scaled by 2 and shifted to bin 30
fig = figure();
plot(x, 2*normalized_curve(x-30))
grid on;
xlabel('Histogram Bin')
ylabel('Normalized Amplitude');
save_figure(fig, 'NormalizedCurve', FigureWidth, 10);

% Full width of the normalized peak, used for the initial guesses below
[curve_peak_height, ~, curve_peak_width, ~] = findpeaks(normalized_curve(-width(single_curve_data):width(single_curve_data)));
curve_peak_width = curve_peak_width(curve_peak_height == 1);
save('curve_peak_width.mat', 'curve_peak_width');

% Model: one pulse (fun) and the sum of two pulses (funfun)
fun = @(height, position, x) height*normalized_curve(x - position);
funfun = @(height1, position1, height2, position2, x) height1*normalized_curve(x - position1) + height2*normalized_curve(x - position2);
fitfun = fittype(funfun);

%% Part 2: Two-Path Recordings %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
directory = fullfile(pwd, 'Two Path Experiment');
folderContents = fileDatastore(fullfile(directory, 'data*'), 'ReadFcn', @importdata);

init_table = readtable(string(folderContents.Files(1)), 'VariableNamingRule', 'Preserve');

cnhstop = find(string(init_table.Properties.VariableNames) == "cnh__hist_bin_74_a15");
cnhstart = find(string(init_table.Properties.VariableNames) == "cnh__hist_bin_0_a0");
hist_cols = cnhstart:num_detectors:cnhstop;
n_hist_bins = numel(hist_cols);

% One row per file: the two path lengths (mm) followed by the median histogram
data_var_names = [{'distance1', 'distance2'}, init_table.Properties.VariableNames(hist_cols)];
data_var_types = [{'double', 'double'}, varfun(@class, init_table(:, hist_cols), 'OutputFormat', 'cell')];

data = table('Size', [length(folderContents.Files), n_hist_bins + 2], 'VariableTypes', data_var_types, 'VariableNames', data_var_names);

for fileIndex = 1:length(folderContents.Files)
    fileTable = readtable(string(folderContents.Files(fileIndex)), 'VariableNamingRule', 'Preserve');

    for histidx = 1:n_hist_bins
        data(fileIndex, 2 + histidx) = median(fileTable(:, hist_cols(histidx)), 1);
    end

    % Lengths from the file name: <distance1>cmx<distance2>cm
    cut_distances = regexp(folderContents.Files(fileIndex), '(\d+)\s*cmx(\d+)\s*cm', 'tokens');
    data(fileIndex, :).distance1 = str2double(cut_distances{1, 1}{1, 1}{1}) * 10; % cm to mm
    data(fileIndex, :).distance2 = str2double(cut_distances{1, 1}{1, 1}{2}) * 10; % cm to mm
end

% Results for the summary table
n_cfg = height(data);
results = NaN(n_cfg, 6);   % short, long, predicted short, predicted long, error short, error long

for curveidx = 1:n_cfg

    fig = figure();
    plot(1:width(data) - 2, transpose(data{curveidx, 3:end}), 'LineWidth', 3)
    hold on

    % Normalize the histogram to its maximum
    m = max(data{curveidx, 3:end});
    normalized = data{curveidx, 3:end}/double(m);

    % Peaks with prominence above 1% of the maximum
    [pks, pkidxs, pkwdths, pkproms] = findpeaks(normalized);
    real_peaks = pkproms > 0.01;
    peak_table = array2table(horzcat(transpose(pks(real_peaks)), transpose(pkidxs(real_peaks)), transpose(pkwdths(real_peaks)), transpose(pkproms(real_peaks))), ...
        'VariableNames', {'Peak Height', 'Peak Location', 'Peak Width', 'Peak Prominence'});

    % Initial guesses and bounds: [height1, position1, height2, position2]
    fit_start = zeros(1, 4);
    if height(peak_table) == 1
        % One merged peak: place one pulse on each side of it
        fit_start(2:2:4) = [peak_table.("Peak Location") - peak_table.("Peak Width")/2 + curve_peak_width/2, peak_table.("Peak Location") + peak_table.("Peak Width")/2 - curve_peak_width/2];
        fit_start(1:2:3) = [normalized(floor(peak_table.("Peak Location") - peak_table.("Peak Width")/2 + curve_peak_width/2)), normalized(ceil(peak_table.("Peak Location") + peak_table.("Peak Width")/2 - curve_peak_width/2))];

        fit_lower = [peak_table.("Peak Height")/2, -inf, 0, peak_table.("Peak Location")];
        fit_upper = [1, peak_table.("Peak Location"), peak_table.("Peak Height")/2, inf];

    elseif height(peak_table) == 2
        % Two separate peaks: start each pulse at its peak
        fit_start(1:2:3) = peak_table.("Peak Height");
        fit_start(2:2:4) = peak_table.("Peak Location");

        fit_lower = [0, -inf, 0, -inf];
        fit_upper = [1, inf, 1, inf];

    else
        error('Expected one or two peaks in %s but found %d.', folderContents.Files{curveidx}, height(peak_table));
    end

    l = fit(transpose(1:width(data) - 2), transpose(normalized), fitfun, 'Start', fit_start, 'Lower', fit_lower, 'Upper', fit_upper);

    plot(0:width(normalized), l(0:width(normalized))*double(m), 'LineWidth', 3)

    coeffss = coeffvalues(l);

    % Fitted positions (bins) to path lengths (mm)
    predicted_lens = mmPerBin*coeffss(2:2:4) + offsetMm;

    plot(x, fun(coeffss(1)*m, coeffss(2), x), 'LineWidth', 3)
    plot(x, fun(coeffss(3)*m, coeffss(4), x), 'LineWidth', 3)

    shortLen = data(curveidx, :).distance2;
    longLen = data(curveidx, :).distance1;
    errShort = abs(predicted_lens(1) - shortLen);
    errLong = abs(predicted_lens(2) - longLen);
    results(curveidx, :) = [shortLen, longLen, predicted_lens(1), predicted_lens(2), errShort, errLong];

    fprintf('For lengths of %g mm and %g mm. Predicted %.4f mm length and %.4f mm. This is an error of %.4f and %.4f\n', ...
        shortLen, longLen, predicted_lens(1), predicted_lens(2), errShort, errLong);

    title({sprintf('For lengths of %g mm and %g mm.', shortLen, longLen), ...
           sprintf('Predicted %.4f mm length and %.4f mm.', predicted_lens(1), predicted_lens(2)), ...
           sprintf('This is an error of %.4f and %.4f', errShort, errLong), ''})
    grid on;
    xlabel('Histogram Bin (Equivalent to Distance)')
    ylabel('Signal Amplitude (Kcps)');
    legend('Experimental Data', 'Deconvolved Sum', 'Deconvolved Signal 1', 'Deconvolved Signal 2');
    ylim([0, 12*10^4]);
    save_figure(fig, sprintf('CurveFitting_%g-%g', shortLen, longLen), FigureWidth, 16);
end

%% Summary %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Sorted by path-length difference. "Within limit" applies the paper's
% criterion: both errors at or below errorLimitMm.
[~, order] = sort(results(:, 2) - results(:, 1));
fprintf('\n%10s %10s %12s %14s %14s %14s\n', 'Short(mm)', 'Long(mm)', 'Diff(cm)', 'Err short(mm)', 'Err long(mm)', 'Within limit');
for k = order'
    withinLimit = max(results(k, 5:6)) <= errorLimitMm;
    fprintf('%10g %10g %12g %14.2f %14.2f %14s\n', results(k, 1), results(k, 2), (results(k, 2) - results(k, 1))/10, ...
        results(k, 5), results(k, 6), string(withinLimit));
end

%% Local Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function save_figure(fig, name, figureWidth, fontPoints)
%SAVE_FIGURE Size a figure and save it as <name>.fig and <name>.png here.
    fontsize(fig, fontPoints, 'points');
    set(fig, 'Units', 'inches', 'Position', [5, 5, figureWidth, figureWidth]);
    if isprop(fig, 'Theme')   % figure themes exist in R2025a and later
        fig.Theme = 'light';
    end
    saveas(fig, [name '.fig']);
    exportgraphics(fig, [name '.png']);
end
