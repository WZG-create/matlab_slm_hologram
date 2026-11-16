function [grayHologram, quantizedPhase, realizedPhase] = phase_to_slm_gray(phase, config)
%PHASE_TO_SLM_GRAY Quantize radians and apply a calibrated 8-bit SLM LUT.

phase = double(phase);
if ~ismatrix(phase) || any(~isfinite(phase), "all")
    error("slm_gray:InvalidPhase", "phase must be a finite two-dimensional matrix.");
end
if ~isequal(size(phase), config.slm_size)
    error("slm_gray:SizeMismatch", "Phase size must equal config.slm_size.");
end
levels = config.phase_levels;
if ~isscalar(levels) || levels < 2 || levels > 256 || mod(levels, 1) ~= 0
    error("slm_gray:InvalidLevels", "phase_levels must be an integer from 2 to 256.");
end

wrapped = mod(phase, 2 * pi);
levelIndex = floor(wrapped ./ (2 * pi) .* levels);
levelIndex = min(max(levelIndex, 0), levels - 1);
quantizedPhase = 2 * pi .* levelIndex ./ levels;
[lutPhase, lutGray] = load_lut(config.phase_lut_file);
grayValues = interp1(lutPhase, lutGray, quantizedPhase, "linear");
grayHologram = uint8(round(min(max(grayValues, 0), 255)));
if config.invert_grayscale
    grayHologram = 255 - grayHologram;
end
% Reconstruct the phase produced by the actual exported gray codes.
% Inversion changes those codes and must not be undone in the replay.
% This is an LUT-based estimate; a measured device can still differ.
effectiveGray = double(grayHologram);
if lutGray(1) < lutGray(end)
    realizedPhase = interp1(lutGray, lutPhase, effectiveGray, "linear", "extrap");
else
    realizedPhase = interp1(flipud(lutGray), flipud(lutPhase), ...
        effectiveGray, "linear", "extrap");
end
realizedPhase = mod(realizedPhase, 2 * pi);
end

function [phase, gray] = load_lut(filename)
if isempty(filename) || (isstring(filename) && strlength(filename) == 0)
    phase = [0; 2 * pi];
    gray = [0; 255];
    return;
end
filename = char(filename);
if ~isfile(filename)
    error("slm_gray:MissingLUT", "Phase LUT file does not exist: %s", filename);
end
lut = readtable(filename, "VariableNamingRule", "preserve");
requiredColumns = {'phase_rad', 'gray'};
if ~all(ismember(requiredColumns, lut.Properties.VariableNames))
    error("slm_gray:InvalidLUT", "LUT must have phase_rad and gray columns.");
end
phase = double(lut.phase_rad);
gray = double(lut.gray);
if numel(phase) < 2 || any(~isfinite(phase)) || any(~isfinite(gray)) || ...
        any(diff(phase) <= 0) || phase(1) > 1e-6 || phase(end) < 2 * pi - 1e-3 || ...
        any(gray < 0) || any(gray > 255) || ...
        ~(all(diff(gray) > 0) || all(diff(gray) < 0))
    error("slm_gray:InvalidLUT", ...
        "LUT phase must strictly increase through 2*pi; gray must be strictly monotonic in 0..255.");
end
end
