%% MultiPeakPressure.m
% Pressing tests on the hard-junction prototype network.
% Produces paper Figure 3 (deconvolved histogram) and Figure 7 (box plots
% of normalized peak amplitude versus applied mass).
%
% Stages (chosen in a dialog when processed_data_files.mat already exists)
%   1. Load the raw CSV files in .\data. Each file is one pressing run on
%      one sensor. The file name gives the sensor, the start, increment and
%      stop mass in grams, and the run number.
%   2. Find the largest peak in two bin windows of every histogram frame.
%      The window 1 height is Peak 1's starting height and sets its +/-20%
%      height bounds. Frames with no peak in window 1 are not fitted.
%   3. Fit every frame as the sum of three master curves (master_curves.mat),
%      each scaled by a height and shifted by a position. Each frame starts
%      from the previous frame's fit (sequential seeding). The average time
%      per frame is printed at the end of this stage.
%   4. Interactive histogram player. Its Export Frame button saves the
%      current frame. Paper Figure 3 is File 1 in the included results
%      (..._20260310_163404_SensorA_Start60_Increment20_Stop220_Run1.csv),
%      row 195.
%   5. Run-by-run diagnostic figures (Plateau_*). Not used in the paper.
%   6. Box-and-whisker plots for each sensor (paper Figure 7).
%
% Stages 1 to 3 reprocess the raw data, take about 30 minutes and overwrite
% processed_data_files.mat. To reproduce the paper figures from the
% included results, select only stages 4 and 6.
%
% Requirements: MATLAB R2024a or later, Curve Fitting Toolbox and Signal
% Processing Toolbox. Figures are written to .\Figures by ExportFigure.m.

close all force
clear
clc

% Work in the folder that contains this script so relative paths resolve
scriptFolder = fileparts(mfilename('fullpath'));
if ~isempty(scriptFolder)
    cd(scriptFolder);
end

%% Settings %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dataFileMat = 'processed_data_files.mat';

% Exported figure size in inches
FigureWidth = 3.4;
FigureHeight_Plateau = 5.0;   % taller size for the stacked run-by-run figures

% MATLAB default colors for Peaks 1, 2 and 3
c1 = [0 0.4470 0.7410];      % blue
c2 = [0.8500 0.3250 0.0980]; % orange
c3 = [0.4660 0.6740 0.1880]; % green

% Box plots (stage 6). Whiskers end at the most extreme value within
% 1.5 times the interquartile range of the box. As in the published
% figures, values beyond the whiskers are not drawn (showOutliers = false).
% Set showOutliers to true to draw them as individual markers. Every value
% is used for the medians, quartiles and trend lines either way.
showOutliers = false;

% Legend position for each sensor's box plot
legendLocation = struct('A', 'west', 'B', 'northeast', 'C', 'east', 'D', 'east');

%% Stage Selection %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Without saved results, every stage runs. With saved results, a dialog
% asks which stages to run (stage 6 is preselected).
run_load = true;
run_peaks = true;
run_fit = true;
run_player = true;
run_plateaus = true;
run_boxplots = true;

if isfile(dataFileMat)
    fprintf('Loading previously saved data from %s...\n', dataFileMat);
    load(dataFileMat, 'data_files');

    list_str = { ...
        '1. Rescan and Load Raw Data (Full Reset)', ...
        '2. Recalculate Peaks', ...
        '3. Run Curve Fitting', ...
        '4. Launch Interactive Histogram Player (Figure 3)', ...
        '5. Generate Plateau Figures (Run-by-Run Diagnostics)', ...
        '6. Generate Box and Whisker Plots (Figure 7)' ...
    };

    [indx, tf] = listdlg('PromptString', {'Saved results found. Select stages to run.', ...
                                          'Stages 1-3 reprocess the raw data (about 30 min)', ...
                                          'and overwrite processed_data_files.mat.', ...
                                          'Stages 4-6 only read the saved results.', ...
                                          '(Hold Ctrl/Cmd to select multiple)'}, ...
                         'SelectionMode', 'multiple', ...
                         'ListString', list_str, ...
                         'InitialValue', 6, ...
                         'Name', 'Stage Selector', ...
                         'ListSize', [350, 150]);

    if ~tf
        disp('Operation cancelled by user. Exiting script.');
        return;
    end

    run_load     = ismember(1, indx);
    run_peaks    = ismember(2, indx);
    run_fit      = ismember(3, indx);
    run_player   = ismember(4, indx);
    run_plateaus = ismember(5, indx);
    run_boxplots = ismember(6, indx);

    % Later processing stages depend on earlier ones
    if run_load
        warning('Full reset selected. Forcing all downstream processing stages to run.');
        run_peaks = true;
        run_fit = true;
    elseif run_peaks && ~run_fit
        warning('Peaks are being recalculated. Forcing Curve Fitting to run to maintain data integrity.');
        run_fit = true;
    end
else
    fprintf('No saved data found. Running full pipeline...\n');
end

