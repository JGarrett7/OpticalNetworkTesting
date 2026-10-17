%% SinglePeakTester.m
% Master curve generation for the hard-junction prototype network (paper
% section "Empirical Master Curve Generation").
%
% Each CSV in .\data was recorded with only one optical path connected
% (file names end in Peak1, Peak2 or Peak3) while the sensor was pressed by
% hand to vary the amplitude.
%
% Stages (chosen in a dialog when single_peak_calibration_data.mat exists)
%   1. Load the raw CSV files.
%   2. Build one master curve per path and save master_curves.mat:
%      median of all frames, bins outside a window around the peak set to
%      zero, normalized to a peak of 1, values below 1e-4 set to zero,
%      padded with zeros, then fit with a shape-preserving (pchip)
%      interpolant centered on the peak.
%   3. Fit every frame with its own master curve (height and position only).
%   4. Interactive histogram player for browsing frames and fits.
%   5. Box plot of the fitted positions, with min, median and max printed.
%
% The pressure and stretch folders each contain a copy of master_curves.mat
% made by stage 2. Stage 2 reproduces the same curves, but the copies in
% those folders are not updated automatically.
%
% Requirements: MATLAB R2024a or later, Curve Fitting Toolbox and Signal
% Processing Toolbox.

close all force
clear
clc

% Work in the folder that contains this script so relative paths resolve
scriptFolder = fileparts(mfilename('fullpath'));
if ~isempty(scriptFolder)
    cd(scriptFolder);
end

%% Stage Selection %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dataFileMat = 'single_peak_calibration_data.mat';

% Without saved results, every stage runs
run_load = true;
run_generate_curves = true;
run_fit = true;
run_player = true;
run_plots = true;

if isfile(dataFileMat)
    fprintf('Loading previously saved data from %s...\n', dataFileMat);
    load(dataFileMat, 'data_files');

    list_str = { ...
        '1. Rescan and Load Raw Data (Full Reset)', ...
        '2. Generate Master Curves (PchipInterpolant)', ...
        '3. Run Single-Curve Fitting', ...
        '4. Launch Interactive Histogram Player', ...
        '5. Generate Box & Whisker Plot' ...
    };

    [indx, tf] = listdlg('PromptString', {'Calibration data found. Select stages to run.', ...
                                          'Stages 1-3 overwrite the saved .mat files.', ...
                                          '(Hold Ctrl/Cmd to select multiple)'}, ...
                         'SelectionMode', 'multiple', ...
                         'ListString', list_str, ...
                         'InitialValue', 5, ...
                         'Name', 'Stage Selector', ...
                         'ListSize', [350, 150]);

    if ~tf
        disp('Operation cancelled by user. Exiting script.');
        return;
    end

    run_load            = ismember(1, indx);
    run_generate_curves = ismember(2, indx);
    run_fit             = ismember(3, indx);
    run_player          = ismember(4, indx);
    run_plots           = ismember(5, indx);

    if run_load
        warning('Full reset selected. Forcing curve generation and fitting stages to run.');
        run_generate_curves = true;
        run_fit = true;
    end
else
    fprintf('No saved data found. Running full pipeline...\n');
end

