clear; clc; close all;

%% USER SETTINGS

baseDir = fullfile(pwd, "onemin-Ground-2016/2016");

monthFolders = ["06", "07", "08"];
filePattern = "onemin-Ground-2016-*.csv";

% Ground Mount rated DC power [kW]
P_rated_kW = 271;

% Reference irradiance [W/m^2]
G_STC = 1000;

%% Dataset construction settings

% Dataset 1/2: direct irradiance threshold
minIrradianceForPR = 50; % W/m^2

% Dataset 3/4: daylight window inferred from array irradiance
% For each day: first and last timestamp where G_POA > this threshold.
sunWindowIrradianceThreshold = 50; % W/m^2

% Optional additional margin after sunrise / before sunset.
% Set to 0 because the threshold itself already removes actual night.
sunWindowMarginMinutes = 0;

% 5-minute sampling
sampleEveryMinutes = 5;

%% Loose physical plausibility limits
% These are only sensor-failure filters, not modelling filters.

minIrradiancePhysical = -20;       % W/m^2
maxIrradiancePhysical = 1500;      % W/m^2

minPowerPhysical = -5;             % kW
maxPowerPhysical = 1.5 * P_rated_kW;

minTmodulePhysical = -40;          % degC
maxTmodulePhysical = 100;          % degC

minTambPhysical = -40;             % degC
maxTambPhysical = 60;              % degC

minWindPhysical = -1;              % m/s
maxWindPhysical = 60;              % m/s

%% Column names in CSV

timestampCol = "TIMESTAMP";
PdcCol       = "InvPDC_kW_Avg";
GpoaCol      = "SEWSPOAIrrad_Wm2_Avg";
TmoduleCol   = "SEWSModuleTemp_C_Avg";
TambCol      = "SEWSAmbientTemp_C_Avg";
windCol      = "WindSpeedAve_ms";

%% FIND FILES

files = [];

for m = monthFolders
    folderPath = fullfile(baseDir, m);
    f = dir(fullfile(folderPath, filePattern));
    files = [files; f]; %#ok<AGROW>
end

if isempty(files)
    error("No files found. Check baseDir, monthFolders and filePattern.");
end

fprintf("Found %d files.\n", numel(files));

%% READ AND MERGE DATA

allData = table();