%% Stage 1: Load Raw Data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if run_load
    data_dir = fullfile(pwd, 'data');
    if ~isfolder(data_dir)
        error('Data directory not found: %s', data_dir);
    end
    files = dir(fullfile(data_dir, '*.csv'));
    num_files = numel(files);

    data_files = struct('filename', cell(num_files,1), 'filepath', cell(num_files,1), 'date', cell(num_files,1), ...
        'time', cell(num_files,1), 'sensor', cell(num_files,1), ...
        'start_mass', cell(num_files,1), 'increment_mass', cell(num_files,1), 'stop_mass', cell(num_files,1), ...
        'run', cell(num_files,1), 'raw_data', cell(num_files,1));

    % Test details appended to the GUI's default file name, for example
    % data_VL53L8CH__AIKit__CNH_4x4_ONECNH__20260310_163404_SensorA_Start60_Increment20_Stop220_Run1.csv
    pattern = [ ...
        '(?<prefix>.*)__' ...
        '(?<date>\d{8}|\d{4}[-]\d{1,2}[-]\d{1,2})_' ...
        '(?<time>\d{6}|[\d\-:]{4,8})_' ...
        'Sensor(?<sensor>[A-Za-z0-9]+)_' ...
        'Start(?<start>\d+\.?\d*)_' ...
        'Increment(?<inc>\d+\.?\d*)_' ...
        'Stop(?<stop>\d+\.?\d*)_' ...
        'Run(?<run>\d+)' ...
    ];

    fprintf('\n--- Loading Raw Data ---\n');
    for idx_file = 1:num_files
        filename = files(idx_file).name;
        filepath = fullfile(files(idx_file).folder, filename);

        data_files(idx_file).filename = filename;
        data_files(idx_file).filepath = filepath;

        tokens = regexp(filename, pattern, 'names', 'once');

        % Fallback parser for file names that do not match the pattern exactly
        if isempty(tokens)
            parts = regexp(filename(1:end-4), '_', 'split');
            tokens = struct('date','','time','','sensor','','start','','inc','','stop','','run','');

            date_idx = find(~cellfun(@isempty, regexp(parts, '^\d{8}$')) | ...
                ~cellfun(@isempty, regexp(parts, '^\d{4}-\d{1,2}-\d{1,2}$')), 1);
            if ~isempty(date_idx) && numel(parts) >= date_idx+1
                tokens.date = parts{date_idx};
                tokens.time = parts{date_idx+1};
            end

            sensor_idx = find(~cellfun(@isempty, regexp(parts, '^Sensor', 'once')), 1);
            if ~isempty(sensor_idx)
                tokens.sensor = regexprep(parts{sensor_idx}, '^Sensor', '');
            end

            for p = 1:numel(parts)
                if startsWith(parts{p}, 'Start', 'IgnoreCase', true)
                    tokens.start = regexprep(parts{p}, '[^\d\.]', '');
                elseif startsWith(parts{p}, 'Increment', 'IgnoreCase', true)
                    tokens.inc = regexprep(parts{p}, '[^\d\.]', '');
                elseif startsWith(parts{p}, 'Stop', 'IgnoreCase', true)
                    tokens.stop = regexprep(parts{p}, '[^\d\.]', '');
                elseif startsWith(parts{p}, 'Run', 'IgnoreCase', true)
                    tokens.run = regexprep(parts{p}, '[^\d\.]', '');
                end
            end
        end

        try
            if ~isempty(tokens.date)
                if ~isempty(regexp(tokens.date, '^\d{8}$', 'once'))
                    data_files(idx_file).date = datetime(tokens.date, 'InputFormat', 'yyyyMMdd');
                else
                    data_files(idx_file).date = datetime(tokens.date, 'InputFormat', 'yyyy-MM-dd');
                end
            end
        catch
            data_files(idx_file).date = [];
        end

        if ~isempty(tokens.time)
            tkn_norm = strrep(tokens.time, '-', ':');
            if ~isempty(regexp(tkn_norm, '^\d{6}$', 'once'))
                try data_files(idx_file).time = datetime(tkn_norm, 'InputFormat', 'HHmmss'); catch, data_files(idx_file).time = tokens.time; end
            else
                try data_files(idx_file).time = datetime(tkn_norm, 'InputFormat', 'HH:mm:ss');
                catch
                    try data_files(idx_file).time = datetime(tkn_norm, 'InputFormat', 'HH:mm');
                    catch, data_files(idx_file).time = tokens.time;
                    end
                end
            end
        end

        data_files(idx_file).sensor = tokens.sensor;
        data_files(idx_file).start_mass = str2double(tokens.start);
        data_files(idx_file).increment_mass = str2double(tokens.inc);
        data_files(idx_file).stop_mass = str2double(tokens.stop);
        data_files(idx_file).run = str2double(tokens.run);

        try
            data_files(idx_file).raw_data = read_every16th_from_cnh_start(filepath);
        catch ME
            warning('Failed to read file %s: %s', filename, ME.message);
            data_files(idx_file).raw_data = [];
        end
    end
end

%% Stage 2: Find Peaks %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Largest peak in each of two bin windows (bin numbers start at 0). Window 1
% (bins 60-75) holds Peak 1. Window 2 (bins 99-110) lies outside the three
% fitted paths. Only the window 1 height is used later, as the starting
% height and bounds for Peak 1. Widths and prominences are stored for
% inspection only.
if run_peaks
    fprintf('\n--- Finding Peaks ---\n');
    minHeight = 1;
    peakRange1 = [60 75];
    peakRange2 = [99 110];
    for idx_file = 1:numel(data_files)
        tbl = data_files(idx_file).raw_data;
        if isempty(tbl) || ~istable(tbl), continue; end

        mat = tbl{:,2:end};   % column 1 is time; the rest are histogram bins 0-143
        if isempty(mat), continue; end

        % Convert the 0-based bin windows to 1-based column indices
        n_bins_total = size(mat,2);
        pr1_s = max(1, round(peakRange1(1)) + 1);
        pr1_e = min(n_bins_total, round(peakRange1(2)) + 1);
        pr2_s = max(1, round(peakRange2(1)) + 1);
        pr2_e = min(n_bins_total, round(peakRange2(2)) + 1);
        ranges = [pr1_s pr1_e; pr2_s pr2_e];

        n_rows = size(mat,1);
        H = NaN(n_rows, 2);   % height
        L = NaN(n_rows, 2);   % location (0-based bin)
        W = NaN(n_rows, 2);   % width
        P = NaN(n_rows, 2);   % prominence

        for r = 1:n_rows
            rowdat = mat(r,:);
            if ~isnumeric(rowdat) || ~isvector(rowdat), continue; end

            for w_idx = 1:2
                sbin = ranges(w_idx,1); ebin = ranges(w_idx,2);
                if sbin <= ebin && sbin >= 1 && ebin <= n_bins_total
                    window = rowdat(sbin:ebin);
                    try [pks, locs_rel, w, p] = findpeaks(window, 'MinPeakHeight', minHeight); catch, pks = []; end
                    if ~isempty(pks)
                        [~, idx_maxh] = max(pks);
                        H(r,w_idx) = pks(idx_maxh);
                        L(r,w_idx) = locs_rel(idx_maxh) + (sbin-1) - 1;
                        W(r,w_idx) = w(idx_maxh);
                        P(r,w_idx) = p(idx_maxh);
                    end
                end
            end
        end

        peakNames = {'Peak1','Peak2'};
        data_files(idx_file).peaks_height = array2table(H, 'VariableNames', peakNames);
        data_files(idx_file).peaks_location = array2table(L, 'VariableNames', peakNames);
        data_files(idx_file).peaks_width = array2table(W, 'VariableNames', peakNames);
        data_files(idx_file).peaks_prominence = array2table(P, 'VariableNames', peakNames);
    end
    report_missing_peaks(data_files)
end