%% Stage 1: Load Raw Data and Parse File Names %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if run_load
    data_dir = fullfile(pwd, 'data');
    if ~isfolder(data_dir)
        error('Data directory not found: %s', data_dir);
    end
    files = dir(fullfile(data_dir, '*.csv'));
    num_files = numel(files);

    data_files = struct('filename', cell(num_files,1), 'filepath', cell(num_files,1), ...
        'raw_data', cell(num_files,1), 'target_name', cell(num_files,1), 'target_loc', cell(num_files,1));

    fprintf('\n--- Loading Calibration Data and Parsing Filenames ---\n');

    for idx_file = 1:num_files
        filename = files(idx_file).name;
        filepath = fullfile(files(idx_file).folder, filename);

        data_files(idx_file).filename = filename;
        data_files(idx_file).filepath = filepath;

        % The file name ending gives the connected path. target_loc is that
        % path's peak location in bins. The same values are hard-coded as
        % starting positions in MultiPeakPressure.m and MultiPeakStretch.m.
        [~, baseName, ~] = fileparts(filename);

        if endsWith(baseName, 'Peak1', 'IgnoreCase', true)
            data_files(idx_file).target_name = 'Peak 1';
            data_files(idx_file).target_loc  = 66.48;
        elseif endsWith(baseName, 'Peak2', 'IgnoreCase', true)
            data_files(idx_file).target_name = 'Peak 2';
            data_files(idx_file).target_loc  = 82.74;
        elseif endsWith(baseName, 'Peak3', 'IgnoreCase', true)
            data_files(idx_file).target_name = 'Peak 3';
            data_files(idx_file).target_loc  = 86.65;
        else
            warning('Filename %s does not end in Peak1, Peak2, or Peak3. Skipping.', filename);
            data_files(idx_file).target_name = '';
            data_files(idx_file).target_loc  = NaN;
        end

        try
            tbl = read_every16th_from_cnh_start(filepath);
            data_files(idx_file).raw_data = tbl;

            if ~isempty(data_files(idx_file).target_name)
                fprintf('Loaded %s -> Assigned to %s\n', filename, data_files(idx_file).target_name);
            end
        catch ME
            warning('Failed to read file %s: %s', filename, ME.message);
            data_files(idx_file).raw_data = [];
        end
    end
end

%% Stage 2: Generate Master Curves %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if run_generate_curves
    fprintf('\n--- Generating Master Normalized Curves ---\n');

    % Bins kept on each side of the peak. Bins outside this window, such
    % as the emitter crosstalk near bin 2, are set to zero. The window is
    % longer on the right to keep the pulse's decaying tail.
    left_cutoff  = 10;
    right_cutoff = 33;

    target_names = {'Peak 1', 'Peak 2', 'Peak 3'};
    expected_targets = [66.48, 82.74, 86.65];
    master_curves = struct();
    curve_peak_widths = struct();

    for t_idx = 1:3
        t_name = target_names{t_idx};
        t_loc = expected_targets(t_idx);

        % 1. Pool every frame recorded for this path
        pooled_data = [];
        for i = 1:numel(data_files)
            if strcmp(data_files(i).target_name, t_name) && ~isempty(data_files(i).raw_data)
                pooled_data = [pooled_data; data_files(i).raw_data{:, 2:end}]; %#ok<SAGROW>
            end
        end

        if isempty(pooled_data)
            warning('No data found to generate master curve for %s', t_name);
            continue;
        end

        n_bins = size(pooled_data, 2);

        % 2. Diagnostic figure: every frame normalized to its own peak
        fig_many = figure('Name', sprintf('%s - Overlapping Curves', t_name), 'Color', 'w');
        ax_many = axes('Parent', fig_many);
        hold(ax_many, 'on');

        c_start_plot = max(1, round(t_loc) - left_cutoff);
        c_end_plot   = min(n_bins, round(t_loc) + right_cutoff);

        for rowidx = 1:size(pooled_data, 1)
            row_vals = pooled_data(rowidx, :);
            m_val = max(row_vals(c_start_plot:c_end_plot));
            if m_val > 0
                plot(ax_many, 0:(n_bins-1), row_vals ./ m_val, 'Color', [0.5 0.5 0.5 0.1]);
            end
        end
        grid(ax_many, 'on');
        xlabel(ax_many, 'Histogram Bin');
        ylabel(ax_many, 'Normalized Amplitude');
        title(ax_many, sprintf('%s: All Normalized Rows', t_name));

        % 3. Median of all frames, then zero the bins outside the window
        median_data = median(pooled_data, 1, 'omitmissing');

        mask_start = max(1, round(t_loc) - left_cutoff);
        mask_end   = min(n_bins, round(t_loc) + right_cutoff);

        m_masked_data = median_data;
        m_masked_data(1 : mask_start-1) = 0;
        m_masked_data(mask_end+1 : end) = 0;

        % Normalize the peak to 1
        m_max = max(m_masked_data);
        if m_max == 0, m_max = 1; end
        m_f_normalized_data = m_masked_data ./ m_max;

        % Set values below 0.01% of the peak to zero
        floor_threshold = 1e-4;
        m_f_normalized_data(m_f_normalized_data < floor_threshold) = 0;

        % Pad with zeros on both sides so the interpolant is zero when shifted
        w = length(m_f_normalized_data);
        m_f_n_spread_data = [zeros(1, w), m_f_normalized_data, zeros(1, w)];

        % 4. Shape-preserving (pchip) interpolant
        ft = 'pchipinterp';
        opts = fitoptions('Method', 'PchipInterpolant');
        opts.ExtrapolationMethod = 'pchip';
        opts.Normalize = 'on';

        % Center the x-axis so the maximum is at x = 0
        [~, idx_max] = max(m_f_n_spread_data);
        x_spread = -(idx_max - 1) : (length(m_f_n_spread_data) - 1 - (idx_max - 1));

        normalized_curve = fit(x_spread', m_f_n_spread_data', ft, opts);

        safe_name = strrep(t_name, ' ', '');
        master_curves.(safe_name) = normalized_curve;

        % Width of the normalized peak (stored for reference)
        [pks, ~, wds, ~] = findpeaks(normalized_curve(-w:w));
        wds_valid = wds(pks == 1);
        if ~isempty(wds_valid)
            curve_peak_widths.(safe_name) = wds_valid(1);
        else
            curve_peak_widths.(safe_name) = 10; % fallback
        end

        % 5. Diagnostic figure: median data and the interpolant
        fig_fit = figure('Name', sprintf('%s - Pchip Fit', t_name), 'Color', 'w');
        ax_fit = axes('Parent', fig_fit);
        hold(ax_fit, 'on');

        x_dense = linspace(min(x_spread), max(x_spread), 2000);
        y_dense = normalized_curve(x_dense);

        plot(ax_fit, x_dense, y_dense, 'r-', 'LineWidth', 2, 'DisplayName', 'PchipInterpolant');
        plot(ax_fit, x_spread, m_f_n_spread_data, 'k.', 'MarkerSize', 12, 'DisplayName', 'Median Data');

        grid(ax_fit, 'on');
        xlabel(ax_fit, 'Relative Histogram Bin (0 = Peak Center)');
        ylabel(ax_fit, 'Normalized Amplitude');
        title(ax_fit, sprintf('%s: Full Padded Median vs Pchip Fit', t_name));
        legend(ax_fit, 'Location', 'northeast');

        xlim(ax_fit, [-left_cutoff*1.2, right_cutoff*1.2]);
    end

    fprintf('Saving master curves to master_curves.mat...\n');
    save('master_curves.mat', 'master_curves', 'curve_peak_widths');