for k = 1:numel(files)

    filePath = fullfile(files(k).folder, files(k).name);

    opts = detectImportOptions(filePath, ...
        "FileType", "text", ...
        "Delimiter", ",", ...
        "VariableNamingRule", "preserve");

    opts.VariableNamesLine = 1;
    opts.DataLines = [2 Inf];

    T = readtable(filePath, opts);

    availableCols = string(T.Properties.VariableNames);
    requiredCols = [timestampCol, PdcCol, GpoaCol, TmoduleCol, TambCol, windCol];

    missingCols = requiredCols(~ismember(requiredCols, availableCols));

    if ~isempty(missingCols)
        fprintf("\nMissing columns in file:\n%s\n", filePath);
        disp(missingCols');
        error("Some required columns are missing.");
    end

    timestamp  = parseTimestamp(T.(timestampCol));
    P_DC_kW    = toNumeric(T.(PdcCol));
    G_POA_Wm2  = toNumeric(T.(GpoaCol));
    T_module_C = toNumeric(T.(TmoduleCol));
    T_amb_C    = toNumeric(T.(TambCol));
    wind_ms    = toNumeric(T.(windCol));

    temp = table(timestamp, P_DC_kW, G_POA_Wm2, ...
                 T_module_C, T_amb_C, wind_ms);

    allData = [allData; temp]; %#ok<AGROW>
end

fprintf("Raw rows: %d\n", height(allData));

%% BASIC CLEANING

allData = sortrows(allData, "timestamp");

% Remove duplicate timestamps
[~, ia] = unique(allData.timestamp);
allData = allData(ia, :);

% Remove missing values in required measurement columns
requiredVars = ["timestamp", "P_DC_kW", "G_POA_Wm2", ...
                "T_module_C", "T_amb_C", "wind_ms"];

allData = rmmissing(allData, "DataVariables", requiredVars);

fprintf("Rows after removing missing values: %d\n", height(allData));

%% ADD TIME VARIABLES

allData.hour = hour(allData.timestamp) + minute(allData.timestamp)/60;
allData.month = month(allData.timestamp);
allData.day = dateshift(allData.timestamp, "start", "day");

%% FILTER ONLY OBVIOUSLY BROKEN MEASUREMENTS

validPhysical = ...
    allData.G_POA_Wm2  >= minIrradiancePhysical & ...
    allData.G_POA_Wm2  <= maxIrradiancePhysical & ...
    allData.P_DC_kW    >= minPowerPhysical & ...
    allData.P_DC_kW    <= maxPowerPhysical & ...
    allData.T_module_C >= minTmodulePhysical & ...
    allData.T_module_C <= maxTmodulePhysical & ...
    allData.T_amb_C    >= minTambPhysical & ...
    allData.T_amb_C    <= maxTambPhysical & ...
    allData.wind_ms    >= minWindPhysical & ...
    allData.wind_ms    <= maxWindPhysical;

fprintf("Removed physically broken rows: %d\n", height(allData) - sum(validPhysical));

cleanBase = allData(validPhysical, :);

fprintf("Rows after physical plausibility filtering: %d\n", height(cleanBase));

%% ADD PR, logPR AND PREDICTORS

cleanBase = addPrAndPredictors(cleanBase, P_rated_kW, G_STC);

%% CREATE 4 DATASETS

% Dataset 1: irradiance > 50 W/m^2, all available 1-minute samples
maskIrr50 = cleanBase.G_POA_Wm2 > minIrradianceForPR;
data_irr50_all = makeModelDataset(cleanBase(maskIrr50, :));

% Dataset 2: irradiance > 50 W/m^2, 5-minute samples
mask5min = mod(minute(cleanBase.timestamp), sampleEveryMinutes) == 0;
data_irr50_5min = makeModelDataset(cleanBase(maskIrr50 & mask5min, :));

% Dataset 3: sun-window per day, all available 1-minute samples
maskSunWindow = makeSunWindowMask( ...
    cleanBase, ...
    sunWindowIrradianceThreshold, ...
    sunWindowMarginMinutes);

data_sunwindow_all = makeModelDataset(cleanBase(maskSunWindow, :));

% Dataset 4: sun-window per day, 5-minute samples
data_sunwindow_5min = makeModelDataset(cleanBase(maskSunWindow & mask5min, :));

%% SAVE DATASETS

out1 = fullfile(baseDir, "ground_model_data_irr50_all.csv");
out2 = fullfile(baseDir, "ground_model_data_irr50_5min.csv");
out3 = fullfile(baseDir, "ground_model_data_sunwindow_all.csv");
out4 = fullfile(baseDir, "ground_model_data_sunwindow_5min.csv");

writetable(data_irr50_all, out1);
writetable(data_irr50_5min, out2);
writetable(data_sunwindow_all, out3);
writetable(data_sunwindow_5min, out4);

fprintf("\nSaved files:\n");
fprintf("1) %s\n", out1);
fprintf("2) %s\n", out2);
fprintf("3) %s\n", out3);
fprintf("4) %s\n", out4);

%% PRINT SUMMARY

printDatasetSummary("irr50 all", data_irr50_all);
printDatasetSummary("irr50 5min", data_irr50_5min);
printDatasetSummary("sunwindow all", data_sunwindow_all);
printDatasetSummary("sunwindow 5min", data_sunwindow_5min);

%% QUICK DIAGNOSTIC PLOTS

figure;
histogram(data_irr50_all.PR, 100);
xlabel("PR");
ylabel("Count");
title("PR distribution: irradiance > 50 W/m^2, all samples");
grid on;

figure;
histogram(data_sunwindow_all.PR, 100);
xlabel("PR");
ylabel("Count");
title("PR distribution: sun-window, all samples");
grid on;

figure;
scatter(data_irr50_all.T_module_C, data_irr50_all.PR, 8, "filled");
xlabel("Module temperature [degC]");
ylabel("PR");
title("PR vs module temperature: irradiance > 50 W/m^2");
grid on;

figure;
scatter(data_sunwindow_all.T_module_C, data_sunwindow_all.PR, 8, "filled");
xlabel("Module temperature [degC]");
ylabel("PR");
title("PR vs module temperature: sun-window");
grid on;

%% LOCAL FUNCTIONS

function T = addPrAndPredictors(T, P_rated_kW, G_STC)

    T.expected_P_DC_kW = P_rated_kW .* T.G_POA_Wm2 ./ G_STC;

    T.PR = T.P_DC_kW ./ T.expected_P_DC_kW;

    % logPR is only defined for positive PR.
    % Rows with nonpositive PR are removed later in makeModelDataset().
    T.logPR = NaN(height(T), 1);
    validLog = isfinite(T.PR) & T.PR > 0;
    T.logPR(validLog) = log(T.PR(validLog));

    T.x_T = (T.T_module_C - 25) ./ 10;

    T.z_wind = (T.wind_ms - mean(T.wind_ms, "omitnan")) ./ ...
                std(T.wind_ms, "omitnan");

    T.z_Tamb = (T.T_amb_C - mean(T.T_amb_C, "omitnan")) ./ ...
                std(T.T_amb_C, "omitnan");

    T.power_ratio = T.PR;

end

function modelData = makeModelDataset(T)

    % Keep only rows usable by the Bayesian model.
    % This is not arbitrary filtering; log(PR) mathematically requires PR > 0.
    modelRows = ...
        isfinite(T.logPR) & ...
        isfinite(T.PR) & ...
        T.PR > 0 & ...
        isfinite(T.x_T) & ...
        isfinite(T.T_module_C);

    T = T(modelRows, :);

    % Recompute day_id so Stan gets consecutive integers: 1, 2, ..., J
    [~, ~, T.day_id] = unique(T.day);

    modelData = T(:, ["timestamp", "day", "day_id", ...
                      "month", "hour", ...
                      "logPR", "PR", "x_T", "z_wind", "z_Tamb", ...
                      "T_module_C", "T_amb_C", "wind_ms", ...
                      "G_POA_Wm2", "P_DC_kW", ...
                      "expected_P_DC_kW", "power_ratio"]);

end

function mask = makeSunWindowMask(T, irradianceThreshold, marginMinutes)

    mask = false(height(T), 1);

    days = unique(T.day);

    for d = 1:numel(days)

        idxDay = find(T.day == days(d));

        idxSun = idxDay(T.G_POA_Wm2(idxDay) > irradianceThreshold);

        if numel(idxSun) < 2
            continue;
        end

        tStart = min(T.timestamp(idxSun)) + minutes(marginMinutes);
        tEnd   = max(T.timestamp(idxSun)) - minutes(marginMinutes);

        mask(idxDay) = T.timestamp(idxDay) >= tStart & ...
                       T.timestamp(idxDay) <= tEnd;
    end

end

function printDatasetSummary(name, T)

    fprintf("\n--- %s ---\n", name);
    fprintf("Rows: %d\n", height(T));

    if height(T) == 0
        return;
    end

    fprintf("Days: %d\n", numel(unique(T.day_id)));
    fprintf("G_POA min/median/max: %.2f / %.2f / %.2f W/m^2\n", ...
        min(T.G_POA_Wm2), median(T.G_POA_Wm2), max(T.G_POA_Wm2));

    fprintf("PR min/median/max: %.4f / %.4f / %.4f\n", ...
        min(T.PR), median(T.PR), max(T.PR));

    fprintf("logPR min/median/max: %.4f / %.4f / %.4f\n", ...
        min(T.logPR), median(T.logPR), max(T.logPR));

end

function t = parseTimestamp(x)

    if isdatetime(x)
        t = x;
        return;
    end

    x = string(x);
    x = strtrim(x);
    x = erase(x, '"');

    % Remove timezone suffix, e.g. -05:00 or +02:00
    x = regexprep(x, "([+-]\d{2}:\d{2})$", "");

    t = datetime(x, ...
        "InputFormat", "yyyy-MM-dd HH:mm:ss", ...
        "Format", "yyyy-MM-dd HH:mm:ss");

end

function y = toNumeric(x)

    if isnumeric(x)
        y = double(x);
        return;
    end

    x = string(x);
    x = strtrim(x);
    x = erase(x, '"');

    x(x == "" | lower(x) == "nan" | lower(x) == "null") = "NaN";

    y = str2double(x);

end