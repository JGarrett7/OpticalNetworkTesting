%% MultiPeakStretch.m
% Stretching tests on the hard-junction prototype network.
% Produces paper Figures 8 and 9 (box plots of normalized peak amplitude
% and peak shift for each sensor).
%
% Stages (chosen in a dialog when processed_data_files.mat already exists)
%   1. Load the raw CSV files in .\data. Each file is one stretching run on
%      one sensor. The file name gives the sensor, the method (Hand or Rig),
%      the starting grip spacing, the step size and the total elongation
%      in inches, and the run number.
%   2. Find the largest peak in two bin windows of every histogram frame.
%      The window 1 height is Peak 1's starting height. Frames with no
%      peak in window 1 are not fitted.
%   3. Fit every frame as the sum of three master curves (master_curves.mat),
%      each scaled by a height and shifted by a position. Each frame starts
%      from the previous frame's fit (sequential seeding).
%   4. Interactive histogram player for browsing frames and fits.
%   5. Run-by-run diagnostic figures (shown, not saved). Not used in the
%      paper.
%   6. Box-and-whisker plots for each sensor (paper Figures 8 and 9).
%
% The paper reports the hand-stretched runs (file names with "_Hand_"),
% and only those runs are plotted. The clamp-rig runs for Sensors B and C
% ("_Rig_") are included because the normalization step divides each
% sensor's heights by the largest fitted height across all of that
% sensor's runs, rig runs included. Removing them would change the
% normalized amplitudes for Sensors B and C.
%
% Stages 1 to 3 reprocess the raw data, take about 30 minutes and overwrite
% processed_data_files.mat. To reproduce the paper figures from the
% included results, select only stage 6.
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