%% Stage 3: Curve Fitting with Sequential Seeding %%%%%%%%%%%%%%%%%%%%%%%%%%
% Model: S(x) = sum over i of h_i * M_i(x - p_i), with x the 0-based bin,
% M_i the master curve of path i, h_i its height and p_i its position.
% Nonlinear least squares (fit, default trust-region-reflective) with the
% bounds set in peak_guess below.
if run_fit
    fprintf('\n--- Starting Curve Fitting ---\n');

    % Time the fitting stage (reported as average time per frame)
    total_fit_frames = 0;
    fit_timer = tic;

    if ~isfile('master_curves.mat')
        error('master_curves.mat not found. Run SinglePeakTester.m (stage 2) in 2026-03-20_NetworkPeakLocationTests and copy its master_curves.mat into this folder.');
    end
    load('master_curves.mat', 'master_curves');

    fun = @(height1, position1, height2, position2, height3, position3, x) ...
        height1 * master_curves.Peak1(x - position1) + ...
        height2 * master_curves.Peak2(x - position2) + ...
        height3 * master_curves.Peak3(x - position3);

    fitfun = fittype(fun);

    % Initial guesses and bounds for every frame
    for idx_file = 1:numel(data_files)
        data_files(idx_file).initial_peak_guesses = [];
        data_files(idx_file).lower_bounds = [];
        data_files(idx_file).upper_bounds = [];

        req_fields = {'peaks_height', 'peaks_location', 'peaks_width', 'peaks_prominence'};
        if ~all(isfield(data_files(idx_file), req_fields)), continue; end
        if isempty(data_files(idx_file).peaks_height), continue; end

        try
            [ig, lb, ub] = peak_guess(data_files(idx_file).peaks_height);
            data_files(idx_file).initial_peak_guesses = ig;
            data_files(idx_file).lower_bounds = lb;
            data_files(idx_file).upper_bounds = ub;
        catch ME
            warning('peak_guess failed for file %d: %s', idx_file, ME.message);
        end
    end

    fopts = fitoptions('Method', 'NonlinearLeastSquares', 'Display', 'Off');
    cnames = coeffnames(fitfun);

    for idx_file = 1:numel(data_files)
        if isempty(data_files(idx_file).raw_data) || isempty(data_files(idx_file).initial_peak_guesses)
            data_files(idx_file).fit_parameters = [];
            continue;
        end

        fprintf('Fitting file %d / %d: %s\n', idx_file, numel(data_files), data_files(idx_file).filename);

        tbl = data_files(idx_file).raw_data;
        data_mat = tbl{:, 2:end};
        [n_rows, n_bins] = size(data_mat);
        xdata = (0:(n_bins-1))';

        total_fit_frames = total_fit_frames + n_rows;

        ig_arr = table2array(data_files(idx_file).initial_peak_guesses(:, cnames));
        lb_arr = table2array(data_files(idx_file).lower_bounds(:, cnames));
        ub_arr = table2array(data_files(idx_file).upper_bounds(:, cnames));
        fit_params_arr = NaN(n_rows, numel(cnames));

        reverseStr = '';
        for r = 1:n_rows
            if mod(r, 10) == 0 || r == 1 || r == n_rows
                msg = sprintf('  Processing row %d / %d', r, n_rows);
                fprintf([reverseStr, msg]);
                reverseStr = repmat(sprintf('\b'), 1, length(msg));
            end

            if any(isnan(ig_arr(r, :))), continue; end

            ydata = data_mat(r, :)';

            % Start from the previous frame's fit when it exists
            if r == 1 || any(isnan(fit_params_arr(r-1, :)))
                current_guess = ig_arr(r, :);
            else
                current_guess = fit_params_arr(r-1, :);
            end

            % Keep the starting point inside this frame's bounds
            current_guess = max(current_guess, lb_arr(r, :));
            current_guess = min(current_guess, ub_arr(r, :));

            fopts.StartPoint = current_guess;
            fopts.Lower      = lb_arr(r, :);
            fopts.Upper      = ub_arr(r, :);

            try
                fitted_model = fit(xdata, ydata, fitfun, fopts);
                fit_params_arr(r, :) = coeffvalues(fitted_model);
            catch
                % A failed fit leaves NaN for this frame
            end
        end
        fprintf('\n');
        data_files(idx_file).fit_parameters = array2table(fit_params_arr, 'VariableNames', cnames);
    end

    total_fit_time = toc(fit_timer);
    if total_fit_frames > 0
        avg_time_per_frame = total_fit_time / total_fit_frames;
        fprintf('\n==================================================\n');
        fprintf('   CURVE FITTING PERFORMANCE REPORT\n');
        fprintf('==================================================\n');
        fprintf('Total Computation Time: %.2f seconds\n', total_fit_time);
        fprintf('Total Frames Fitted:    %d frames\n', total_fit_frames);
        fprintf('Average Time Per Frame: %.4f seconds/frame\n', avg_time_per_frame);
        fprintf('==================================================\n\n');
    end
end

%% Save Processed Data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Only runs when stages 1-3 ran. Plotting stages never write this file.
if run_load || run_peaks || run_fit
    fprintf('\nSaving processed data to %s...\n', dataFileMat);
    save(dataFileMat, 'data_files', '-v7.3');
    fprintf('Save complete.\n');
end

%% Stage 4: Histogram Player %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if run_player
    fprintf('\nLaunching Interactive Histogram Player...\n');
    interactive_histogram_player(data_files, 1, FigureWidth, c1, c2, c3)
end

%% Normalize Fitted Heights %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Each height is divided by the largest fitted value of that peak among all
% runs of the same sensor, so that largest value becomes 1.
if run_plateaus || run_boxplots
    fprintf('\n--- Normalizing Data Across Sensors ---\n');

    [data_files.normalized_fit_parameters] = deal([]);

    valid_idx = arrayfun(@(s) isfield(s, 'fit_parameters') && ~isempty(s.fit_parameters), data_files);
    valid_files = data_files(valid_idx);

    unique_sensors = unique({valid_files.sensor});
    sensor_max = containers.Map('KeyType', 'char', 'ValueType', 'any');

    for s = 1:numel(unique_sensors)
        sens = unique_sensors{s};
        max_h1 = 0; max_h2 = 0; max_h3 = 0;
        for i = 1:numel(valid_files)
            if strcmp(valid_files(i).sensor, sens)
                tbl = valid_files(i).fit_parameters;
                max_h1 = max([max_h1; tbl.height1]);
                max_h2 = max([max_h2; tbl.height2]);
                max_h3 = max([max_h3; tbl.height3]);
            end
        end
        if max_h1 == 0, max_h1 = 1; end
        if max_h2 == 0, max_h2 = 1; end
        if max_h3 == 0, max_h3 = 1; end
        sensor_max(sens) = [max_h1, max_h2, max_h3];
    end

    for i = 1:numel(data_files)
        if valid_idx(i)
            sens = data_files(i).sensor;
            max_vals = sensor_max(sens);
            tbl = data_files(i).fit_parameters;

            data_files(i).normalized_fit_parameters = table(...
                tbl.height1 / max_vals(1), tbl.position1, ...
                tbl.height2 / max_vals(2), tbl.position2, ...
                tbl.height3 / max_vals(3), tbl.position3, ...
                'VariableNames', {'norm_height1','position1','norm_height2','position2','norm_height3','position3'});
        end
    end
end