end

%% Stage 3: Single-Curve Fitting %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Each frame is fit with its path's master curve. The position may move up
% to 5 bins either side of the target location.
if run_fit
    fprintf('\n--- Starting Single-Curve Fitting ---\n');

    if ~isfile('master_curves.mat')
        error('master_curves.mat not found. You must run the curve generation stage first.');
    end
    load('master_curves.mat', 'master_curves');

    fopts = fitoptions('Method', 'NonlinearLeastSquares', 'Display', 'Off');

    for idx_file = 1:numel(data_files)
        if isempty(data_files(idx_file).raw_data) || isempty(data_files(idx_file).target_name)
            data_files(idx_file).fit_parameters = [];
            continue;
        end

        t_name = data_files(idx_file).target_name;
        safe_name = strrep(t_name, ' ', '');

        if ~isfield(master_curves, safe_name)
            warning('No master curve found for %s. Skipping file %d.', t_name, idx_file);
            continue;
        end

        specific_curve = master_curves.(safe_name);
        fun = @(height, position, x) height * specific_curve(x - position);
        fitfun = fittype(fun);
        cnames = coeffnames(fitfun); % 'height', 'position'

        target_loc = data_files(idx_file).target_loc;

        fprintf('Fitting file %d / %d: %s (Target Bin: %.2f)\n', ...
            idx_file, numel(data_files), t_name, target_loc);

        tbl = data_files(idx_file).raw_data;
        data_mat = tbl{:, 2:end};
        [n_rows, n_bins] = size(data_mat);
        xdata = (0:(n_bins-1))';

        fit_params_arr = NaN(n_rows, numel(cnames));

        reverseStr = '';
        for r = 1:n_rows
            if mod(r, 10) == 0 || r == 1 || r == n_rows
                msg = sprintf('  Processing row %d / %d', r, n_rows);
                fprintf([reverseStr, msg]);
                reverseStr = repmat(sprintf('\b'), 1, length(msg));
            end

            ydata = data_mat(r, :)';

            % Initial height: largest value within 5 bins of the target
            c_start = max(1, round(target_loc) - 5 + 1);
            c_end   = min(n_bins, round(target_loc) + 5 + 1);
            max_height_guess = max(ydata(c_start:c_end));

            if max_height_guess <= 0, max_height_guess = 1; end

            fopts.StartPoint = [max_height_guess, target_loc];
            fopts.Lower      = [0, target_loc - 5];
            fopts.Upper      = [inf, target_loc + 5];

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
if run_load || run_generate_curves || run_fit
    fprintf('\nSaving processed data to %s...\n', dataFileMat);
    save(dataFileMat, 'data_files', '-v7.3');
    fprintf('Save complete.\n');