% Legend positions for each sensor's amplitude and shift plots
legendLocationAmp   = struct('A', 'southwest', 'B', 'west',  'C', 'east',      'D', 'east');
legendLocationShift = struct('A', 'south',     'B', 'north', 'C', 'northwest', 'D', 'northwest');

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
        '4. Launch Interactive Histogram Player', ...
        '5. Show Run-by-Run Diagnostic Figures', ...
        '6. Generate Box and Whisker Plots (Figures 8 and 9)' ...
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
        'time', cell(num_files,1), 'sensor', cell(num_files,1), 'mode', cell(num_files,1), ...
        'start_in', cell(num_files,1), 'increment_in', cell(num_files,1), 'delta_in', cell(num_files,1), ...
        'run', cell(num_files,1), 'raw_data', cell(num_files,1));

    % Test details appended to the GUI's default file name, for example
    % data_VL53L8CH__AIKit__CNH_4x4_ONECNH__20260312_155006_SensorA_Hand_Start2in_Increment2in_Change2in_Run1.csv
    pattern = [ ...
        '(?<prefix>.*)__' ...
        '(?<date>\d{8}|\d{4}[-]\d{1,2}[-]\d{1,2})_' ...
        '(?<time>\d{6}|[\d\-:]{4,8})_' ...
        'Sensor(?<sensor>[A-Za-z0-9]+)_' ...
        '(?<mode>Hand|Rig)_' ...
        'Start(?<start>\d+\.?\d*)in_' ...
        'Increment(?<inc>\d+\.?\d*)in_' ...
        'Change(?<change>\d+\.?\d*)in_' ...
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
            tokens = struct('date','','time','','sensor','','mode','','start','','inc','','change','','run','');

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

            mode_idx = find(strcmp(parts, 'Hand') | strcmp(parts, 'Rig'), 1);
            if ~isempty(mode_idx)
                tokens.mode = parts{mode_idx};
            end

            for p = 1:numel(parts)
                if startsWith(parts{p}, 'Start', 'IgnoreCase', true)
                    tokens.start = regexprep(parts{p}, '[^\d\.]', '');
                elseif startsWith(parts{p}, 'Increment', 'IgnoreCase', true)
                    tokens.inc = regexprep(parts{p}, '[^\d\.]', '');
                elseif startsWith(parts{p}, 'Change', 'IgnoreCase', true)
                    tokens.change = regexprep(parts{p}, '[^\d\.]', '');
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
        data_files(idx_file).mode = tokens.mode;

        data_files(idx_file).start_in = str2double(tokens.start);
        data_files(idx_file).increment_in = str2double(tokens.inc);
        data_files(idx_file).delta_in = str2double(tokens.change);
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
% height for Peak 1. Widths and prominences are stored for inspection only.
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
            warning('peak_guess failed for file %d (%s): %s', idx_file, data_files(idx_file).filename, ME.message);
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

            if any(isnan(ig_arr(r, :)))
                continue;
            end

            ydata = data_mat(r, :)';

            % Start from the previous frame's fit when it exists
            if r == 1 || any(isnan(fit_params_arr(r-1, :)))
                current_guess = ig_arr(r, :);
            else
                current_guess = fit_params_arr(r-1, :);
            end

            % Keep the starting point inside the bounds
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
end

%% Save Processed Data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Only runs when stages 1-3 ran. Plotting stages never write this file.
if run_load || run_peaks || run_fit
    fprintf('\nSaving processed data to %s (This may take a moment)...\n', dataFileMat);
    save(dataFileMat, 'data_files', '-v7.3');
    fprintf('Save complete.\n');
end

%% Stage 4: Histogram Player %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if run_player
    fprintf('\nLaunching Interactive Histogram Player...\n');
    interactive_histogram_player(data_files, 1)
end

%% Normalize Heights and Summarize Hand Runs %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if run_plateaus || run_boxplots
    fprintf('\n--- Normalizing Data and Processing Summaries ---\n');

    % Make sure the fields exist before they are filled
    [data_files.normalized_fit_parameters] = deal([]);
    if ~isfield(data_files, 'stretch_summary')
        [data_files.stretch_summary] = deal([]);
    end

    % Step 1: largest fitted height of each peak for each sensor, across
    % every run of that sensor (hand and rig)
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

    % Step 2: normalized heights (0 to 1) and positions for every run
    for i = 1:numel(data_files)
        if valid_idx(i)
            sens = data_files(i).sensor;
            max_vals = sensor_max(sens);

            tbl = data_files(i).fit_parameters;

            norm_height1 = tbl.height1 / max_vals(1);
            norm_height2 = tbl.height2 / max_vals(2);
            norm_height3 = tbl.height3 / max_vals(3);

            position1 = tbl.position1;
            position2 = tbl.position2;
            position3 = tbl.position3;

            data_files(i).normalized_fit_parameters = table(...
                norm_height1, position1, norm_height2, position2, norm_height3, position3);
        end
    end

    % Step 3: for each hand run, find the stretch plateau and the unstretched
    % periods before and after it on the sensor's primary peak, then take
    % the median amplitude and position of every peak in each window
    for i = 1:numel(data_files)
        df = data_files(i);

        if isempty(df.normalized_fit_parameters) || isempty(df.raw_data) || ~strcmpi(df.mode, 'Hand')
            continue;
        end

        time_sec = df.raw_data{:, 1};
        h1 = df.normalized_fit_parameters.norm_height1;
        h2 = df.normalized_fit_parameters.norm_height2;
        h3 = df.normalized_fit_parameters.norm_height3;

        p1 = df.normalized_fit_parameters.position1;
        p2 = df.normalized_fit_parameters.position2;
        p3 = df.normalized_fit_parameters.position3;

        switch upper(df.sensor)
            case 'A'
                primary_h = h1; prim_idx = 1;
            case {'B', 'D'}
                primary_h = h2; prim_idx = 2;
            case 'C'
                primary_h = h3; prim_idx = 3;
            otherwise
                primary_h = h1; prim_idx = 1;
        end

        [pre_win, plat_win, post_win] = extract_stretch_windows(time_sec, primary_h);

        if ~isnan(plat_win(1))
            get_med = @(data, win) median(data(time_sec >= win(1) & time_sec <= win(2)), 'omitnan');

            summary = struct();
            summary.windows = struct('pre', pre_win, 'plateau', plat_win, 'post', post_win);

            for pk = 1:3
                if pk==1, h=h1; pos=p1; elseif pk==2, h=h2; pos=p2; else, h=h3; pos=p3; end
                summary.(sprintf('peak%d', pk)) = struct(...
                    'pre_amp', get_med(h, pre_win),   'pre_pos', get_med(pos, pre_win), ...
                    'plat_amp', get_med(h, plat_win), 'plat_pos', get_med(pos, plat_win), ...
                    'post_amp', get_med(h, post_win), 'post_pos', get_med(pos, post_win));
            end

            data_files(i).stretch_summary = summary;

            fprintf('\n--- HAND STRETCH REPORT: Run %d (Sensor %s) ---\n', df.run, df.sensor);
            fprintf('  TIMING WINDOWS:\n');
            fprintf('    Pre-Stretch Baseline : [%6.2f - %6.2f] sec\n', pre_win(1), pre_win(2));
            fprintf('    Stretch Plateau      : [%6.2f - %6.2f] sec\n', plat_win(1), plat_win(2));
            if ~isnan(post_win(1))
                fprintf('    Post-Stretch Baseline: [%6.2f - %6.2f] sec\n', post_win(1), post_win(2));
            else
                fprintf('    Post-Stretch Baseline: Not Detected (End of file reached)\n');
            end

            fprintf('  PEAK DATA (Medians):\n');
            for pk = 1:3
                p_data = summary.(sprintf('peak%d', pk));
                prim_tag = ''; if pk == prim_idx, prim_tag = ' (Primary)'; end
                fprintf('    Peak %d%s:\n', pk, prim_tag);
                fprintf('      Amplitude -> Pre: %6.3f | Plateau: %6.3f | Post: %6.3f\n', ...
                    p_data.pre_amp, p_data.plat_amp, p_data.post_amp);
                fprintf('      Position  -> Pre: %6.2f | Plateau: %6.2f | Post: %6.2f\n', ...
                    p_data.pre_pos, p_data.plat_pos, p_data.post_pos);
            end
        end
    end
end

%% Stage 5: Run-by-Run Diagnostic Figures (not saved) %%%%%%%%%%%%%%%%%%%%%%%%
if run_plateaus
    fprintf('\n--- Generating Run-by-Run Diagnostic Figures ---\n');
    count_figs = 0;

    for i = 1:numel(data_files)
        df = data_files(i);

        if isempty(df.normalized_fit_parameters) || isempty(df.raw_data)
            continue;
        end

        time_sec = df.raw_data{:, 1};
        h1 = df.normalized_fit_parameters.norm_height1;
        h2 = df.normalized_fit_parameters.norm_height2;
        h3 = df.normalized_fit_parameters.norm_height3;
        p1 = df.normalized_fit_parameters.position1;
        p2 = df.normalized_fit_parameters.position2;
        p3 = df.normalized_fit_parameters.position3;

        % Shift relative to the first fitted position of each peak
        idx1 = find(~isnan(p1), 1, 'first'); if isempty(idx1), idx1 = 1; end
        idx2 = find(~isnan(p2), 1, 'first'); if isempty(idx2), idx2 = 1; end
        idx3 = find(~isnan(p3), 1, 'first'); if isempty(idx3), idx3 = 1; end

        shift1 = p1 - p1(idx1);
        shift2 = p2 - p2(idx2);
        shift3 = p3 - p3(idx3);

        title_str = sprintf('Sensor %s | %s Mode | Start: %g" | Inc: %g" | Change: %g" | Run %d', ...
            df.sensor, df.mode, df.start_in, df.increment_in, df.delta_in, df.run);

        fig_name = sprintf('Test Data - Run %d - Sensor %s', df.run, df.sensor);
        fig = figure('Name', fig_name, 'Color', 'w', 'Units', 'normalized', 'Position', [0.1 0.1 0.6 0.8]);

        tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
        title(tl, title_str, 'FontWeight', 'bold', 'FontSize', 14, 'Color', 'k');

        ax1 = nexttile(tl);
        hold(ax1, 'on');
        plot(ax1, time_sec, h1, 'g-', 'LineWidth', 1.5, 'DisplayName', 'Peak 1 Amplitude');
        plot(ax1, time_sec, h2, 'm-', 'LineWidth', 2.5, 'DisplayName', 'Peak 2 Amplitude');
        plot(ax1, time_sec, h3, 'c--', 'LineWidth', 1.5, 'DisplayName', 'Peak 3 Amplitude');

        % Detected windows on the primary peak (dotted: unstretched, solid: plateau)
        if strcmpi(df.mode, 'Hand') && isfield(df, 'stretch_summary') && ~isempty(df.stretch_summary)
            switch upper(df.sensor)
                case 'A', prim_color = 'g'; prim_idx = 1;
                case {'B', 'D'}, prim_color = 'm'; prim_idx = 2;
                case 'C', prim_color = 'c'; prim_idx = 3;
                otherwise, prim_color = 'g'; prim_idx = 1;
            end

            summary = df.stretch_summary;
            prim_dat = summary.(sprintf('peak%d', prim_idx));

            if ~isnan(summary.windows.pre(1))
                plot(ax1, summary.windows.pre, [prim_dat.pre_amp, prim_dat.pre_amp], ':', 'Color', prim_color, 'LineWidth', 3, 'HandleVisibility', 'off');
            end
            if ~isnan(summary.windows.plateau(1))
                plot(ax1, summary.windows.plateau, [prim_dat.plat_amp, prim_dat.plat_amp], '-', 'Color', prim_color, 'LineWidth', 4, 'HandleVisibility', 'off');
            end
            if ~isnan(summary.windows.post(1))
                plot(ax1, summary.windows.post, [prim_dat.post_amp, prim_dat.post_amp], ':', 'Color', prim_color, 'LineWidth', 3, 'HandleVisibility', 'off');
            end
        end

        ylabel(ax1, 'Normalized Amplitude');
        grid(ax1, 'on');
        legend(ax1, 'Location', 'best');
        set(ax1, 'FontSize', 11, 'Box', 'on', 'XColor', 'k', 'YColor', 'k');

        ax2 = nexttile(tl);
        hold(ax2, 'on');
        plot(ax2, time_sec, shift1, 'g-', 'LineWidth', 1.5, 'DisplayName', 'Peak 1 Shift');
        plot(ax2, time_sec, shift2, 'm-', 'LineWidth', 2.5, 'DisplayName', 'Peak 2 Shift');
        plot(ax2, time_sec, shift3, 'c--', 'LineWidth', 1.5, 'DisplayName', 'Peak 3 Shift');
        xlabel(ax2, 'Time (seconds)');
        ylabel(ax2, 'Shift in Location (Bins)');
        grid(ax2, 'on');
        set(ax2, 'FontSize', 11, 'Box', 'on', 'XColor', 'k', 'YColor', 'k');

        linkaxes([ax1, ax2], 'x');
        count_figs = count_figs + 1;
    end
    fprintf('Generated %d figures.\n', count_figs);
end

%% Stage 6: Box and Whisker Plots (Figures 8 and 9) %%%%%%%%%%%%%%%%%%%%%%%%%
% For each hand run: the 0 cm values are the pre-stretch medians, and the
% stretched values are the plateau medians. The shift is the plateau
% position minus the pre-stretch position, in bins.
if run_boxplots
    fprintf('\n--- Generating Aggregated Stretch Box and Whisker Plots ---\n');

    hand_idx = arrayfun(@(s) strcmpi(s.mode, 'Hand') && isfield(s, 'stretch_summary') && ~isempty(s.stretch_summary), data_files);
    hand_files = data_files(hand_idx);

    unique_stretch_sensors = unique({hand_files.sensor});

    for s = 1:numel(unique_stretch_sensors)
        sens = unique_stretch_sensors{s};

        plot_dists  = [];
        plot_amps   = [];
        plot_shifts = [];
        plot_groups = categorical([]);

        for j = 1:numel(hand_files)
            df = hand_files(j);
            if ~strcmp(df.sensor, sens), continue; end

            summary = df.stretch_summary;
            if isnan(summary.windows.plateau(1)), continue; end

            stretch_cm = round(df.delta_in * 2.54);

            % Peak 1: amplitude and shift (the 0 cm shift is 0 by definition)
            plot_dists  = [plot_dists; 0; stretch_cm]; %#ok<SAGROW>
            plot_amps   = [plot_amps; summary.peak1.pre_amp; summary.peak1.plat_amp]; %#ok<SAGROW>
            shift1      = summary.peak1.plat_pos - summary.peak1.pre_pos;
            plot_shifts = [plot_shifts; 0; shift1]; %#ok<SAGROW>
            plot_groups = [plot_groups; repmat(categorical({'Peak 1'}), 2, 1)]; %#ok<SAGROW>

            % Peak 2: amplitude and shift
            plot_dists  = [plot_dists; 0; stretch_cm]; %#ok<SAGROW>
            plot_amps   = [plot_amps; summary.peak2.pre_amp; summary.peak2.plat_amp]; %#ok<SAGROW>
            shift2      = summary.peak2.plat_pos - summary.peak2.pre_pos;
            plot_shifts = [plot_shifts; 0; shift2]; %#ok<SAGROW>
            plot_groups = [plot_groups; repmat(categorical({'Peak 2'}), 2, 1)]; %#ok<SAGROW>

            % Peak 3: amplitude and shift
            plot_dists  = [plot_dists; 0; stretch_cm]; %#ok<SAGROW>
            plot_amps   = [plot_amps; summary.peak3.pre_amp; summary.peak3.plat_amp]; %#ok<SAGROW>
            shift3      = summary.peak3.plat_pos - summary.peak3.pre_pos;
            plot_shifts = [plot_shifts; 0; shift3]; %#ok<SAGROW>
            plot_groups = [plot_groups; repmat(categorical({'Peak 3'}), 2, 1)]; %#ok<SAGROW>
        end

        if isempty(plot_dists)
            continue;
        end

        % Some shifts are differences between positions held at the same
        % fit bound and are floating-point round-off rather than zero. They
        % are drawn as 0 so they don't appear as outliers. The trend-line
        % equations use the unrounded values.
        shifts_drawn = plot_shifts;
        shifts_drawn(abs(shifts_drawn) < 1e-9) = 0;

        unique_dists = unique(plot_dists);
        peak_labels = {'Peak 1', 'Peak 2', 'Peak 3'};

        % =================================================================
        % Figure A: normalized amplitude
        % =================================================================
        fig_amp = figure('Name', sprintf('Aggregated Stretch Amp - Sensor %s', sens), ...
            'Color', 'w', 'Units', 'normalized', 'Position', [0.15 0.15 0.7 0.7]);

        % Axes leave the top of the figure free for the trend-line equations
        ax_amp = axes('Parent', fig_amp, 'Position', [0.15 0.15 0.75 0.65]);
        hold(ax_amp, 'on');

        b_amp = boxchart(plot_dists, plot_amps, 'GroupByColor', plot_groups);
        style_boxes(b_amp, showOutliers);
        colororder(ax_amp, [c1; c2; c3]);
        set(ax_amp, 'XTick', unique_dists);

        xlabel(ax_amp, 'Stretch Distance (cm)', 'FontWeight', 'bold');
        ylabel(ax_amp, 'Normalized Amplitude', 'FontWeight', 'bold');
        grid(ax_amp, 'off');
        set(ax_amp, 'FontSize', 12, 'Box', 'off', 'XGrid', 'off', 'YGrid', 'off');
        legend(ax_amp, 'Location', pick_location(legendLocationAmp, sens));

        add_trend_equations(fig_amp, plot_dists, plot_amps, plot_groups, unique_dists, peak_labels);

        savename_amp = sprintf('AggregatedStretch_Amp_Sensor%s', sens);
        ExportFigure(fig_amp, savename_amp, FigureWidth);

        % =================================================================
        % Figure B: shift in location
        % =================================================================
        fig_shift = figure('Name', sprintf('Aggregated Stretch Shift - Sensor %s', sens), ...
            'Color', 'w', 'Units', 'normalized', 'Position', [0.2 0.2 0.7 0.7]);

        ax_shift = axes('Parent', fig_shift, 'Position', [0.15 0.15 0.75 0.65]);
        hold(ax_shift, 'on');

        b_shift = boxchart(plot_dists, shifts_drawn, 'GroupByColor', plot_groups);
        style_boxes(b_shift, showOutliers);
        colororder(ax_shift, [c1; c2; c3]);
        set(ax_shift, 'XTick', unique_dists);

        xlabel(ax_shift, 'Stretch Distance (cm)', 'FontWeight', 'bold');
        ylabel(ax_shift, 'Shift in Location (Bins)', 'FontWeight', 'bold');
        grid(ax_shift, 'off');
        set(ax_shift, 'FontSize', 12, 'Box', 'off', 'XGrid', 'off', 'YGrid', 'off');
        legend(ax_shift, 'Location', pick_location(legendLocationShift, sens));

        add_trend_equations(fig_shift, plot_dists, plot_shifts, plot_groups, unique_dists, peak_labels);

        savename_shift = sprintf('AggregatedStretch_Shift_Sensor%s', sens);
        ExportFigure(fig_shift, savename_shift, FigureWidth);
    end
end

%% Local Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function style_boxes(b, showOutliers)
%STYLE_BOXES Line width and outlier markers for a set of boxchart objects.
    for j = 1:numel(b)
        b(j).LineWidth = 1.5;
        if showOutliers
            b(j).MarkerStyle = 'o';
            b(j).MarkerSize = 4;
        else
            b(j).MarkerStyle = 'none';
        end
    end
end

function loc = pick_location(locationMap, sens)
%PICK_LOCATION Legend location for a sensor, or 'best' if none is set.
    if isfield(locationMap, sens)
        loc = locationMap.(sens);
    else
        loc = 'best';
    end
end

function add_trend_equations(fig, x_vals, y_vals, groups, unique_x, peak_labels)
%ADD_TREND_EQUATIONS Print a linear fit through the box medians of each
%   peak above the axes. The fit lines themselves are not drawn.
    equations = {};
    for p = 1:numel(peak_labels)
        lbl = peak_labels{p};
        med_vals = NaN(size(unique_x));

        for m = 1:length(unique_x)
            idx = (x_vals == unique_x(m)) & (groups == lbl);
            if any(idx), med_vals(m) = median(y_vals(idx)); end
        end

        valid_fit_idx = ~isnan(med_vals);
        if sum(valid_fit_idx) > 1
            poly_coeff = polyfit(unique_x(valid_fit_idx), med_vals(valid_fit_idx), 1);

            slope = poly_coeff(1); intercept = poly_coeff(2);
            sign_str = '+'; if intercept < 0, sign_str = '-'; end
            % '% .1e' pads positive numbers with a space so the columns line up
            equations{end+1} = sprintf('%s: y = % .1e x %s %.1e', lbl, slope, sign_str, abs(intercept)); %#ok<AGROW>
        end
    end

    if ~isempty(equations)
        eq_text = strjoin(equations, '\n');
        annotation(fig, 'textbox', [0.05 0.82 0.90 0.15], 'String', eq_text, ...
            'FitBoxToText', 'off', 'BackgroundColor', 'none', 'EdgeColor', 'none', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'FontSize', 11, 'FontName', 'Courier');
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
%REPORT_MISSING_PEAKS List frames where no peak was found in a window.
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
        end

        for r = rows_with_nan1(:)'
            fprintf('File %d: Peak1 is NaN at row %d\n', fi, r);
        end
        for r = rows_with_nan2(:)'
            fprintf('File %d: Peak2 is NaN at row %d\n', fi, r);
        end
    end
    if ~foundAny
        fprintf('No missing peaks found in any peaks_location tables.\n');
    end
end

function [initial_peak_guesses, lower_bounds, upper_bounds] = peak_guess(peaks_height)
%PEAK_GUESS Initial guesses and bounds for the stretching fits.
%   Heights must be non-negative (stretching lowers amplitude). Position
%   lower bounds equal the pressing-fit lower bounds, and position upper
%   bounds are the pressing-fit upper bounds plus 7.5 bins.
    N = height(peaks_height);
    varNames = {'height1','position1','height2','position2','height3','position3'};

    initial_peak_guesses = array2table(nan(N,6), 'VariableNames', varNames);
    lower_bounds         = array2table(nan(N,6), 'VariableNames', varNames);
    upper_bounds         = array2table(nan(N,6), 'VariableNames', varNames);

    % Heights
    initial_peak_guesses.height1   = peaks_height.Peak1;
    lower_bounds.height1           = zeros(N, 1);
    upper_bounds.height1           = inf(N, 1);

    initial_peak_guesses.height2   = repmat(600, N, 1);
    lower_bounds.height2           = zeros(N, 1);
    upper_bounds.height2           = inf(N, 1);

    initial_peak_guesses.height3   = repmat(40, N, 1);
    lower_bounds.height3           = zeros(N, 1);
    upper_bounds.height3           = inf(N, 1);

    % Positions (bins)
    initial_peak_guesses.position1 = repmat(66.48, N, 1);
    lower_bounds.position1         = repmat(66.14, N, 1);
    upper_bounds.position1         = repmat(74.08, N, 1);

    initial_peak_guesses.position2 = repmat(82.74, N, 1);
    lower_bounds.position2         = repmat(82.68, N, 1);
    upper_bounds.position2         = repmat(90.39, N, 1);

    initial_peak_guesses.position3 = repmat(86.65, N, 1);
    lower_bounds.position3         = repmat(86.58, N, 1);
    upper_bounds.position3         = repmat(94.34, N, 1);
end

function fig = interactive_histogram_player(data_files, idx_file)
%INTERACTIVE_HISTOGRAM_PLAYER Browse histogram frames and their fits.
%   Slider or arrow keys: change frame. File #: change file. L: toggle log
%   y-axis.
    if nargin<2, error('Must provide data_files and idx_file.'); end

    bg_color = [0.15 0.15 0.15];
    ax_color = [0.1 0.1 0.1];
    ui_bg    = [0.25 0.25 0.25];

    fig = figure('Name', 'Histogram Player', 'NumberTitle','off', 'Color', bg_color);
    ax = axes('Parent', fig, 'Color', ax_color, 'XColor', 'w', 'YColor', 'w');
    hold(ax, 'on');
    xlabel(ax, 'Bin Number', 'Color', 'w');
    ylabel(ax, 'Signal Amplitude (kcps)', 'Color', 'w');

    top_margin = 0.93; edit_w = 0.08; edit_h = 0.04;
    edit_x = 0.88; edit_y = top_margin - edit_h;

    uicontrol('Parent', fig, 'Style','text', 'Units','normalized', ...
        'Position', [edit_x-0.07, edit_y, 0.07, edit_h], 'String','File #', ...
        'HorizontalAlignment','right', 'BackgroundColor', bg_color, 'ForegroundColor', 'w');

    file_edit = uicontrol('Parent', fig, 'Style','edit', 'Units','normalized', ...
        'Position', [edit_x, edit_y, edit_w, edit_h], 'String', num2str(idx_file), ...
        'BackgroundColor', ui_bg, 'ForegroundColor', 'w', 'Callback', @(src,ev) fileEditCallback());

    sld = uicontrol('Parent', fig, 'Style','slider', 'Units','normalized', ...
        'Position', [0.15 0.02 0.6 0.05], 'Min',1, 'Max',1, 'Value',1, 'BackgroundColor', bg_color);

    idx_txt = uicontrol('Parent', fig, 'Style','text', 'Units','normalized', ...
        'Position', [0.88 0.02 0.1 0.05], 'String','1', 'HorizontalAlignment','left', ...
        'BackgroundColor', bg_color, 'ForegroundColor', 'w');

    scale_chk = uicontrol('Parent', fig, 'Style','checkbox', 'Units','normalized', ...
        'Position', [0.76 0.02 0.1 0.05], 'String','Log Y', 'Value', 1, ...
        'BackgroundColor', bg_color, 'ForegroundColor', 'w');

    uicontrol('Parent', fig, 'Style','text', 'Units','normalized', ...
        'Position', [0.02, edit_y, 0.05, edit_h], 'String','Y-Min:', ...
        'HorizontalAlignment','right', 'BackgroundColor', bg_color, 'ForegroundColor', 'w');

    ymin_edit = uicontrol('Parent', fig, 'Style','edit', 'Units','normalized', ...
        'Position', [0.08, edit_y, 0.06, edit_h], 'String', '1', ...
        'BackgroundColor', ui_bg, 'ForegroundColor', 'w', 'Callback', @(src,ev) manualYLimCallback());

    uicontrol('Parent', fig, 'Style','text', 'Units','normalized', ...
        'Position', [0.15, edit_y, 0.05, edit_h], 'String','Y-Max:', ...
        'HorizontalAlignment','right', 'BackgroundColor', bg_color, 'ForegroundColor', 'w');

    ymax_edit = uicontrol('Parent', fig, 'Style','edit', 'Units','normalized', ...
        'Position', [0.21, edit_y, 0.06, edit_h], 'String', '100', ...
        'BackgroundColor', ui_bg, 'ForegroundColor', 'w', 'Callback', @(src,ev) manualYLimCallback());

    uicontrol('Parent', fig, 'Style','pushbutton', 'Units','normalized', ...
        'Position', [0.28, edit_y, 0.06, edit_h], 'String','Auto Y', ...
        'BackgroundColor', [0.35 0.35 0.35], 'ForegroundColor', 'w', 'Callback', @(src,ev) autoYCallback());

    hLine     = plot(ax, nan, nan, 'w-o', 'MarkerSize',4, 'MarkerFaceColor','w', 'DisplayName','Raw Data');
    hFitTotal = plot(ax, nan, nan, 'b-', 'LineWidth', 2, 'DisplayName','Total Fit');
    hFit1     = plot(ax, nan, nan, 'g-', 'LineWidth', 1.5, 'DisplayName','Peak 1');
    hFit2     = plot(ax, nan, nan, 'm-', 'LineWidth', 2.5, 'DisplayName','Peak 2');
    hFit3     = plot(ax, nan, nan, 'c--', 'LineWidth', 1.5, 'DisplayName','Peak 3');
    hPeaks    = plot(ax, nan, nan, 'r^', 'MarkerFaceColor','r', 'MarkerSize',8, 'DisplayName','Initial Peaks');

    lgd = legend(ax, 'show', 'Location', 'northeast');
    set(lgd, 'TextColor', 'w', 'Color', bg_color, 'EdgeColor', [0.3 0.3 0.3]);
    t = title(ax, '', 'Color', 'w');

    state.data_files = data_files;
    state.idx_file = idx_file;
    state.isLogScale = true;
    state.auto_y = true;

    try
        tmp = load('master_curves.mat', 'master_curves');
        state.master_curves = tmp.master_curves;
        state.canDrawFits = true;
    catch
        state.master_curves = [];
        state.canDrawFits = false;
        warning('Could not load master_curves.mat. Fitted curves cannot be drawn.');
    end

    addlistener(sld, 'Value', 'PostSet', @(~,~) sliderCallback());
    set(fig, 'KeyPressFcn', @keyPressFcn);
    set(scale_chk, 'Callback', @(~,~) toggleScale());

    loadFile(idx_file);
    sliderCallback();

    function ok = validateFileIndex(val)
        ok = isnumeric(val) && isscalar(val) && val>=1 && val<=numel(state.data_files) && (floor(val)==val);
    end
    function applyYLimits()
        ymax_data = max(state.data_mat(:));
        if isempty(ymax_data) || isnan(ymax_data) || ymax_data <= 0, ymax_data = 1; end

        if state.auto_y
            ymin_val = 0;
            if state.isLogScale, ymin_val = 1; end
            ymax_val = max(ymin_val + 1e-6, ymax_data);

            set(ymin_edit, 'String', num2str(ymin_val));
            set(ymax_edit, 'String', num2str(ymax_val));
        else
            ymin_val = str2double(get(ymin_edit, 'String'));
            ymax_val = str2double(get(ymax_edit, 'String'));
        end

        if state.isLogScale
            set(ax, 'YScale', 'log', 'YLim', [ymin_val, ymax_val]);
        else
            set(ax, 'YScale', 'linear', 'YLim', [ymin_val, ymax_val]);
        end
    end
    function manualYLimCallback()
        y_min_in = str2double(get(ymin_edit, 'String'));
        y_max_in = str2double(get(ymax_edit, 'String'));

        if isnan(y_min_in) || isnan(y_max_in) || (y_min_in >= y_max_in)
            applyYLimits();
            return;
        end

        if state.isLogScale && y_min_in <= 0
            set(ymin_edit, 'String', '1');
            if y_max_in <= 1
                set(ymax_edit, 'String', '10');
            end
        end

        state.auto_y = false;
        applyYLimits();
        drawnow;
    end
    function autoYCallback()
        state.auto_y = true;
        applyYLimits();
        drawnow;
    end
    function loadFile(newIdx)
        if ~validateFileIndex(newIdx)
            errordlg('Invalid file index.','File Index'); return;
        end
        state.idx_file = newIdx;
        tbl = state.data_files(newIdx).raw_data;
        if isempty(tbl) || ~istable(tbl)
            errordlg('Selected entry has no table.','Data Error'); return;
        end

        timestamps = tbl{:,1};
        state.timestamps_display = arrayfun(@(v) sprintf('%.3f s', v), timestamps, 'UniformOutput', false);

        % Zeros are shown as 1 so they appear on the log axis
        data_mat = tbl{:,2:end};
        [n_rows, n_bins] = size(data_mat);
        data_mat(data_mat==0) = 1;

        state.data_mat = data_mat;
        state.n_rows = n_rows;
        state.n_bins = n_bins;

        if isfield(state.data_files,'peaks_height') && ~isempty(state.data_files(newIdx).peaks_height)
            state.peaks_height = table2array(state.data_files(newIdx).peaks_height);
            state.peaks_location = table2array(state.data_files(newIdx).peaks_location);
            state.hasPeaks = true;
        else
            state.hasPeaks = false;
        end

        if state.canDrawFits && isfield(state.data_files, 'fit_parameters') && ~isempty(state.data_files(newIdx).fit_parameters)
            f_tbl = state.data_files(newIdx).fit_parameters;
            target_vars = {'height1', 'height2', 'height3', 'position1', 'position2', 'position3'};
            if all(ismember(target_vars, f_tbl.Properties.VariableNames))
                state.fit_params = table2array(f_tbl(:, target_vars));
                state.hasFits = true;
            else
                state.hasFits = false;
            end
        else
            state.hasFits = false;
        end

        if n_rows > 1
            set(sld, 'Min', 1, 'Max', n_rows, 'Value', 1, 'SliderStep', [1/(n_rows-1) , min(1, 10/(n_rows-1))]);
        else
            set(sld, 'Min', 1, 'Max', 1.01, 'Value', 1, 'SliderStep', [1, 1]);
        end

        set(idx_txt, 'String', '1');
        set(file_edit, 'String', num2str(newIdx));

        applyYLimits();

        set(hLine, 'XData', 0:(n_bins-1));
        set([hPeaks, hFitTotal, hFit1, hFit2, hFit3], 'XData', nan, 'YData', nan, 'Visible','off');
    end
    function sliderCallback()
        idx = round(get(sld, 'Value'));
        idx = max(1, min(state.n_rows, idx));
        set(sld, 'Value', idx);

        set(hLine, 'YData', state.data_mat(idx,:));
        ts = ''; if idx <= numel(state.timestamps_display), ts = state.timestamps_display{idx}; end
        set(t, 'String', sprintf('File %d Row %d / %d Timestamp: %s', state.idx_file, idx, state.n_rows, ts), 'Interpreter','none');
        set(idx_txt, 'String', num2str(idx));

        if state.hasPeaks
            Hrow = state.peaks_height(idx,:);
            Lrow = state.peaks_location(idx,:);
            valid = ~isnan(Hrow) & ~isnan(Lrow);

            if any(valid)
                Lplot = max(0, min(state.n_bins-1, Lrow(valid)));
                set(hPeaks, 'XData', Lplot, 'YData', Hrow(valid), 'Visible','on');
            else
                set(hPeaks, 'Visible','off');
            end
        end

        if state.hasFits
            params = state.fit_params(idx, :);
            if ~any(isnan(params))
                h1 = params(1); h2 = params(2); h3 = params(3);
                p1 = params(4); p2 = params(5); p3 = params(6);

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
            else
                set([hFitTotal, hFit1, hFit2, hFit3], 'Visible','off');
            end
        else
            set([hFitTotal, hFit1, hFit2, hFit3], 'Visible','off');
        end
        drawnow;
    end
    function fileEditCallback()
        str = get(file_edit, 'String');
        val = str2double(str);
        if isnan(val) || ~validateFileIndex(val)
            set(file_edit, 'String', num2str(state.idx_file)); return;
        end
        loadFile(val); sliderCallback();
    end
    function toggleScale()
        state.isLogScale = logical(get(scale_chk, 'Value'));
        if ~state.auto_y && state.isLogScale
            current_min = str2double(get(ymin_edit, 'String'));
            if current_min <= 0
                set(ymin_edit, 'String', '1');
            end
        end
        applyYLimits();
        drawnow;
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
end

function [pre_win, plat_win, post_win] = extract_stretch_windows(time_sec, y_raw)
%EXTRACT_STRETCH_WINDOWS Find the stretch plateau and unstretched periods.
%   The trace is smoothed with a 2 s moving median. The plateau is the
%   longest stretch below baseline - 0.80*range (baseline = 95th
%   percentile, range = baseline - 5th percentile), trimmed by 10% at each
%   end. The pre-stretch window runs from the start of the file to the
%   first drop below baseline - 0.15*range, trimmed by 15% at its end. The
%   post-stretch window runs from the first frame after the last frame
%   below that level to the end of the file, trimmed by 15% at its start.
%   Windows that cannot be found are returned as [NaN, NaN].

    pre_win = [NaN, NaN]; plat_win = [NaN, NaN]; post_win = [NaN, NaN];

    dt = median(diff(time_sec));
    if isnan(dt) || dt == 0, dt = 1; end
    window_samples = max(3, round(2.0 / dt));
    y_filt = movmedian(y_raw, window_samples);

    baseline = prctile(y_filt, 95);
    min_level = prctile(y_filt, 5);
    signal_range = baseline - min_level;

    % Skip traces that drop by less than 5%
    if signal_range < 0.05 * baseline
        return;
    end

    thresh_low  = baseline - 0.80 * signal_range; % stretched
    thresh_high = baseline - 0.15 * signal_range; % near the unstretched level

    % 1. Stretch plateau: longest run below the low threshold
    is_low = y_filt < thresh_low;
    edges_low = diff([0; is_low; 0]);
    starts_low = find(edges_low == 1);
    stops_low = find(edges_low == -1) - 1;

    if isempty(starts_low), return; end

    [~, max_idx] = max(stops_low - starts_low);
    idx_plat_s = starts_low(max_idx);
    idx_plat_e = stops_low(max_idx);

    trim_plat = round((idx_plat_e - idx_plat_s) * 0.1);
    if (idx_plat_e - trim_plat) > (idx_plat_s + trim_plat)
        idx_plat_s = idx_plat_s + trim_plat;
        idx_plat_e = idx_plat_e - trim_plat;
    end
    plat_win = [time_sec(idx_plat_s), time_sec(idx_plat_e)];

    % 2. Pre-stretch window: start of file to the first drop below the high threshold
    idx_first_drop = find(y_filt < thresh_high, 1, 'first');
    if ~isempty(idx_first_drop) && idx_first_drop > 5
        idx_pre_s = 1;
        idx_pre_e = idx_first_drop - 1;
        trim_pre = round((idx_pre_e - idx_pre_s) * 0.15);
        idx_pre_e = max(idx_pre_s, idx_pre_e - trim_pre);

        if idx_pre_e > idx_pre_s
            pre_win = [time_sec(idx_pre_s), time_sec(idx_pre_e)];
        end
    end

    % 3. Post-stretch window: after the last frame below the high threshold to the end of file
    idx_last_rise = find(y_filt < thresh_high, 1, 'last');
    if ~isempty(idx_last_rise) && idx_last_rise < (length(y_filt) - 5)
        idx_post_s = idx_last_rise + 1;
        idx_post_e = length(y_filt);
        trim_post = round((idx_post_e - idx_post_s) * 0.15);
        idx_post_s = min(idx_post_e, idx_post_s + trim_post);

        if idx_post_e > idx_post_s
            post_win = [time_sec(idx_post_s), time_sec(idx_post_e)];
        end
    end
end
