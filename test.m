baseDir = fullfile(pwd, "2016");
testFile = fullfile(baseDir, "06", "onemin-Canopy-2016-06-01.csv");

lines = readlines(testFile);

for i = 1:min(30, numel(lines))
    fprintf("%2d: %s\n", i, lines(i));
end