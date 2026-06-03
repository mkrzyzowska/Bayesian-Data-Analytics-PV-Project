clear; clc; close all;

%% USER SETTINGS

% Folder z danymi:
% aktualny folder:
% ├── Ground_Data_Preprocess.m
% └── 2016/
%     ├── 06/
%     ├── 07/
%     └── 08/
baseDir = fullfile(pwd, "onemin-Ground-2016/2016");

monthFolders = ["06", "07", "08"];

% Pattern dla Ground Mount
filePattern = "onemin-Ground-2016-*.csv";

% Ground Mount rated DC power [kW]
% NIST Ground Mount Array: około 271 kW DC
P_rated_kW = 271;

% Reference irradiance
G_STC = 1000; % W/m^2

% Filtering settings
minIrradiance = 700;      % W/m^2
maxIrradianceChange = 30; % W/m^2 per minute
minHour = 11;
maxHour = 14;

minPR = 0.75;
maxPR = 1.15;

% Column names in CSV
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

    % Check required columns
    availableCols = string(T.Properties.VariableNames);
    requiredCols = [timestampCol, PdcCol, GpoaCol, TmoduleCol, TambCol, windCol];

    missingCols = requiredCols(~ismember(requiredCols, availableCols));

    if ~isempty(missingCols)
        fprintf("\nMissing columns in file:\n%s\n", filePath);
        disp(missingCols');
        error("Some required columns are missing.");
    end

    % Convert columns
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

allData = sortrows(allData, 'timestamp');

% Remove duplicate timestamps
[~, ia] = unique(allData.timestamp);
allData = allData(ia, :);

% Remove missing values
requiredVars = ["timestamp", "P_DC_kW", "G_POA_Wm2", ...
                "T_module_C", "T_amb_C", "wind_ms"];

allData = rmmissing(allData, "DataVariables", requiredVars);

%% ADD TIME VARIABLES

allData.hour = hour(allData.timestamp) + minute(allData.timestamp)/60;
allData.month = month(allData.timestamp);
allData.day = dateshift(allData.timestamp, "start", "day");

%% COMPUTE IRRADIANCE CHANGE

allData.dG_POA = [NaN; abs(diff(allData.G_POA_Wm2))];

% Do not compare last sample of one day with first sample of next day
newDay = [true; allData.day(2:end) ~= allData.day(1:end-1)];
allData.dG_POA(newDay) = NaN;

%% FILTER DATA

clean = allData;

% High irradiance only
clean = clean(clean.G_POA_Wm2 > minIrradiance, :);

% Positive DC power only
clean = clean(clean.P_DC_kW > 0, :);

% Near solar noon only
clean = clean(clean.hour >= minHour & clean.hour <= maxHour, :);

% Remove unstable irradiance / cloudy transients
clean = clean(clean.dG_POA < maxIrradianceChange, :);

%% COMPUTE PERFORMANCE RATIO

clean.expected_P_DC_kW = P_rated_kW .* clean.G_POA_Wm2 ./ G_STC;

clean.PR = clean.P_DC_kW ./ clean.expected_P_DC_kW;

% Remove suspicious PR values
clean = clean(clean.PR > minPR & clean.PR < maxPR, :);

% Response variable for Bayesian model
clean.logPR = log(clean.PR);

% Scaled predictors
clean.x_T = (clean.T_module_C - 25) ./ 10; % +1 means +10 degC

clean.z_wind = (clean.wind_ms - mean(clean.wind_ms, "omitnan")) ./ ...
                std(clean.wind_ms, "omitnan");

clean.z_Tamb = (clean.T_amb_C - mean(clean.T_amb_C, "omitnan")) ./ ...
                std(clean.T_amb_C, "omitnan");

% Additional variable, same as PR but clearer name for plots
clean.power_ratio = clean.P_DC_kW ./ clean.expected_P_DC_kW;

fprintf("Clean rows: %d\n", height(clean));

%% SUMMARY

fprintf("\nPR summary:\n");
fprintf("mean PR = %.4f\n", mean(clean.PR, "omitnan"));
fprintf("std  PR = %.4f\n", std(clean.PR, "omitnan"));
fprintf("min  PR = %.4f\n", min(clean.PR));
fprintf("max  PR = %.4f\n", max(clean.PR));

fprintf("\nTemperature summary:\n");
fprintf("min Tmodule = %.2f degC\n", min(clean.T_module_C));
fprintf("max Tmodule = %.2f degC\n", max(clean.T_module_C));

fprintf("\nSamples per month:\n");
[Gm, months] = findgroups(clean.month);
counts = splitapply(@numel, clean.PR, Gm);
disp(table(months, counts));

%% DIAGNOSTIC PLOTS

% 1. Distribution of PR
figure;
histogram(clean.PR, 80);
xlabel("Performance ratio PR");
ylabel("Count");
title("Distribution of PR");
grid on;

% 2. PR vs module temperature
figure;
scatter(clean.T_module_C, clean.PR, 8, "filled"); hold on;
p = polyfit(clean.T_module_C, clean.PR, 1);
xfit = linspace(min(clean.T_module_C), max(clean.T_module_C), 100);
yfit = polyval(p, xfit);
plot(xfit, yfit, "LineWidth", 2);
xlabel("Module temperature [degC]");
ylabel("PR");
title("PR vs module temperature");
grid on;

% 3. DC power vs POA irradiance
figure;
scatter(clean.G_POA_Wm2, clean.P_DC_kW, 8, "filled");
xlabel("POA irradiance [W/m^2]");
ylabel("DC power [kW]");
title("DC power vs POA irradiance");
grid on;

% 4. PR vs wind speed
figure;
scatter(clean.wind_ms, clean.PR, 8, "filled"); hold on;
p = polyfit(clean.wind_ms, clean.PR, 1);
xfit = linspace(min(clean.wind_ms), max(clean.wind_ms), 100);
yfit = polyval(p, xfit);
plot(xfit, yfit, "LineWidth", 2);
xlabel("Wind speed [m/s]");
ylabel("PR");
title("PR vs wind speed");
grid on;

% 5. Module temperature vs wind speed
figure;
scatter(clean.wind_ms, clean.T_module_C, 8, "filled"); hold on;
p = polyfit(clean.wind_ms, clean.T_module_C, 1);
xfit = linspace(min(clean.wind_ms), max(clean.wind_ms), 100);
yfit = polyval(p, xfit);
plot(xfit, yfit, "LineWidth", 2);
xlabel("Wind speed [m/s]");
ylabel("Module temperature [degC]");
title("Module temperature vs wind speed");
grid on;

% 6. PR over time
figure;
plot(clean.timestamp, clean.PR, ".");
xlabel("Time");
ylabel("PR");
title("PR over time");
grid on;

% 7. PR by month
figure;
boxchart(clean.month, clean.PR);
xlabel("Month");
ylabel("PR");
title("PR by month");
grid on;

% 8. PR vs hour of day
figure;
scatter(clean.hour, clean.PR, 8, "filled");
xlabel("Hour of day");
ylabel("PR");
title("PR vs hour of day");
grid on;

%% SAVE DATASETS

% Full cleaned dataset for EDA
cleanOutFile = fullfile(baseDir, "clean_ground_2016_summer.csv");
writetable(clean, cleanOutFile);

fprintf("\nSaved full clean dataset to:\n%s\n", cleanOutFile);

% Smaller dataset for Bayesian modelling
modelData = clean(:, ["timestamp", "day", "month", "hour", ...
                      "logPR", "PR", "x_T", "z_wind", ...
                      "T_module_C", "wind_ms", ...
                      "G_POA_Wm2", "P_DC_kW", ...
                      "expected_P_DC_kW", "power_ratio"]);

modelOutFile = fullfile(baseDir, "ground_model_data.csv");
writetable(modelData, modelOutFile);

fprintf("\nSaved model dataset to:\n%s\n", modelOutFile);

%% LOCAL FUNCTIONS

function t = parseTimestamp(x)

    if isdatetime(x)
        t = x;
        return;
    end

    x = string(x);
    x = strtrim(x);

    % Remove quotes if present
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

    % Convert empty / invalid text fields to NaN
    x(x == "" | lower(x) == "nan" | lower(x) == "null") = "NaN";

    y = str2double(x);

end