%% Stage 5: Run-by-Run Plateau Figures (diagnostics) %%%%%%%%%%%%%%%%%%%%%%%%
if run_plateaus
    fprintf('\n--- Generating Run-by-Run Plateau Figures ---\n');

    for i = 1:numel(data_files)
        df = data_files(i);
        if isempty(df.normalized_fit_parameters) || isempty(df.raw_data), continue; end

        time_sec = df.raw_data{:, 1};
        h1 = df.normalized_fit_parameters.norm_height1;
        h2 = df.normalized_fit_parameters.norm_height2;
        h3 = df.normalized_fit_parameters.norm_height3;

        p1 = df.normalized_fit_parameters.position1;
        p2 = df.normalized_fit_parameters.position2;
        p3 = df.normalized_fit_parameters.position3;

        % The 6th output is the filtered signal
        [b1, v1, t1, ~, ~, f1] = extract_plateaus(time_sec, h1);
        [b2, v2, t2, ~, ~, f2] = extract_plateaus(time_sec, h2);
        [b3, v3, t3, ~, ~, f3] = extract_plateaus(time_sec, h3);

        title_str = sprintf('Sensor %s | Start: %gg | Inc: %gg | Stop: %gg | Run %d', ...
            df.sensor, df.start_mass, df.increment_mass, df.stop_mass, df.run);

        fig = figure('Name', sprintf('Plateau Data - Run %d - Sensor %s', df.run, df.sensor), ...
            'Color', 'w', 'Units', 'normalized', 'Position', [0.1 0.1 0.6 0.8]);

        tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
        title(tl, title_str, 'FontWeight', 'bold', 'FontSize', 14, 'Color', 'k');

        ax1 = nexttile(tl);
        hold(ax1, 'on');

        % Raw normalized heights, faded
        plot(ax1, time_sec, h1, '-', 'Color', [c1 0.3], 'LineWidth', 1.0, 'DisplayName', 'Peak 1 (Raw)');
        plot(ax1, time_sec, h2, '-', 'Color', [c2 0.3], 'LineWidth', 1.0, 'DisplayName', 'Peak 2 (Raw)');
        plot(ax1, time_sec, h3, '-', 'Color', [c3 0.3], 'LineWidth', 1.0, 'DisplayName', 'Peak 3 (Raw)');

        % Moving-median filtered heights
        if ~isempty(f1), plot(ax1, time_sec, f1, '-', 'Color', c1, 'LineWidth', 1.5, 'DisplayName', 'Peak 1 (Filtered)'); end
        if ~isempty(f2), plot(ax1, time_sec, f2, '-', 'Color', c2, 'LineWidth', 1.5, 'DisplayName', 'Peak 2 (Filtered)'); end
        if ~isempty(f3), plot(ax1, time_sec, f3, '-', 'Color', c3, 'LineWidth', 1.5, 'DisplayName', 'Peak 3 (Filtered)'); end

        % Baselines (dotted)
        plot(ax1, [time_sec(1), time_sec(end)], [b1, b1], ':', 'Color', c1, 'LineWidth', 2, 'HandleVisibility', 'off');
        plot(ax1, [time_sec(1), time_sec(end)], [b2, b2], ':', 'Color', c2, 'LineWidth', 2, 'HandleVisibility', 'off');
        plot(ax1, [time_sec(1), time_sec(end)], [b3, b3], ':', 'Color', c3, 'LineWidth', 2, 'HandleVisibility', 'off');

        % Detected loading steps (thick bars)
        for k=1:length(v1), plot(ax1, t1(k,:), [v1(k), v1(k)], '-', 'Color', c1, 'LineWidth', 4, 'HandleVisibility', 'off'); end
        for k=1:length(v2), plot(ax1, t2(k,:), [v2(k), v2(k)], '-', 'Color', c2, 'LineWidth', 4, 'HandleVisibility', 'off'); end
        for k=1:length(v3), plot(ax1, t3(k,:), [v3(k), v3(k)], '-', 'Color', c3, 'LineWidth', 4, 'HandleVisibility', 'off'); end

        ylabel(ax1, 'Normalized Amplitude');
        grid(ax1, 'off');
        legend(ax1, 'Location', 'best');
        set(ax1, 'FontSize', 11, 'Box', 'off', 'XGrid', 'off', 'YGrid', 'off', 'XColor', 'k', 'YColor', 'k');

        ax2 = nexttile(tl);
        hold(ax2, 'on');
        plot(ax2, time_sec, p1, '-', 'Color', c1, 'LineWidth', 1.5);
        plot(ax2, time_sec, p2, '-', 'Color', c2, 'LineWidth', 2.5);
        plot(ax2, time_sec, p3, '--', 'Color', c3, 'LineWidth', 1.5);
        xlabel(ax2, 'Time (seconds)');
        ylabel(ax2, 'Location (Bin Number)');
        grid(ax2, 'off');
        set(ax2, 'FontSize', 11, 'Box', 'off', 'XGrid', 'off', 'YGrid', 'off', 'XColor', 'k', 'YColor', 'k');

        linkaxes([ax1, ax2], 'x');

        savename = sprintf('Plateau_Sensor%s_Run%d', df.sensor, df.run);
        ExportFigure(fig, savename, FigureWidth, FigureHeight_Plateau);
    end
end