end

%% Stage 4: Histogram Player %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if run_player
    fprintf('\nLaunching Interactive Histogram Player...\n');
    interactive_histogram_player_single(data_files, 1)
end

%% Stage 5: Box Plot of Fitted Positions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if run_plots
    fprintf('\n--- Generating Box and Whisker Plot ---\n');

    all_positions = [];
    all_labels = {};

    for i = 1:numel(data_files)
        df = data_files(i);
        if isfield(df, 'fit_parameters') && ~isempty(df.fit_parameters)
            pos = df.fit_parameters.position;
            pos = pos(~isnan(pos));

            all_positions = [all_positions; pos]; %#ok<SAGROW>
            lbl = repmat({df.target_name}, numel(pos), 1);
            all_labels = [all_labels; lbl]; %#ok<SAGROW>
        end
    end

    if ~isempty(all_positions)
        fig_box = figure('Name', 'Peak Locations Boxplot', 'Color', 'w');
        ax_box = axes('Parent', fig_box);

        boxchart(ax_box, categorical(all_labels), all_positions);
        ylabel(ax_box, 'Fitted Location (Bin Number)');
        title(ax_box, 'Variation in Fitted Peak Locations', 'FontSize', 14);
        grid(ax_box, 'on');
        set(ax_box, 'FontSize', 12);

        % Target locations used in this script
        hold(ax_box, 'on');
        yline(ax_box, 66.48, 'r--', 'Peak 1 target (66.48)', 'LabelHorizontalAlignment', 'left');
        yline(ax_box, 82.74, 'b--', 'Peak 2 target (82.74)', 'LabelHorizontalAlignment', 'left');
        yline(ax_box, 86.65, 'g--', 'Peak 3 target (86.65)', 'LabelHorizontalAlignment', 'left');

        fprintf('Boxplot generated successfully.\n');

        fprintf('\n========================================================\n');
        fprintf('   CALIBRATED PEAK LOCATIONS (MIN | MEDIAN | MAX)\n');
        fprintf('========================================================\n');

        target_list = {'Peak 1', 'Peak 2', 'Peak 3'};
        for k = 1:numel(target_list)
            idx = strcmp(all_labels, target_list{k});
            if any(idx)
                min_val = min(all_positions(idx));
                med_val = median(all_positions(idx));
                max_val = max(all_positions(idx));

                fprintf('  %s : Min %6.2f  |  Median %6.2f  |  Max %6.2f bins\n', ...
                    target_list{k}, min_val, med_val, max_val);
            else
                fprintf('  %s : No valid data found\n', target_list{k});
            end
        end
        fprintf('========================================================\n\n');

    else
        warning('No valid fitted position data found to plot.');
    end
end

%% Local Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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

