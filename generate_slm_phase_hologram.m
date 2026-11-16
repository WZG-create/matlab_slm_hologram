function [grayHologram, result] = generate_slm_phase_hologram(components, userConfig)
%GENERATE_SLM_PHASE_HOLOGRAM Generate and export a direct optical phase map.
%
% Unlike generate_slm_hologram, this function does not run GS/IFTA or need a
% target intensity image. It superposes optical phase components directly.

if nargin < 2
    userConfig = struct();
end
config = merge_direct_config(userConfig);
[combinedPhase, descriptions, normalizedComponents] = compose_slm_phase_components(components, config);
backgroundPhase = load_direct_background_phase( ...
    config.background_phase_map_file, config.slm_size);
basePhase = config.phase_offset_rad + backgroundPhase;
combinedPhase = combinedPhase + basePhase;
[activeRegionMask, activeRegion] = slm_active_region_mask(config);
combinedPhase(~activeRegionMask) = basePhase(~activeRegionMask);
[grayHologram, quantizedPhase] = phase_to_slm_gray(combinedPhase, config);
write_direct_outputs(grayHologram, quantizedPhase, descriptions, normalizedComponents, ...
    activeRegionMask, activeRegion, config);

result = struct();
result.phase_rad = quantizedPhase;
result.descriptions = descriptions;
result.components = normalizedComponents;
result.active_region = activeRegion;
if isempty(normalizedComponents)
    result.mode = "reference_phase";
else
    result.mode = "direct_phase_composition";
end
result.config = config;
end

function config = merge_direct_config(userConfig)
defaults = default_slm_config();
if ~isstruct(userConfig)
    error("slm_phase:InvalidConfig", "config must be a structure.");
end
config = defaults;
names = fieldnames(userConfig);
validNames = fieldnames(defaults);
for index = 1:numel(names)
    name = names{index};
    if ~ismember(name, validNames)
        error("slm_phase:UnknownConfig", "Unknown configuration field: %s", name);
    end
    config.(name) = userConfig.(name);
end
if numel(config.slm_size) ~= 2 || any(config.slm_size <= 0) || any(mod(config.slm_size, 1) ~= 0)
    error("slm_phase:InvalidSize", "slm_size must be [height,width].");
end
if config.wavelength_nm <= 0 || config.pixel_pitch_um <= 0
    error("slm_phase:InvalidOptics", "wavelength_nm and pixel_pitch_um must be positive.");
end
end

function write_direct_outputs(grayHologram, phase, descriptions, components, ...
        activeRegionMask, activeRegion, config)
outputDir = char(config.output_dir);
if ~isfolder(outputDir)
    mkdir(outputDir);
end
imwrite(grayHologram, fullfile(outputDir, "hologram.png"), "png");
isReference = isempty(components);
if isReference
    imwrite(grayHologram, fullfile(outputDir, "reference_phase.png"), "png");
end
if config.write_bmp
    imwrite(grayHologram, fullfile(outputDir, "hologram.bmp"), "bmp");
end
phasePreview = uint8(round(mod(phase, 2 * pi) ./ (2 * pi) .* 255));
imwrite(phasePreview, fullfile(outputDir, "phase_preview.png"), "png");
imwrite(uint8(activeRegionMask) .* 255, ...
    fullfile(outputDir, "active_region_mask.png"), "png");
phaseRad = phase;
save(fullfile(outputDir, "phase_data.mat"), "phaseRad", "components", "-v7.3");

metadata = struct();
if isReference
    metadata.algorithm = "Uniform reference phase";
    metadata.output_mode = "reference_phase";
else
    metadata.algorithm = "Direct optical phase composition";
    metadata.output_mode = "direct_phase_composition";
end
metadata.generated_at = char(datetime("now", "Format", "yyyy-MM-dd'T'HH:mm:ss"));
metadata.slm_size = config.slm_size;
metadata.wavelength_nm = config.wavelength_nm;
metadata.pixel_pitch_um = config.pixel_pitch_um;
metadata.phase_levels = config.phase_levels;
metadata.phase_lut_file = char(config.phase_lut_file);
metadata.invert_grayscale = logical(config.invert_grayscale);
metadata.phase_offset_rad = config.phase_offset_rad;
metadata.background_phase_map_file = char(config.background_phase_map_file);
metadata.target_description = char(config.target_description);
metadata.target_parameters = config.target_parameters;
metadata.descriptions = descriptions;
metadata.components = components;
metadata.active_region = activeRegion;
metadata.files = struct( ...
    "hologram", "hologram.png", ...
    "active_region_mask", "active_region_mask.png", ...
    "phase_preview", "phase_preview.png", ...
    "phase_data", "phase_data.mat");
if isReference
    metadata.files.reference = "reference_phase.png";
end
file = fopen(fullfile(outputDir, "metadata.json"), "w");
if file < 0
    error("slm_phase:MetadataWrite", "Unable to write direct-phase metadata.");
end
cleanup = onCleanup(@() fclose(file));
fprintf(file, "%s\n", jsonencode(metadata, "PrettyPrint", true));
end

function phase = load_direct_background_phase(filename, expectedSize)
if isempty(filename) || (isstring(filename) && strlength(filename) == 0)
    phase = zeros(expectedSize);
    return;
end
filename = char(filename);
if ~isfile(filename)
    error("slm_phase:MissingBackgroundMap", "Background phase map does not exist: %s", filename);
end
source = imread(filename);
if isinteger(source)
    source = double(source) ./ double(intmax(class(source)));
elseif islogical(source)
    source = double(source);
else
    source = double(source);
end
if ndims(source) == 3
    if size(source, 3) < 3
        source = source(:, :, 1);
    else
        source = 0.2126 .* source(:, :, 1) + ...
                 0.7152 .* source(:, :, 2) + ...
                 0.0722 .* source(:, :, 3);
    end
elseif ~ismatrix(source)
    error("slm_phase:InvalidBackgroundMap", ...
        "Background phase map must be a two-dimensional or RGB image.");
end
if any(~isfinite(source), "all")
    error("slm_phase:InvalidBackgroundMap", "Background phase map contains non-finite values.");
end
source = min(max(source, 0), 1);
if ~isequal(size(source), expectedSize)
    error("slm_phase:BackgroundSize", ...
        "Background phase map must have the native SLM size [%d %d]; it is not resized automatically.", ...
        expectedSize(1), expectedSize(2));
end
phase = 2 * pi .* source;
end
