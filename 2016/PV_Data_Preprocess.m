clear; clc; close all;

%% USER SETTINGS

% Folder, w którym masz podfoldery 06, 07, 08
baseDir = "2016";   % <- ZMIEN

monthFolders = ["06", "07", "08"];
filePattern = "onemin-Canopy-2016-*.csv";

% Rated DC power of selected PV array [kW]
% Dla Canopy prawdopodobnie ok. 243 kW DC, ale sprawdź w metadanych NIST.
P_rated_kW = 243;

G_STC = 1000; % W/m^2

% Filtry
minIrradiance = 200;   % W/m^2
maxPR = 1.30;          % usuwa oczywiste outliery

% Jeśli auto-detekcja źle wybierze kolumny, wpisz je ręcznie tutaj.
% Najpierw uruchom skrypt i zobacz "Selected columns".
manual.timestamp = "";       % np. "TIMESTAMP"
manual.Pdc       = "";       % np. "InvPDC_kW"
manual.Gpoa      = "";       % np. "SEWSPOAIrrad_Wm2"
manual.Tmodule   = "";       % np. "SEWSModuleTemp_C"
manual.wind      = "";       % np. "WindSpeed_ms" albo zostaw ""

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

%% DETECT COLUMNS FROM FIRST FILE

firstFile = fullfile(files(1).folder, files(1).name);
opts = detectImportOptions(firstFile, "VariableNamingRule", "preserve");
T0 = readtable(firstFile, opts);

names = string(T0.Properties.VariableNames);

fprintf("\nAvailable columns in first file:\n");
disp(names');

timestampCol = pickColumn(names, manual.timestamp, ...
    ["TIMESTAMP", "time", "date"], true);

PdcCol = pickColumn(names, manual.Pdc, ...
    ["InvPDC", "PDC", "DC Power", "DC_Power", "PowerDC", "ShuntPDC"], true);

GpoaCol = pickColumn(names, manual.Gpoa, ...
    ["POA", "POAIrrad", "Plane", "Irrad", "RefCell"], true);

TmoduleCol = pickColumn(names, manual.Tmodule, ...
    ["ModuleTemp", "Module Temp", "Back", "Backsheet", "RTD"], true);

windCol = pickColumn(names, manual.wind, ...
    ["WindSpeed", "Wind Speed", "WindSpd"], false);

fprintf("\nSelected columns:\n");
fprintf("timestamp : %s\n", timestampCol);
fprintf("Pdc       : %s\n", PdcCol);
fprintf("Gpoa      : %s\n", GpoaCol);
fprintf("Tmodule   : %s\n", TmoduleCol);

if strlength(windCol) > 0
    fprintf("wind      : %s\n", windCol);
else
    fprintf("wind      : NOT FOUND, continuing without wind.\n");
end

%% READ AND MERGE DATA

allData = table();

for k = 1:numel(files)
    filePath = fullfile(files(k).folder, files(k).name);
    opts = detectImportOptions(filePath, "VariableNamingRule", "preserve");
    T = readtable(filePath, opts);

    temp = table();

    temp.timestamp = parseTimestamp(T.(timestampCol));
    temp.P_DC_kW = double(T.(PdcCol));
    temp.G_POA_Wm2 = double(T.(GpoaCol));
    temp.T_module_C = double(T.(TmoduleCol));

    if strlength(windCol) > 0 && ismember(windCol, string(T.Properties.VariableNames))
        temp.wind_ms = double(T.(windCol));
    end

    allData = [allData; temp]; %#ok<AGROW>
end

fprintf("\nRaw rows: %d\n", height(allData));

%% BASIC CLEANING

% Sort and remove duplicate timestamps
allData = sortrows(allData, "timestamp");
[~, ia] = unique(allData.timestamp);
allData = allData(ia, :);

% Remove missing required values
requiredVars = ["timestamp", "P_DC_kW", "G_POA_Wm2", "T_module_C"];
allData = rmmissing(allData, "DataVariables", requiredVars);

% Main filters
clean = allData;
clean = clean(clean.G_POA_Wm2 > minIrradiance, :);
clean = clean(clean.P_DC_kW > 0, :);

% Optional: uncomment if you want only around solar noon
% h = hour(clean.timestamp) + minute(clean.timestamp)/60;
% clean = clean(h >= 10 & h <= 15, :);

%% COMPUTE PERFORMANCE RATIO

clean.PR = (clean.P_DC_kW .* G_STC) ./ (P_rated_kW .* clean.G_POA_Wm2);

% Remove unphysical / extreme PR
clean = clean(clean.PR > 0 & clean.PR < maxPR, :);

% Response variable for Bayesian model
clean.logPR = log(clean.PR);

% Scaled predictors
clean.x_T = (clean.T_module_C - 25) ./ 10;  % 1 unit = +10 degC

if ismember("wind_ms", string(clean.Properties.VariableNames))
    clean = rmmissing(clean, "DataVariables", "wind_ms");
    clean.z_wind = (clean.wind_ms - mean(clean.wind_ms, "omitnan")) ./ std(clean.wind_ms, "omitnan");
end

fprintf("Clean rows: %d\n", height(clean));

%% QUICK DIAGNOSTIC PLOTS

figure;
histogram(clean.PR, 80);
xlabel("Performance ratio PR");
ylabel("Count");
title("Distribution of PR");

figure;
scatter(clean.T_module_C, clean.PR, 5, "filled");
xlabel("Module temperature [degC]");
ylabel("PR");
title("PR vs module temperature");
grid on;

figure;
scatter(clean.G_POA_Wm2, clean.P_DC_kW, 5, "filled");
xlabel("POA irradiance [W/m^2]");
ylabel("DC power [kW]");
title("DC power vs POA irradiance");
grid on;

figure;
plot(clean.timestamp, clean.PR, ".");
xlabel("Time");
ylabel("PR");
title("PR over time");
grid on;

%% SAVE CLEAN DATASET

outFile = fullfile(baseDir, "clean_canopy_2016_summer.csv");
writetable(clean, outFile);

fprintf("\nSaved clean dataset to:\n%s\n", outFile);

%% LOCAL FUNCTIONS

function col = pickColumn(names, manualName, candidates, required)
    names = string(names);

    if strlength(manualName) > 0
        manualName = string(manualName);
        if any(names == manualName)
            col = manualName;
            return;
        else
            error("Manual column '%s' not found.", manualName);
        end
    end

    simplifiedNames = lower(regexprep(names, "[^a-zA-Z0-9]", ""));

    for c = candidates
        pattern = lower(regexprep(string(c), "[^a-zA-Z0-9]", ""));
        idx = contains(simplifiedNames, pattern);

        if any(idx)
            col = names(find(idx, 1, "first"));
            return;
        end
    end

    if required
        fprintf("\nAvailable columns:\n");
        disp(names');
        error("Required column not found. Set it manually in USER SETTINGS.");
    else
        col = "";
    end
end

function t = parseTimestamp(x)
    if isdatetime(x)
        t = x;
        return;
    end

    if isnumeric(x)
        t = datetime(x, "ConvertFrom", "datenum");
        return;
    end

    x = string(x);

    formats = [
        "yyyy-MM-dd HH:mm:ss"
        "yyyy-MM-dd HH:mm:ss.SSS"
        "MM/dd/yyyy HH:mm:ss"
        "MM/dd/yyyy HH:mm"
        "yyyy/MM/dd HH:mm:ss"
    ];

    for f = formats'
        try
            t = datetime(x, "InputFormat", f);
            if all(~isnat(t))
                return;
            end
        catch
        end
    end

    % fallback
    t = datetime(x);
end