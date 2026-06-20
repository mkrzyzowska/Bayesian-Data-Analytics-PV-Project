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

%% CREATE FINAL DATASET: 09:00-16:00, 5-minute samples

% Keep only measurements between 09:00 and 16:00.
% This avoids low-irradiance sunrise/sunset periods where PR becomes unstable.
maskDaytime = cleanBase.hour >= 9 & cleanBase.hour <= 16;

% Keep only 5-minute timestamps: 00, 05, 10, ..., 55
mask5min = mod(minute(cleanBase.timestamp), sampleEveryMinutes) == 0;

% Final modelling dataset
data_9_16_5min = makeModelDataset(cleanBase(maskDaytime & mask5min, :));

%% SAVE FINAL DATASET

outFinal = fullfile(baseDir, "ground_model_data_9_16_5min.csv");

writetable(data_9_16_5min, outFinal);

fprintf("\nSaved final modelling dataset:\n");
fprintf("%s\n", outFinal);

%% PRINT SUMMARY

printDatasetSummary("09:00-16:00, 5min", data_9_16_5min);

%% QUICK DIAGNOSTIC PLOTS

figure;
histogram(data_9_16_5min.PR, 100);
xlabel("PR");
ylabel("Count");
title("PR distribution: 09:00-16:00, 5-minute samples");
grid on;

figure;
scatter(data_9_16_5min.T_module_C, data_9_16_5min.PR, 8, "filled");
xlabel("Module temperature [degC]");
ylabel("PR");
title("PR vs module temperature: 09:00-16:00, 5-minute samples");
grid on;


%% LOCAL FUNCTIONS

function T = addPrAndPredictors(T, P_rated_kW, G_STC)

    T.expected_P_DC_kW = P_rated_kW .* T.G_POA_Wm2 ./ G_STC;

    T.PR = T.P_DC_kW ./ T.expected_P_DC_kW;

    T.logPR = NaN(height(T), 1);
    validLog = isfinite(T.PR) & T.PR > 0;
    T.logPR(validLog) = log(T.PR(validLog));

    T.power_ratio = T.PR;

end


function modelData = makeModelDataset(T)

    % Keep only rows usable by the Bayesian model
    modelRows = ...
        isfinite(T.logPR) & ...
        isfinite(T.PR) & ...
        T.PR > 0 & ...
        isfinite(T.T_module_C);

    T = T(modelRows, :);

    % Min-max normalization of module temperature to [0, 1]
    T_min = min(T.T_module_C, [], "omitnan");
    T_max = max(T.T_module_C, [], "omitnan");
    T_range = T_max - T_min;

    if T_range <= 0
        error("Temperature range is zero or invalid.");
    end

    T.x_T = (T.T_module_C - T_min) ./ T_range;

    % Store normalization constants in the CSV for reproducibility
    T.T_min_C = repmat(T_min, height(T), 1);
    T.T_max_C = repmat(T_max, height(T), 1);
    T.T_range_C = repmat(T_range, height(T), 1);

    fprintf("T_min = %.2f degC\n", T_min);
    fprintf("T_max = %.2f degC\n", T_max);
    fprintf("T_range = %.2f degC\n", T_range);
    fprintf("x_T min = %.4f\n", min(T.x_T));
    fprintf("x_T max = %.4f\n", max(T.x_T));

    T.z_wind = (T.wind_ms - mean(T.wind_ms, "omitnan")) ./ ...
                std(T.wind_ms, "omitnan");

    T.z_Tamb = (T.T_amb_C - mean(T.T_amb_C, "omitnan")) ./ ...
                std(T.T_amb_C, "omitnan");

    % Recompute day_id so Stan gets consecutive integers: 1, 2, ..., J
    [~, ~, T.day_id] = unique(T.day);

    modelData = T(:, ["timestamp", "day", "day_id", ...
                      "month", "hour", ...
                      "logPR", "PR", "x_T", ...
                      "T_min_C", "T_max_C", "T_range_C", ...
                      "z_wind", "z_Tamb", ...
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