%% Stage 6: Box and Whisker Plots (Figure 7) %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% For each run, the loading steps are found on the sensor's primary peak
% (Peak 1 for Sensor A, Peak 2 for Sensors B and D, Peak 3 for Sensor C).
% A run is used only if the number of detected steps equals the number of
% applied masses; other runs are listed as rejected in the Command Window.
% Within each step window, every peak's value is the median of its
% normalized height. The 0 g value is the baseline from extract_plateaus
% (95th percentile of the 3 s moving median), which follows the unloaded
% signal for peaks that drop under load. Peak 3 of Sensor A rises under
% load, so its 0 g value follows the loaded signal instead.
if run_boxplots
    fprintf('\n--- Generating Aggregated Box and Whisker Plots ---\n');

    unique_sensors = unique({data_files(arrayfun(@(s) ~isempty(s.normalized_fit_parameters), data_files)).sensor});

    for s = 1:numel(unique_sensors)
        sens = unique_sensors{s};
        fprintf('\n==================================================\n');
        fprintf('   AGGREGATION REPORT: SENSOR %s\n', sens);
        fprintf('==================================================\n');

        plot_masses = [];
        plot_amps   = [];
        plot_groups = categorical([]);

        rej_runs = {};
        n_runs_total = 0;
        n_runs_used = 0;

        for i = 1:numel(data_files)
            df = data_files(i);
            if ~strcmp(df.sensor, sens) || isempty(df.normalized_fit_parameters), continue; end
            n_runs_total = n_runs_total + 1;

            mass_sequence = df.start_mass : df.increment_mass : df.stop_mass;
            expected_drops = length(mass_sequence);

            time_sec = df.raw_data{:, 1};
            h1 = df.normalized_fit_parameters.norm_height1;
            h2 = df.normalized_fit_parameters.norm_height2;
            h3 = df.normalized_fit_parameters.norm_height3;

            % 1. Primary peak for this sensor
            switch upper(sens)
                case 'A'
                    primary_h = h1;
                case {'B', 'D'}
                    primary_h = h2;
                case 'C'
                    primary_h = h3;
                otherwise
                    warning('Unknown sensor %s. Defaulting to Peak 1 for timing.', sens);
                    primary_h = h1;
            end

            % 2. Step windows from the primary peak only
            [~, ~, t_steps, s_prim, l_prim] = extract_plateaus(time_sec, primary_h);

            % Baselines for all peaks give the 0 g values
            b1 = extract_plateaus(time_sec, h1);
            b2 = extract_plateaus(time_sec, h2);
            b3 = extract_plateaus(time_sec, h3);

            num_steps = size(t_steps, 1);

            % 3. Use the run only if the step count matches the number of masses
            if num_steps == expected_drops
                n_runs_used = n_runs_used + 1;
                v1_synced = zeros(1, num_steps);
                v2_synced = zeros(1, num_steps);
                v3_synced = zeros(1, num_steps);

                for k = 1:num_steps
                    t_start = t_steps(k, 1);
                    t_stop  = t_steps(k, 2);

                    % Frames inside this step window
                    idx_window = (time_sec >= t_start) & (time_sec <= t_stop);

                    % Median of each peak within the same window
                    v1_synced(k) = median(h1(idx_window), 'omitnan');
                    v2_synced(k) = median(h2(idx_window), 'omitnan');
                    v3_synced(k) = median(h3(idx_window), 'omitnan');
                end

                plot_masses = [plot_masses; 0; mass_sequence'];
                plot_amps   = [plot_amps; b1; v1_synced'];
                plot_groups = [plot_groups; repmat(categorical({'Peak 1'}), expected_drops + 1, 1)];

                plot_masses = [plot_masses; 0; mass_sequence'];
                plot_amps   = [plot_amps; b2; v2_synced'];
                plot_groups = [plot_groups; repmat(categorical({'Peak 2'}), expected_drops + 1, 1)];

                plot_masses = [plot_masses; 0; mass_sequence'];
                plot_amps   = [plot_amps; b3; v3_synced'];
                plot_groups = [plot_groups; repmat(categorical({'Peak 3'}), expected_drops + 1, 1)];
            else
                rej_runs{end+1} = sprintf('Run %d (Found %d/%d valid on primary peak | Rejected: %d short, %d long)', ...
                                           df.run, num_steps, expected_drops, s_prim, l_prim); %#ok<SAGROW>
            end
        end

        fprintf('  Runs used: %d of %d\n', n_runs_used, n_runs_total);
        if isempty(rej_runs)
            fprintf('  All runs accepted and synchronized successfully!\n');
        else
            fprintf('  Rejected Runs:\n');
            for r = 1:length(rej_runs)
                fprintf('      - %s\n', rej_runs{r});
            end
        end

        if isempty(plot_masses)
            fprintf('  -> No valid data to plot for Sensor %s.\n', sens);
            continue;
        end

        fig = figure('Name', sprintf('Aggregated Pressure Response - Sensor %s', sens), ...
            'Color', 'w', 'Units', 'normalized', 'Position', [0.15 0.15 0.7 0.7]);

        % Axes leave the top of the figure free for the trend-line equations
        ax = axes('Parent', fig, 'Position', [0.15 0.15 0.75 0.65]);
        hold(ax, 'on');

        b = boxchart(plot_masses, plot_amps, 'GroupByColor', plot_groups);
        for j = 1:numel(b)
            b(j).LineWidth = 1.5;
            if showOutliers
                b(j).MarkerStyle = 'o';
                b(j).MarkerSize = 4;
            else
                b(j).MarkerStyle = 'none';
            end
        end
        colororder(ax, [c1; c2; c3]);

        unique_masses = unique(plot_masses);
        set(ax, 'XTick', unique_masses);

        xlabel(ax, 'Applied Mass (grams)', 'FontWeight', 'bold');
        ylabel(ax, 'Normalized Amplitude', 'FontWeight', 'bold');

        grid(ax, 'off');
        set(ax, 'FontSize', 12, 'Box', 'off', 'XGrid', 'off', 'YGrid', 'off');
        if isfield(legendLocation, sens)
            legend(ax, 'Location', legendLocation.(sens));
        else
            legend(ax, 'Location', 'best');
        end

        % Linear trend line through the median of each box, per peak
        peak_labels = {'Peak 1', 'Peak 2', 'Peak 3'};
        colors = {c1, c2, c3};
        equations = {};

        for p = 1:3
            lbl = peak_labels{p};
            med_vals = NaN(size(unique_masses));
            for m = 1:length(unique_masses)
                mass_val = unique_masses(m);
                idx = (plot_masses == mass_val) & (plot_groups == lbl);
                if any(idx), med_vals(m) = median(plot_amps(idx)); end
            end

            valid_fit_idx = ~isnan(med_vals);
            if sum(valid_fit_idx) > 1
                poly_coeff = polyfit(unique_masses(valid_fit_idx), med_vals(valid_fit_idx), 1);
                trend_line = polyval(poly_coeff, unique_masses);
                plot(ax, unique_masses, trend_line, '--', 'Color', colors{p}, 'LineWidth', 2, 'HandleVisibility', 'off');

                slope = poly_coeff(1);
                intercept = poly_coeff(2);

                sign_str = '+';
                if intercept < 0
                    sign_str = '-';
                end

                % '% .1e' pads positive numbers with a space so the columns line up
                equations{end+1} = sprintf('%s: y = % .1e x %s %.1e', lbl, slope, sign_str, abs(intercept)); %#ok<SAGROW>
            end
        end

        if ~isempty(equations)
            eq_text = strjoin(equations, '\n');

            % Equations go in the space above the axes
            annotation(fig, 'textbox', [0.05 0.82 0.90 0.15], 'String', eq_text, ...
                'FitBoxToText', 'off', 'BackgroundColor', 'none', 'EdgeColor', 'none', ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                'FontSize', 11, 'FontName', 'Courier');
        end

        savename = sprintf('AggregatedResponse_Sensor%s', sens);
        ExportFigure(fig, savename, FigureWidth);
    end
end

%% Local Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [baseline, step_vals, step_times, short_count, long_count, y_filt] = extract_plateaus(time_sec, y_raw)
%EXTRACT_PLATEAUS Find the loading steps in one normalized height trace.
%   The trace is smoothed with a 3 s moving median. The baseline is the
%   95th percentile of the smoothed trace. A step is any stretch below
%   baseline - 0.15*(baseline - 5th percentile) that lasts 2.8 to 20 s.
%   Each step's value is the median of the middle half of the step.
%   Shorter and longer stretches are counted and rejected.

    filter_window_sec = 3.0;

    dt = median(diff(time_sec));
    if isnan(dt) || dt == 0, dt = 1; end
    window_samples = max(3, round(filter_window_sec / dt));

    y_filt = movmedian(y_raw, window_samples);

    baseline = prctile(y_filt, 95);
    signal_range = baseline - prctile(y_filt, 5);

    short_count = 0;
    long_count = 0;

    % No clear steps if the trace varies by less than 5% of the baseline
    if signal_range < 0.05 * baseline
        step_vals = []; step_times = []; return;
    end

    threshold = baseline - 0.15 * signal_range;

    is_drop = y_filt < threshold;
    edges = diff([0; is_drop; 0]);
    starts = find(edges == 1);
    stops = find(edges == -1) - 1;

    step_vals = []; step_times = [];

    min_duration = 2.8;
    max_duration = 20.0;

    for k = 1:length(starts)
        idx_start = starts(k); idx_stop = stops(k);
        duration = time_sec(idx_stop) - time_sec(idx_start);

        if duration < min_duration
            short_count = short_count + 1;
        elseif duration > max_duration
            long_count = long_count + 1;
        else
            % Middle half of the step, away from the loading transitions
            q_len = round((idx_stop - idx_start) / 4);
            s_start = idx_start + q_len; s_stop  = idx_stop - q_len;
            if s_stop < s_start, s_start = idx_start; s_stop = idx_stop; end

            step_vals(end+1) = median(y_filt(s_start:s_stop)); %#ok<AGROW>
            step_times(end+1, :) = [time_sec(s_start), time_sec(s_stop)]; %#ok<AGROW>
        end
    end
end

function table_out = read_every16th_from_cnh_start(fullpath)
%READ_EVERY16TH_FROM_CNH_START Read the histogram from one GUI log file.
%   The MZ-AI GUI writes 16 aggregate columns for every histogram bin
%   (cnh__hist_bin_<bin>_a0 ... _a15). With all SPAD zones merged into one
%   1x1 zone, only aggregate a0 holds data, so every 16th column is kept.
%   Output: a table whose first column is time in seconds from the first
%   frame (from the HostTimestamp column), followed by the histogram bins.
%   Rows with more than half of their values missing are removed.

    import_opts = detectImportOptions(fullpath,'Delimiter',',');
    table_in = readtable(fullpath, import_opts);
    variable_names = table_in.Properties.VariableNames;

    start_column_idx = find(strcmp(variable_names,'cnh__hist_bin_0_a0'),1);
    if isempty(start_column_idx)
        error('Column named ''cnh__hist_bin_0_a0'' not found in the file.');
    end

    lower_names = lower(variable_names);
    timestamp_idx = find(contains(lower_names,'hosttimestamp'),1);

    if isempty(timestamp_idx)
        error('Timestamp column containing ''hosttimestamp'' not found.');
    end

    selected_columns = start_column_idx:16:numel(variable_names);
    table_out = table_in(:, selected_columns);

    timestamp_values = table_in{:, timestamp_idx};
    if isdatetime(timestamp_values) || isduration(timestamp_values)
        timestamp_seconds = seconds(timestamp_values - timestamp_values(1));
    elseif iscellstr(timestamp_values) || isstring(timestamp_values)
        try
            dt_vals = datetime(timestamp_values);
            timestamp_seconds = seconds(dt_vals - dt_vals(1));
        catch
            numeric_vals = str2double(timestamp_values);
            timestamp_seconds = numeric_vals - numeric_vals(1);
        end
    else
        timestamp_seconds = timestamp_values - timestamp_values(1);
    end

    timestamp_name = variable_names{timestamp_idx};
    table_out = addvars(table_out, timestamp_seconds, 'Before', 1, 'NewVariableNames', timestamp_name);

    nanCounts = sum(ismissing(table_out), 2);
    threshold = floor(width(table_out) / 2);
    table_out(nanCounts > threshold, :) = [];
end

function report_missing_peaks(data_files)
%REPORT_MISSING_PEAKS Print, for each file, how many frames had no peak in each window.
    foundAny = false;
    for fi = 1:numel(data_files)
        df = data_files(fi);
        if ~isfield(df, 'peaks_location') || isempty(df.peaks_location), continue; end

        tbl = df.peaks_location;
        if ~ismember('Peak1', tbl.Properties.VariableNames) || ~ismember('Peak2', tbl.Properties.VariableNames)
            continue;
        end

        rows_with_nan1 = find(isnan(tbl.Peak1));
        rows_with_nan2 = find(isnan(tbl.Peak2));

        if ~isempty(rows_with_nan1) || ~isempty(rows_with_nan2)
            foundAny = true;
            fprintf('File %d: no peak in window 1 for %d frames, no peak in window 2 for %d frames\n', ...
                fi, numel(rows_with_nan1), numel(rows_with_nan2));
        end
    end
    if ~foundAny
        fprintf('No missing peaks found in any peaks_location tables.\n');
    end
end

function [initial_peak_guesses, lower_bounds, upper_bounds] = peak_guess(peaks_height)
%PEAK_GUESS Initial guesses and bounds for the pressing fits.
%   Each position is held in a fixed narrow window (bins), since pressing
%   is not expected to change path length. Peak 1's height is held within
%   20% of the largest value found in window 1 of that frame. Peak 2 and
%   Peak 3 heights only need to be non-negative.
    N = height(peaks_height);
    varNames = {'height1','position1','height2','position2','height3','position3'};

    initial_peak_guesses = array2table(nan(N,6), 'VariableNames', varNames);
    lower_bounds         = array2table(nan(N,6), 'VariableNames', varNames);
    upper_bounds         = array2table(nan(N,6), 'VariableNames', varNames);

    initial_peak_guesses.height1   = peaks_height.Peak1;
    initial_peak_guesses.position1 = repmat(66.48, N, 1);

    lower_bounds.height1   = peaks_height.Peak1 * 0.8;
    lower_bounds.position1 = repmat(66.14, N, 1);

    upper_bounds.height1   = peaks_height.Peak1 * 1.2;
    upper_bounds.position1 = repmat(66.58, N, 1);

    initial_peak_guesses.height2   = repmat(600, N, 1);
    initial_peak_guesses.height3   = repmat(40, N, 1);
    initial_peak_guesses.position2 = repmat(82.74, N, 1);
    initial_peak_guesses.position3 = repmat(86.65, N, 1);

    lower_bounds.height2   = zeros(N, 1);
    lower_bounds.height3   = zeros(N, 1);
    lower_bounds.position2 = repmat(82.68, N, 1);
    lower_bounds.position3 = repmat(86.58, N, 1);

    upper_bounds.height2   = inf(N, 1);
    upper_bounds.height3   = inf(N, 1);
    upper_bounds.position2 = repmat(82.89, N, 1);
    upper_bounds.position3 = repmat(86.84, N, 1);
end

function fig = interactive_histogram_player(data_files, idx_file, FigureWidth, c1, c2, c3)
%INTERACTIVE_HISTOGRAM_PLAYER Browse histogram frames and their fits.
%   Slider or arrow keys: change frame. File #: change file. L: toggle log
%   y-axis. Export Frame: save the current frame to .\Figures in the style
%   of paper Figure 3 (File 1, row 195 is the published frame).
    if nargin<2, error('Must provide data_files and idx_file.'); end
    if nargin<3, FigureWidth = 3.4; end

    bg_color = [0.94 0.94 0.94];
    ax_color = [1 1 1];
    ui_bg = [1 1 1];
    text_color = 'k';

    fig = figure('Name', 'Histogram Player', 'NumberTitle','off', 'Color', bg_color);
    ax = axes('Parent', fig, 'Color', ax_color, 'XColor', text_color, 'YColor', text_color);
    hold(ax, 'on');
    xlabel(ax, 'Bin Number', 'Color', text_color);
    ylabel(ax, 'Signal Amplitude (kcps)', 'Color', text_color);

    top_margin = 0.93; edit_w = 0.08; edit_h = 0.04; edit_x = 0.88; edit_y = top_margin - edit_h;

    uicontrol('Parent', fig, 'Style','text', 'Units','normalized', 'Position', [edit_x-0.07, edit_y, 0.07, edit_h], 'String','File #', 'HorizontalAlignment','right', 'BackgroundColor', bg_color, 'ForegroundColor', text_color);
    file_edit = uicontrol('Parent', fig, 'Style','edit', 'Units','normalized', 'Position', [edit_x, edit_y, edit_w, edit_h], 'String', num2str(idx_file), 'BackgroundColor', ui_bg, 'ForegroundColor', text_color, 'Callback', @(src,ev) fileEditCallback());
    sld = uicontrol('Parent', fig, 'Style','slider', 'Units','normalized', 'Position', [0.15 0.02 0.6 0.05], 'Min',1, 'Max',1, 'Value',1, 'BackgroundColor', bg_color);
    idx_txt = uicontrol('Parent', fig, 'Style','text', 'Units','normalized', 'Position', [0.88 0.02 0.1 0.05], 'String','1', 'HorizontalAlignment','left', 'BackgroundColor', bg_color, 'ForegroundColor', text_color);
    scale_chk = uicontrol('Parent', fig, 'Style','checkbox', 'Units','normalized', 'Position', [0.76 0.02 0.1 0.05], 'String','Log Y', 'Value', 1, 'BackgroundColor', bg_color, 'ForegroundColor', text_color);

    uicontrol('Parent', fig, 'Style','text', 'Units','normalized', 'Position', [0.02, edit_y, 0.05, edit_h], 'String','Y-Min:', 'HorizontalAlignment','right', 'BackgroundColor', bg_color, 'ForegroundColor', text_color);
    ymin_edit = uicontrol('Parent', fig, 'Style','edit', 'Units','normalized', 'Position', [0.08, edit_y, 0.06, edit_h], 'String', '1', 'BackgroundColor', ui_bg, 'ForegroundColor', text_color, 'Callback', @(src,ev) manualYLimCallback());
    uicontrol('Parent', fig, 'Style','text', 'Units','normalized', 'Position', [0.15, edit_y, 0.05, edit_h], 'String','Y-Max:', 'HorizontalAlignment','right', 'BackgroundColor', bg_color, 'ForegroundColor', text_color);
    ymax_edit = uicontrol('Parent', fig, 'Style','edit', 'Units','normalized', 'Position', [0.21, edit_y, 0.06, edit_h], 'String', '100', 'BackgroundColor', ui_bg, 'ForegroundColor', text_color, 'Callback', @(src,ev) manualYLimCallback());
    uicontrol('Parent', fig, 'Style','pushbutton', 'Units','normalized', 'Position', [0.28, edit_y, 0.06, edit_h], 'String','Auto Y', 'BackgroundColor', [0.85 0.85 0.85], 'ForegroundColor', text_color, 'Callback', @(src,ev) autoYCallback());

    uicontrol('Parent', fig, 'Style','pushbutton', 'Units','normalized', 'Position', [0.35, edit_y, 0.1, edit_h], 'String','Export Frame', 'BackgroundColor', [0.85 0.85 0.85], 'ForegroundColor', text_color, 'Callback', @(src,ev) exportFrameCallback());

    hLine     = plot(ax, nan, nan, 'k-o', 'MarkerSize',4, 'MarkerFaceColor','k', 'DisplayName','Raw Data');
    hFitTotal = plot(ax, nan, nan, '-', 'Color', [0.3 0.3 0.3], 'LineWidth', 2, 'DisplayName','Total Fit');
    hFit1     = plot(ax, nan, nan, '-', 'Color', c1, 'LineWidth', 1.5, 'DisplayName','Peak 1');
    hFit2     = plot(ax, nan, nan, '-', 'Color', c2, 'LineWidth', 2.5, 'DisplayName','Peak 2');
    hFit3     = plot(ax, nan, nan, '--', 'Color', c3, 'LineWidth', 1.5, 'DisplayName','Peak 3');
    hPeaks    = plot(ax, nan, nan, 'r^', 'MarkerFaceColor','r', 'MarkerSize',8, 'DisplayName','Initial Peaks');

    lgd = legend(ax, 'show', 'Location', 'northeast');
    set(lgd, 'TextColor', text_color, 'Color', ax_color, 'EdgeColor', [0.8 0.8 0.8]);
    t = title(ax, '', 'Color', text_color);

    state.data_files = data_files; state.idx_file = idx_file; state.isLogScale = true; state.auto_y = true;

    try
        tmp = load('master_curves.mat', 'master_curves');
        state.master_curves = tmp.master_curves;
        state.canDrawFits = true;
    catch
        state.master_curves = [];
        state.canDrawFits = false;
        warning('Could not load master_curves.mat. Fitted curves cannot be drawn.');
    end

    addlistener(sld, 'Value', 'PostSet', @(~,~) sliderCallback()); set(fig, 'KeyPressFcn', @keyPressFcn); set(scale_chk, 'Callback', @(~,~) toggleScale());
    loadFile(idx_file); sliderCallback();

    function ok = validateFileIndex(val), ok = isnumeric(val) && isscalar(val) && val>=1 && val<=numel(state.data_files) && (floor(val)==val); end

    function applyYLimits()
        ymax_data = max(state.data_mat(:)); if isempty(ymax_data) || isnan(ymax_data) || ymax_data <= 0, ymax_data = 1; end
        if state.auto_y
            ymin_val = 0; if state.isLogScale, ymin_val = 1; end
            ymax_val = max(ymin_val + 1e-6, ymax_data);
            set(ymin_edit, 'String', num2str(ymin_val)); set(ymax_edit, 'String', num2str(ymax_val));
        else
            ymin_val = str2double(get(ymin_edit, 'String')); ymax_val = str2double(get(ymax_edit, 'String'));
        end
        if state.isLogScale, set(ax, 'YScale', 'log', 'YLim', [ymin_val, ymax_val]); else, set(ax, 'YScale', 'linear', 'YLim', [ymin_val, ymax_val]); end
    end

    function manualYLimCallback()
        y_min_in = str2double(get(ymin_edit, 'String')); y_max_in = str2double(get(ymax_edit, 'String'));
        if isnan(y_min_in) || isnan(y_max_in) || (y_min_in >= y_max_in), applyYLimits(); return; end
        if state.isLogScale && y_min_in <= 0, set(ymin_edit, 'String', '1'); if y_max_in <= 1, set(ymax_edit, 'String', '10'); end; end
        state.auto_y = false; applyYLimits(); drawnow;
    end

    function autoYCallback(), state.auto_y = true; applyYLimits(); drawnow; end

    function loadFile(newIdx)
        if ~validateFileIndex(newIdx), return; end
        state.idx_file = newIdx; tbl = state.data_files(newIdx).raw_data;
        if isempty(tbl) || ~istable(tbl), return; end
        state.timestamps_display = arrayfun(@(v) sprintf('%.3f s', v), tbl{:,1}, 'UniformOutput', false);
        % Zeros are shown as 1 so they appear on the log axis
        data_mat = tbl{:,2:end}; [n_rows, n_bins] = size(data_mat); data_mat(data_mat==0) = 1;
        state.data_mat = data_mat; state.n_rows = n_rows; state.n_bins = n_bins;
        if isfield(state.data_files,'peaks_height') && ~isempty(state.data_files(newIdx).peaks_height)
            state.peaks_height = table2array(state.data_files(newIdx).peaks_height); state.peaks_location = table2array(state.data_files(newIdx).peaks_location); state.hasPeaks = true;
        else, state.hasPeaks = false; end
        if state.canDrawFits && isfield(state.data_files, 'fit_parameters') && ~isempty(state.data_files(newIdx).fit_parameters)
            f_tbl = state.data_files(newIdx).fit_parameters; target_vars = {'height1', 'height2', 'height3', 'position1', 'position2', 'position3'};
            if all(ismember(target_vars, f_tbl.Properties.VariableNames)), state.fit_params = table2array(f_tbl(:, target_vars)); state.hasFits = true; else, state.hasFits = false; end
        else, state.hasFits = false; end
        if n_rows > 1, set(sld, 'Min', 1, 'Max', n_rows, 'Value', 1, 'SliderStep', [1/(n_rows-1) , min(1, 10/(n_rows-1))]); else, set(sld, 'Min', 1, 'Max', 1.01, 'Value', 1, 'SliderStep', [1, 1]); end
        set(idx_txt, 'String', '1'); set(file_edit, 'String', num2str(newIdx)); applyYLimits();
        set(hLine, 'XData', 0:(n_bins-1)); set([hPeaks, hFitTotal, hFit1, hFit2, hFit3], 'XData', nan, 'YData', nan, 'Visible','off');
    end

    function sliderCallback()
        idx = round(get(sld, 'Value')); idx = max(1, min(state.n_rows, idx)); set(sld, 'Value', idx);
        set(hLine, 'YData', state.data_mat(idx,:));
        ts = ''; if idx <= numel(state.timestamps_display), ts = state.timestamps_display{idx}; end
        set(t, 'String', sprintf('File %d Row %d / %d Timestamp: %s', state.idx_file, idx, state.n_rows, ts), 'Interpreter','none'); set(idx_txt, 'String', num2str(idx));
        if state.hasPeaks
            Hrow = state.peaks_height(idx,:); Lrow = state.peaks_location(idx,:); valid = ~isnan(Hrow) & ~isnan(Lrow);
            if any(valid), Lplot = max(0, min(state.n_bins-1, Lrow(valid))); set(hPeaks, 'XData', Lplot, 'YData', Hrow(valid), 'Visible','on'); else, set(hPeaks, 'Visible','off'); end
        end
        if state.hasFits
            params = state.fit_params(idx, :);
            if ~any(isnan(params))
                h1 = params(1); h2 = params(2); h3 = params(3); p1 = params(4); p2 = params(5); p3 = params(6);
                xx = linspace(0, state.n_bins-1, 500);

                y1 = h1 * state.master_curves.Peak1(xx - p1);
                y2 = h2 * state.master_curves.Peak2(xx - p2);
                y3 = h3 * state.master_curves.Peak3(xx - p3);
                yTotal = y1 + y2 + y3;

                % Values below 1 are drawn at 1 so they appear on the log axis
                y1(y1 < 1) = 1; y2(y2 < 1) = 1; y3(y3 < 1) = 1; yTotal(yTotal < 1) = 1;

                set(hFitTotal, 'XData', xx, 'YData', yTotal, 'Visible','on');
                set(hFit1, 'XData', xx, 'YData', y1, 'Visible','on');
                set(hFit2, 'XData', xx, 'YData', y2, 'Visible','on');
                set(hFit3, 'XData', xx, 'YData', y3, 'Visible','on');
            else, set([hFitTotal, hFit1, hFit2, hFit3], 'Visible','off'); end
        else, set([hFitTotal, hFit1, hFit2, hFit3], 'Visible','off'); end
        drawnow;
    end

    function fileEditCallback()
        val = str2double(get(file_edit, 'String')); if isnan(val) || ~validateFileIndex(val), set(file_edit, 'String', num2str(state.idx_file)); return; end
        loadFile(val); sliderCallback();
    end

    function toggleScale()
        state.isLogScale = logical(get(scale_chk, 'Value'));
        if ~state.auto_y && state.isLogScale, if str2double(get(ymin_edit, 'String')) <= 0, set(ymin_edit, 'String', '1'); end; end
        applyYLimits(); drawnow;
    end

    function keyPressFcn(~, event)
        switch event.Key
            case 'rightarrow', v = min(state.n_rows, round(get(sld,'Value')) + 1); set(sld,'Value',v); sliderCallback();
            case 'leftarrow', v = max(1, round(get(sld,'Value')) - 1); set(sld,'Value',v); sliderCallback();
            case 'home', set(sld,'Value',1); sliderCallback();
            case 'end', set(sld,'Value',state.n_rows); sliderCallback();
            case 'l', set(scale_chk, 'Value', ~get(scale_chk,'Value')); toggleScale();
        end
    end

    function exportFrameCallback()
        % Draw the current frame in an off-screen figure styled like the
        % published Figure 3: raw data, total fit and the three peaks (all
        % solid lines), no initial-peak markers, and the published axis label
        exportFig = figure('Name', 'Export Temp', 'NumberTitle', 'off', 'Position', [-5000, -5000, 800, 600], 'Color', 'w');
        newAx = axes('Parent', exportFig);
        hold(newAx, 'on');

        idx = round(get(sld, 'Value'));

        plot(newAx, 0:(state.n_bins-1), state.data_mat(idx,:), 'k-o', 'MarkerSize',4, 'MarkerFaceColor','k', 'DisplayName','Raw Data');

        if strcmp(get(hFitTotal, 'Visible'), 'on')
            plot(newAx, get(hFitTotal, 'XData'), get(hFitTotal, 'YData'), '-', 'Color', [0.3 0.3 0.3], 'LineWidth', 2, 'DisplayName','Total Fit');
            plot(newAx, get(hFit1, 'XData'), get(hFit1, 'YData'), '-', 'Color', c1, 'LineWidth', 1.5, 'DisplayName','Peak 1');
            plot(newAx, get(hFit2, 'XData'), get(hFit2, 'YData'), '-', 'Color', c2, 'LineWidth', 2.5, 'DisplayName','Peak 2');
            plot(newAx, get(hFit3, 'XData'), get(hFit3, 'YData'), '-', 'Color', c3, 'LineWidth', 1.5, 'DisplayName','Peak 3');
        end

        xlabel(newAx, 'Bin Number');
        ylabel(newAx, 'Signal Amplitude Kcps');

        if state.isLogScale
            set(newAx, 'YScale', 'log');
        end

        ylim(newAx, ylim(ax));
        xlim(newAx, xlim(ax));

        set(newAx, 'Box', 'off', 'XGrid', 'off', 'YGrid', 'off', 'XColor', 'k', 'YColor', 'k');
        legend(newAx, 'show', 'Location', 'northeast');

        % Same 2:1 shape as paper Figure 3
        savename = sprintf('Histogram_File%d_Row%d', state.idx_file, idx);
        ExportFigure(exportFig, savename, 2*FigureWidth, FigureWidth);

        close(exportFig);
        fprintf('Exported current histogram frame to Figures/%s.*\n', savename);
    end
end