function fig = interactive_histogram_player_single(data_files, idx_file)
%INTERACTIVE_HISTOGRAM_PLAYER_SINGLE Browse frames and single-curve fits.
%   Slider or arrow keys: change frame. File #: change file. L: toggle log
%   y-axis.
    if nargin<2, error('Must provide data_files and idx_file.'); end

    bg_color = [0.15 0.15 0.15];
    ax_color = [0.1 0.1 0.1];
    ui_bg    = [0.25 0.25 0.25];

    fig = figure('Name', 'Single Peak Histogram Player', 'NumberTitle','off', 'Color', bg_color);
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

    hLine = plot(ax, nan, nan, 'w-o', 'MarkerSize',4, 'MarkerFaceColor','w', 'DisplayName','Raw Data');
    hFit  = plot(ax, nan, nan, 'g-', 'LineWidth', 2.5, 'DisplayName','Fitted Peak');

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
        state.master_curves = struct();
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
            applyYLimits(); return;
        end
        if state.isLogScale && y_min_in <= 0
            set(ymin_edit, 'String', '1');
            if y_max_in <= 1, set(ymax_edit, 'String', '10'); end
        end
        state.auto_y = false;
        applyYLimits(); drawnow;
    end
    function autoYCallback()
        state.auto_y = true; applyYLimits(); drawnow;
    end
    function loadFile(newIdx)
        if ~validateFileIndex(newIdx), return; end
        state.idx_file = newIdx;
        tbl = state.data_files(newIdx).raw_data;
        if isempty(tbl) || ~istable(tbl), return; end

        state.timestamps_display = arrayfun(@(v) sprintf('%.3f s', v), tbl{:,1}, 'UniformOutput', false);
        % Zeros are shown as 1 so they appear on the log axis
        data_mat = tbl{:,2:end};
        [n_rows, n_bins] = size(data_mat);
        data_mat(data_mat==0) = 1;

        state.data_mat = data_mat;
        state.n_rows = n_rows;
        state.n_bins = n_bins;

        t_name = state.data_files(newIdx).target_name;
        safe_name = strrep(t_name, ' ', '');

        if state.canDrawFits && isfield(state.data_files, 'fit_parameters') && ~isempty(state.data_files(newIdx).fit_parameters) && isfield(state.master_curves, safe_name)
            f_tbl = state.data_files(newIdx).fit_parameters;
            if all(ismember({'height', 'position'}, f_tbl.Properties.VariableNames))
                state.fit_params = table2array(f_tbl(:, {'height', 'position'}));
                state.active_curve = state.master_curves.(safe_name);
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
        set(hFit, 'XData', nan, 'YData', nan, 'Visible','off');

        if isfield(state.data_files, 'target_name')
            t_str = sprintf('File %d: %s (Target Bin: %.2f)', newIdx, state.data_files(newIdx).target_name, state.data_files(newIdx).target_loc);
        else
            t_str = sprintf('File %d', newIdx);
        end
        set(t, 'String', t_str, 'Interpreter','none');
    end
    function sliderCallback()
        idx = round(get(sld, 'Value'));
        idx = max(1, min(state.n_rows, idx));
        set(sld, 'Value', idx);

        set(hLine, 'YData', state.data_mat(idx,:));
        set(idx_txt, 'String', num2str(idx));

        if state.hasFits
            params = state.fit_params(idx, :);
            if ~any(isnan(params))
                h = params(1); p = params(2);
                xx = linspace(0, state.n_bins-1, 500);
                y = h * state.active_curve(xx - p);
                y(y < 1) = 1;
                set(hFit, 'XData', xx, 'YData', y, 'Visible','on');
            else
                set(hFit, 'Visible','off');
            end
        else
            set(hFit, 'Visible','off');
        end
        drawnow;
    end
    function fileEditCallback()
        val = str2double(get(file_edit, 'String'));
        if isnan(val) || ~validateFileIndex(val)
            set(file_edit, 'String', num2str(state.idx_file)); return;
        end
        loadFile(val); sliderCallback();
    end
    function toggleScale()
        state.isLogScale = logical(get(scale_chk, 'Value'));
        if ~state.auto_y && state.isLogScale
            if str2double(get(ymin_edit, 'String')) <= 0, set(ymin_edit, 'String', '1'); end
        end
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
end
