function [grayHologram, result] = generate_slm_hologram(inputImage, userConfig)
%GENERATE_SLM_HOLOGRAM Generate an 8-bit phase-only Fourier hologram.
%
% [grayHologram, result] = generate_slm_hologram(inputImage, config)
% accepts an image filename or a numeric grayscale/RGB image.  The generated
% uint8 matrix is directly writable as an 8-bit grayscale SLM image.  The
% target is reconstructed in the Fourier plane of a phase-only SLM using
% GS, WGS for multi-focus arrays, or MRAF for continuous targets.
%
% inputImage: image filename, HxW grayscale array, or HxWx3 RGB array.
% userConfig: structure based on default_slm_config().

if nargin < 2
    userConfig = struct();
end
config = merge_and_validate_config(userConfig);

target = load_and_fit_target(inputImage, config.slm_size, config.preserve_aspect);
target = min(max(target, 0), 1) .^ config.target_gamma;
targetAmplitude = sqrt(target);
targetEnergy = sum(targetAmplitude(:).^2);
if targetEnergy <= 0
    error("slm_hologram:BlackTarget", ...
        "The target is entirely black and cannot define a hologram.");
end
targetPreview = target;
wgs = prepare_wgs_context(target, targetAmplitude, config);
[activeRegionMask, activeRegion] = slm_active_region_mask(config);
illuminationAmplitude = load_illumination_amplitude(config.illumination_amplitude_file, config.slm_size);
slmAmplitude = illuminationAmplitude .* double(activeRegionMask);
inputEnergy = sum(slmAmplitude.^2, "all");
if inputEnergy <= 0
    error("slm_hologram:NoIllumination", "No light reaches the active SLM region.");
end
targetAmplitude = targetAmplitude .* sqrt(numel(targetAmplitude) / targetEnergy);
mraf = prepare_mraf_context(target, config, wgs.resolved_algorithm);
if mraf.enabled
    wgs.resolved_algorithm = "mraf";
end

previousRng = rng;
rngCleanup = onCleanup(@() rng(previousRng));
if ~isempty(config.random_seed)
    rng(config.random_seed, "twister");
end

phase = 2 * pi * rand(config.slm_size);
errors = zeros(config.iterations, 1);
spotUniformityHistory = nan(config.iterations, 1);
normalization = sqrt(inputEnergy);
spotWeights = ones(size(wgs.focus_centers_px, 1), 1);

for iteration = 1:config.iterations
    slmField = slmAmplitude .* exp(1i * phase);
    fourierField = fftshift(fft2(slmField)) ./ normalization;
    constrainedAmplitude = targetAmplitude;
    if wgs.enabled
        spotPowers = measure_spot_powers(fourierField, ...
            wgs.focus_centers_px, wgs.spot_radius_px);
        spotUniformityHistory(iteration) = calculate_spot_uniformity(spotPowers);
        measuredAmplitude = sqrt(max(spotPowers, 0));
        meanAmplitude = mean(measuredAmplitude);
        floorAmplitude = max(meanAmplitude * 1e-6, eps);
        correction = (meanAmplitude ./ max(measuredAmplitude, floorAmplitude)) .^ ...
            config.wgs_feedback_strength;
        spotWeights = spotWeights .* correction;
        spotWeights = min(max(spotWeights, 0.05), 20);
        spotWeights = spotWeights ./ mean(spotWeights);
        constrainedAmplitude = apply_wgs_weights(targetAmplitude, wgs, spotWeights);
    end
    constrainedFourier = constrainedAmplitude .* exp(1i * angle(fourierField));
    if mraf.enabled
        constrainedFourier(mraf.signal_mask) = ...
            sqrt(config.mraf_signal_fraction) .* constrainedFourier(mraf.signal_mask);
        constrainedFourier(~mraf.signal_mask) = ...
            sqrt(1 - config.mraf_signal_fraction) .* fourierField(~mraf.signal_mask);
    end
    backField = ifft2(ifftshift(constrainedFourier)) .* normalization;
    phase = angle(backField);

    reconstructedIntensity = normalized_intensity(fourierField);
    errors(iteration) = mean((reconstructedIntensity - targetPreview).^2, "all");
    if ~isempty(config.progress_callback)
        invoke_progress_callback(config.progress_callback, iteration, config.iterations, ...
            errors(iteration), spotUniformityHistory(iteration), wgs.resolved_algorithm);
    end
end

finalField = fftshift(fft2(slmAmplitude .* exp(1i * phase))) ./ normalization;
preExportMSE = mean((normalized_intensity(finalField) - targetPreview).^2, "all");
finalSpotPowers = zeros(0, 1);
finalSpotUniformity = NaN;
[phaseWithSuperposition, backgroundPhase] = add_phase_superpositions(phase, config);
normalizedPhaseComponents = struct("type", {}, "parameters", {}, "description", {});
if ~isempty(config.phase_components)
    [additionalPhase, ~, normalizedPhaseComponents] = compose_slm_phase_components(config.phase_components, config);
    phaseWithSuperposition = mod(phaseWithSuperposition + additionalPhase, 2 * pi);
end
basePhase = mod(config.phase_offset_rad + backgroundPhase, 2 * pi);
phaseWithSuperposition(~activeRegionMask) = basePhase(~activeRegionMask);
[grayHologram, quantizedPhase, realizedPhase] = phase_to_slm_gray(phaseWithSuperposition, config);
% The original GS preview above is retained as a pre-export diagnostic.
% The public preview and final metrics are recomputed from exported gray.
carrierPhase = carrier_phase(config);
displayField = illuminationAmplitude .* exp(1i * realizedPhase);
finalDisplayField = fftshift(fft2(displayField)) ./ sqrt(sum(illuminationAmplitude.^2, "all"));
fullReconstruction = normalized_intensity(finalDisplayField);
alignedField = fftshift(fft2(displayField .* exp(-1i * carrierPhase))) ./ ...
    sqrt(sum(illuminationAmplitude.^2, "all"));
reconstruction = normalized_intensity(alignedField);
finalGlobalMSE = mean((reconstruction - targetPreview).^2, "all");
signalMetrics = evaluate_signal_region(reconstruction, targetPreview);
errors(end) = finalGlobalMSE;
if wgs.enabled
    finalSpotPowers = measure_spot_powers(alignedField, ...
        wgs.focus_centers_px, wgs.spot_radius_px);
    finalSpotUniformity = calculate_spot_uniformity(finalSpotPowers);
    spotUniformityHistory(end) = finalSpotUniformity;
end

algorithmInfo = struct();
algorithmInfo.requested = char(config.algorithm);
algorithmInfo.resolved = char(wgs.resolved_algorithm);
algorithmInfo.focus_centers_px = wgs.focus_centers_px;
algorithmInfo.spot_radius_px = wgs.spot_radius_px;
algorithmInfo.feedback_strength = config.wgs_feedback_strength;
algorithmInfo.final_weights = spotWeights;
algorithmInfo.final_spot_powers = finalSpotPowers;
algorithmInfo.uniformity_history = spotUniformityHistory;
algorithmInfo.final_uniformity = finalSpotUniformity;
algorithmInfo.mraf_signal_fraction = config.mraf_signal_fraction;
algorithmInfo.mraf_signal_pixel_count = nnz(mraf.signal_mask);
algorithmInfo.signal_metrics = signalMetrics;
algorithmInfo.pre_export_normalized_mse = preExportMSE;
write_outputs(grayHologram, reconstruction, fullReconstruction, target, errors, ...
    normalizedPhaseComponents, algorithmInfo, activeRegionMask, activeRegion, config);

result = struct();
result.phase_rad = quantizedPhase;
result.reconstruction = reconstruction;
result.reconstruction_full = fullReconstruction;
result.target_intensity = target;
result.error_history = errors;
result.final_normalized_mse = errors(end);
result.pre_export_normalized_mse = algorithmInfo.pre_export_normalized_mse;
result.signal_metrics = signalMetrics;
result.algorithm = wgs.resolved_algorithm;
result.algorithm_requested = string(config.algorithm);
result.focus_centers_px = wgs.focus_centers_px;
result.wgs_spot_radius_px = wgs.spot_radius_px;
result.wgs_final_weights = spotWeights;
result.final_spot_powers = finalSpotPowers;
result.spot_uniformity_history = spotUniformityHistory;
result.final_spot_uniformity = finalSpotUniformity;
result.phase_components = normalizedPhaseComponents;
result.active_region = activeRegion;
result.config = config;
end

function config = merge_and_validate_config(userConfig)
defaults = default_slm_config();
if ~isstruct(userConfig)
    error("slm_hologram:InvalidConfig", "config must be a structure.");
end
config = defaults;
names = fieldnames(userConfig);
validNames = fieldnames(defaults);
for index = 1:numel(names)
    name = names{index};
    if ~ismember(name, validNames)
        error("slm_hologram:UnknownConfig", "Unknown configuration field: %s", name);
    end
    config.(name) = userConfig.(name);
end

if ~isnumeric(config.slm_size) || numel(config.slm_size) ~= 2 || ...
        any(config.slm_size <= 0) || any(mod(config.slm_size, 1) ~= 0)
    error("slm_hologram:InvalidSize", "slm_size must be [positive_integer_height, positive_integer_width].");
end
config.slm_size = double(reshape(config.slm_size, 1, 2));
if ~isscalar(config.iterations) || config.iterations <= 0 || mod(config.iterations, 1) ~= 0
    error("slm_hologram:InvalidIterations", "iterations must be a positive integer.");
end
if ~(isempty(config.progress_callback) || isa(config.progress_callback, "function_handle"))
    error("slm_hologram:InvalidCallback", "progress_callback must be empty or a function handle.");
end
if ~(ischar(config.algorithm) || (isstring(config.algorithm) && isscalar(config.algorithm)))
    error("slm_hologram:InvalidAlgorithm", "algorithm must be auto, gs, wgs, or mraf.");
end
config.algorithm = lower(string(config.algorithm));
if ~ismember(config.algorithm, ["auto", "gs", "wgs", "mraf"])
    error("slm_hologram:InvalidAlgorithm", "algorithm must be auto, gs, wgs, or mraf.");
end
if ~isscalar(config.mraf_signal_threshold) || ~isfinite(config.mraf_signal_threshold) || ...
        config.mraf_signal_threshold <= 0 || config.mraf_signal_threshold >= 1 || ...
        ~isscalar(config.mraf_guard_px) || ~isfinite(config.mraf_guard_px) || ...
        config.mraf_guard_px < 0 || mod(config.mraf_guard_px, 1) ~= 0 || ...
        ~isscalar(config.mraf_signal_fraction) || ~isfinite(config.mraf_signal_fraction) || ...
        config.mraf_signal_fraction <= 0 || config.mraf_signal_fraction >= 1
    error("slm_hologram:InvalidMRAF", ...
        "MRAF threshold and signal fraction must be in (0,1), and guard_px a nonnegative integer.");
end
if ~isscalar(config.wgs_feedback_strength) || ~isfinite(config.wgs_feedback_strength) || ...
        config.wgs_feedback_strength <= 0 || config.wgs_feedback_strength > 1
    error("slm_hologram:InvalidWGSFeedback", ...
        "wgs_feedback_strength must be greater than 0 and no greater than 1.");
end
if ~isscalar(config.wgs_spot_radius_px) || ~isfinite(config.wgs_spot_radius_px) || ...
        config.wgs_spot_radius_px < 0
    error("slm_hologram:InvalidWGSSpotRadius", ...
        "wgs_spot_radius_px must be zero (automatic) or positive.");
end
if ~isscalar(config.wgs_detection_threshold) || ~isfinite(config.wgs_detection_threshold) || ...
        config.wgs_detection_threshold <= 0 || config.wgs_detection_threshold > 1
    error("slm_hologram:InvalidWGSThreshold", ...
        "wgs_detection_threshold must be in the interval (0,1].");
end
if ~isscalar(config.wgs_max_spots) || config.wgs_max_spots < 2 || ...
        mod(config.wgs_max_spots, 1) ~= 0
    error("slm_hologram:InvalidWGSMaxSpots", ...
        "wgs_max_spots must be an integer of at least 2.");
end
if ~isnumeric(config.wgs_focus_centers_px) || ...
        (~isempty(config.wgs_focus_centers_px) && size(config.wgs_focus_centers_px, 2) ~= 2) || ...
        any(~isfinite(config.wgs_focus_centers_px), "all")
    error("slm_hologram:InvalidWGSCenters", ...
        "wgs_focus_centers_px must be an N-by-2 finite [x,y] array.");
end
if ~isscalar(config.target_gamma) || config.target_gamma <= 0
    error("slm_hologram:InvalidGamma", "target_gamma must be positive.");
end
if ~(ischar(config.target_description) || isstring(config.target_description)) || ...
        ~isstruct(config.target_parameters)
    error("slm_hologram:InvalidTargetMetadata", ...
        "target_description must be text and target_parameters must be a structure.");
end
if ~isstruct(config.phase_components) || ...
        (~isempty(config.phase_components) && ...
        ~all(isfield(config.phase_components, {'type', 'parameters'}), "all"))
    error("slm_hologram:InvalidPhaseComponents", ...
        "phase_components must be a struct array with type and parameters fields.");
end
if ~isscalar(config.phase_levels) || config.phase_levels < 2 || ...
        config.phase_levels > 256 || mod(config.phase_levels, 1) ~= 0
    error("slm_hologram:InvalidLevels", "phase_levels must be an integer from 2 to 256.");
end
if ~isscalar(config.grating_period_x_px) || ~isscalar(config.grating_period_y_px) || ...
        config.grating_period_x_px < 0 || config.grating_period_y_px < 0
    error("slm_hologram:InvalidGrating", "Carrier periods must be zero or positive.");
end
if ~isscalar(config.phase_offset_rad) || ~isfinite(config.phase_offset_rad)
    error("slm_hologram:InvalidPhaseOffset", "phase_offset_rad must be finite.");
end
if ~isscalar(config.wavelength_nm) || config.wavelength_nm <= 0 || ...
        ~isscalar(config.pixel_pitch_um) || config.pixel_pitch_um <= 0
    error("slm_hologram:InvalidOptics", "wavelength_nm and pixel_pitch_um must be positive.");
end
if isempty(config.zernike_radius_px)
    config.zernike_radius_px = min(config.slm_size) / 2 - 0.5;
elseif ~isscalar(config.zernike_radius_px) || config.zernike_radius_px <= 0 || ...
        ~isfinite(config.zernike_radius_px)
    error("slm_hologram:InvalidZernikeRadius", "zernike_radius_px must be empty or a positive scalar.");
end
wavefrontNames = {"tilt_x_cycles", "tilt_y_cycles", "defocus_waves", ...
    "astigmatism_0_waves", "astigmatism_45_waves"};
for index = 1:numel(wavefrontNames)
    value = config.(wavefrontNames{index});
    if ~isscalar(value) || ~isfinite(value)
        error("slm_hologram:InvalidWavefront", "%s must be a finite scalar.", wavefrontNames{index});
    end
end
if ~isscalar(config.fresnel_focal_length_mm) || ~isfinite(config.fresnel_focal_length_mm)
    error("slm_hologram:InvalidFresnelLens", "fresnel_focal_length_mm must be a finite scalar; use 0 to disable it.");
end
if ~(islogical(config.preserve_aspect) || isnumeric(config.preserve_aspect)) || ...
        ~(islogical(config.invert_grayscale) || isnumeric(config.invert_grayscale))
    error("slm_hologram:InvalidBoolean", "preserve_aspect and invert_grayscale must be logical values.");
end
end

function context = prepare_wgs_context(target, targetAmplitude, config)
context = struct( ...
    "enabled", false, ...
    "resolved_algorithm", "gs", ...
    "focus_centers_px", zeros(0, 2), ...
    "spot_radius_px", 0, ...
    "active_indices", zeros(0, 1), ...
    "active_labels", zeros(0, 1));

centers = double(config.wgs_focus_centers_px);
if isempty(centers) && isfield(config.target_parameters, "focus_centers_px")
    centers = double(config.target_parameters.focus_centers_px);
end

spotRadius = config.wgs_spot_radius_px;
if spotRadius == 0
    if isfield(config.target_parameters, "spot_sigma_px") && ...
            isscalar(config.target_parameters.spot_sigma_px) && ...
            isfinite(config.target_parameters.spot_sigma_px)
        spotRadius = max(1, ceil(2 * config.target_parameters.spot_sigma_px));
    else
        spotRadius = 2;
    end
end

if config.algorithm == "wgs" && size(centers, 1) < 2
    centers = detect_wgs_focus_centers(target, spotRadius, ...
        config.wgs_detection_threshold, config.wgs_max_spots);
end
if size(centers, 1) > config.wgs_max_spots
    error("slm_hologram:TooManyWGSSpots", ...
        "WGS found %d spots, exceeding wgs_max_spots=%d.", ...
        size(centers, 1), config.wgs_max_spots);
end
if ~isempty(centers)
    width = config.slm_size(2);
    height = config.slm_size(1);
    if any(centers(:, 1) < 1 | centers(:, 1) > width | ...
            centers(:, 2) < 1 | centers(:, 2) > height)
        error("slm_hologram:WGSCenterOutside", ...
            "Every WGS focus center must lie inside the target canvas.");
    end
end

useWgs = config.algorithm == "wgs" || ...
    (config.algorithm == "auto" && size(centers, 1) >= 2);
if ~useWgs
    context.focus_centers_px = centers;
    context.spot_radius_px = spotRadius;
    return;
end
if size(centers, 1) < 2
    error("slm_hologram:InsufficientWGSSpots", ...
        "WGS requires at least two isolated focal spots. Use GS for a continuous target.");
end

activeIndices = find(targetAmplitude > max(targetAmplitude, [], "all") * 1e-8);
[activeRows, activeColumns] = ind2sub(size(targetAmplitude), activeIndices);
nearestDistance = inf(size(activeIndices));
activeLabels = ones(size(activeIndices));
for spotIndex = 1:size(centers, 1)
    distanceSquared = (activeColumns - centers(spotIndex, 1)).^2 + ...
        (activeRows - centers(spotIndex, 2)).^2;
    closer = distanceSquared < nearestDistance;
    nearestDistance(closer) = distanceSquared(closer);
    activeLabels(closer) = spotIndex;
end

context.enabled = true;
context.resolved_algorithm = "wgs";
context.focus_centers_px = centers;
context.spot_radius_px = spotRadius;
context.active_indices = activeIndices;
context.active_labels = activeLabels;
end

function context = prepare_mraf_context(target, config, resolvedAlgorithm)
patternType = "";
if isfield(config.target_parameters, "pattern_type")
    patternType = string(config.target_parameters.pattern_type);
end
enabled = config.algorithm == "mraf" || ...
    (config.algorithm == "auto" && resolvedAlgorithm ~= "wgs" && ...
    ismember(patternType, ["annulus", "disk"]));
context = struct("enabled", enabled, "signal_mask", false(size(target)));
if ~enabled
    return;
end
core = target >= config.mraf_signal_threshold * max(target, [], "all");
guard = config.mraf_guard_px;
if guard > 0
    horizontal = conv2(double(core), ones(1, 2 * guard + 1), "same") > 0;
    context.signal_mask = conv2(double(horizontal), ones(2 * guard + 1, 1), "same") > 0;
else
    context.signal_mask = core;
end
if all(context.signal_mask, "all")
    error("slm_hologram:MRAFNoNoiseRegion", ...
        "MRAF signal region covers the entire canvas; reduce the guard or target size.");
end
end

function amplitude = load_illumination_amplitude(filename, expectedSize)
if isempty(filename) || (isstring(filename) && strlength(filename) == 0)
    amplitude = ones(expectedSize);
    return;
end
filename = char(filename);
if ~isfile(filename)
    error("slm_hologram:MissingIllumination", ...
        "Illumination amplitude map does not exist: %s", filename);
end
amplitude = image_to_grayscale_unit(imread(filename));
if ~isequal(size(amplitude), expectedSize)
    error("slm_hologram:IlluminationSize", ...
        "Illumination amplitude map must have native SLM size [%d %d].", ...
        expectedSize(1), expectedSize(2));
end
if ~any(amplitude > 0, "all")
    error("slm_hologram:NoIllumination", "Illumination amplitude map is black.");
end
end

function centers = detect_wgs_focus_centers(target, spotRadius, thresholdFraction, maxSpots)
work = double(target);
maximum = max(work, [], "all");
threshold = maximum * thresholdFraction;
suppressionRadius = max(2, ceil(2.5 * spotRadius));
centers = zeros(0, 2);
[height, width] = size(work);
while true
    [peak, linearIndex] = max(work, [], "all", "linear");
    if peak < threshold || peak <= 0
        break;
    end
    [row, column] = ind2sub([height, width], linearIndex);
    centers(end + 1, :) = [column, row]; %#ok<AGROW>
    if size(centers, 1) >= maxSpots
        error("slm_hologram:WGSDetectionAmbiguous", ...
            "WGS peak detection reached %d spots. The target may be continuous; use GS or provide explicit focus centers.", ...
            maxSpots);
    end
    xRange = max(1, column - suppressionRadius):min(width, column + suppressionRadius);
    yRange = max(1, row - suppressionRadius):min(height, row + suppressionRadius);
    [x, y] = meshgrid(xRange, yRange);
    disk = (x - column).^2 + (y - row).^2 <= suppressionRadius^2;
    patch = work(yRange, xRange);
    patch(disk) = 0;
    work(yRange, xRange) = patch;
end
end

function weightedAmplitude = apply_wgs_weights(targetAmplitude, context, spotWeights)
weightedAmplitude = targetAmplitude;
weightedAmplitude(context.active_indices) = ...
    targetAmplitude(context.active_indices) .* spotWeights(context.active_labels);
energy = sum(weightedAmplitude.^2, "all");
weightedAmplitude = weightedAmplitude .* sqrt(numel(weightedAmplitude) / energy);
end

function powers = measure_spot_powers(field, centers, radius)
[height, width] = size(field);
intensity = abs(field).^2;
powers = zeros(size(centers, 1), 1);
integerRadius = ceil(radius);
for index = 1:size(centers, 1)
    centerX = centers(index, 1);
    centerY = centers(index, 2);
    xRange = max(1, floor(centerX - integerRadius)):min(width, ceil(centerX + integerRadius));
    yRange = max(1, floor(centerY - integerRadius)):min(height, ceil(centerY + integerRadius));
    [x, y] = meshgrid(xRange, yRange);
    aperture = (x - centerX).^2 + (y - centerY).^2 <= radius^2;
    patch = intensity(yRange, xRange);
    powers(index) = sum(patch(aperture), "all");
end
end

function uniformity = calculate_spot_uniformity(powers)
if numel(powers) < 2 || any(~isfinite(powers))
    uniformity = NaN;
    return;
end
minimum = min(powers);
maximum = max(powers);
if maximum + minimum <= 0
    uniformity = 0;
else
    uniformity = 1 - (maximum - minimum) / (maximum + minimum);
end
end

function invoke_progress_callback(callback, completed, total, mse, uniformity, algorithm)
try
    argumentCount = nargin(callback);
catch
    argumentCount = 3;
end
if argumentCount < 0 || argumentCount >= 5
    callback(completed, total, mse, uniformity, algorithm);
else
    callback(completed, total, mse);
end
end

function target = load_and_fit_target(inputImage, outputSize, preserveAspect)
if ischar(inputImage) || isstring(inputImage)
    filename = char(inputImage);
    if ~isfile(filename)
        error("slm_hologram:MissingTarget", "Target image does not exist: %s", filename);
    end
    source = imread(filename);
elseif isnumeric(inputImage) || islogical(inputImage)
    source = inputImage;
else
    error("slm_hologram:InvalidTarget", "inputImage must be a filename or numeric image array.");
end

source = image_to_grayscale_unit(source);
if preserveAspect
    sourceHeight = size(source, 1);
    sourceWidth = size(source, 2);
    scale = min(outputSize(1) / sourceHeight, outputSize(2) / sourceWidth);
    resizedHeight = max(1, round(sourceHeight * scale));
    resizedWidth = max(1, round(sourceWidth * scale));
    resized = resize_gray(source, resizedHeight, resizedWidth);
    target = zeros(outputSize);
    rowStart = floor((outputSize(1) - resizedHeight) / 2) + 1;
    colStart = floor((outputSize(2) - resizedWidth) / 2) + 1;
    target(rowStart:rowStart + resizedHeight - 1, colStart:colStart + resizedWidth - 1) = resized;
else
    target = resize_gray(source, outputSize(1), outputSize(2));
end
end

function gray = image_to_grayscale_unit(source)
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
    error("slm_hologram:InvalidTarget", "Input image must be two-dimensional or RGB.");
end

gray = source;
if any(~isfinite(gray), "all")
    error("slm_hologram:InvalidTarget", "Input image contains non-finite values.");
end
gray = min(max(gray, 0), 1);
end

function resized = resize_gray(source, targetHeight, targetWidth)
sourceHeight = size(source, 1);
sourceWidth = size(source, 2);
if sourceHeight == targetHeight && sourceWidth == targetWidth
    resized = source;
    return;
end
if sourceHeight == 1 && sourceWidth == 1
    resized = repmat(source, targetHeight, targetWidth);
    return;
end
if sourceHeight == 1
    xQuery = linspace(1, sourceWidth, targetWidth);
    row = interp1(1:sourceWidth, source, xQuery, "linear");
    resized = repmat(row, targetHeight, 1);
    return;
end
if sourceWidth == 1
    yQuery = linspace(1, sourceHeight, targetHeight)';
    column = interp1((1:sourceHeight)', source, yQuery, "linear");
    resized = repmat(column, 1, targetWidth);
    return;
end
[yQuery, xQuery] = ndgrid(linspace(1, sourceHeight, targetHeight), ...
                           linspace(1, sourceWidth, targetWidth));
resized = interp2(source, xQuery, yQuery, "linear");
end

function intensity = normalized_intensity(field)
intensity = abs(field).^2;
maximum = max(intensity, [], "all");
if maximum > 0
    intensity = intensity ./ maximum;
end
end

function phase = carrier_phase(config)
[height, width] = deal(config.slm_size(1), config.slm_size(2));
[x, y] = meshgrid(0:width - 1, 0:height - 1);
phase = zeros(height, width);
if config.grating_period_x_px > 0
    phase = phase + 2 * pi * x ./ config.grating_period_x_px;
end
if config.grating_period_y_px > 0
    phase = phase + 2 * pi * y ./ config.grating_period_y_px;
end
phase = phase + 2 * pi * ( ...
    config.tilt_x_cycles .* (x - (width - 1) / 2) ./ width + ...
    config.tilt_y_cycles .* (y - (height - 1) / 2) ./ height);
end

function metrics = evaluate_signal_region(reconstruction, target)
mask = target >= 0.1 * max(target, [], "all");
measured = reconstruction(mask);
desired = target(mask);
denominator = sum(measured.^2);
if denominator > 0
    fitScale = sum(measured .* desired) / denominator;
else
    fitScale = 0;
end
metrics = struct();
metrics.signal_pixel_fraction = nnz(mask) / numel(mask);
metrics.signal_nrmse = sqrt(sum((fitScale .* measured - desired).^2) / ...
    max(sum(desired.^2), eps));
metrics.signal_power_fraction = sum(reconstruction(mask)) / ...
    max(sum(reconstruction, "all"), eps);
metrics.best_fit_intensity_scale = fitScale;
end

function [phase, backgroundPhase] = add_phase_superpositions(basePhase, config)
[height, width] = size(basePhase);
[x, y] = meshgrid(0:width - 1, 0:height - 1);
carrier = config.phase_offset_rad;
if config.grating_period_x_px > 0
    carrier = carrier + 2 * pi * x ./ config.grating_period_x_px;
end
if config.grating_period_y_px > 0
    carrier = carrier + 2 * pi * y ./ config.grating_period_y_px;
end
centeredX = x - (width - 1) / 2;
centeredY = y - (height - 1) / 2;
normalizedX = centeredX ./ config.zernike_radius_px;
normalizedY = centeredY ./ config.zernike_radius_px;
radiusSquared = normalizedX.^2 + normalizedY.^2;

% The tilt controls are cycles across the full SLM width/height.  Defocus
% and astigmatism are low-order Zernike-like terms, measured in waves at
% their polynomial extrema; they mirror the superposition workflow in the
% HOLOEYE Pattern Generator while retaining explicit numerical units.
wavefront = 2 * pi * ( ...
    config.tilt_x_cycles .* centeredX ./ width + ...
    config.tilt_y_cycles .* centeredY ./ height + ...
    config.defocus_waves .* (2 .* radiusSquared - 1) + ...
    config.astigmatism_0_waves .* (normalizedX.^2 - normalizedY.^2) + ...
    config.astigmatism_45_waves .* (2 .* normalizedX .* normalizedY));

fresnelPhase = zeros(height, width);
if config.fresnel_focal_length_mm ~= 0
    wavelengthM = config.wavelength_nm * 1e-9;
    pitchM = config.pixel_pitch_um * 1e-6;
    focalLengthM = config.fresnel_focal_length_mm * 1e-3;
    fresnelPhase = -pi .* ((centeredX .* pitchM).^2 + (centeredY .* pitchM).^2) ./ ...
        (wavelengthM .* focalLengthM);
end

backgroundPhase = load_background_phase_map(config.background_phase_map_file, [height, width]);
phase = mod(basePhase + carrier + wavefront + fresnelPhase + backgroundPhase, 2 * pi);
end

function phase = load_background_phase_map(filename, expectedSize)
if isempty(filename) || (isstring(filename) && strlength(filename) == 0)
    phase = zeros(expectedSize);
    return;
end
filename = char(filename);
if ~isfile(filename)
    error("slm_hologram:MissingBackgroundMap", "Background phase map does not exist: %s", filename);
end
phaseImage = image_to_grayscale_unit(imread(filename));
if ~isequal(size(phaseImage), expectedSize)
    error("slm_hologram:BackgroundSize", ...
        "Background phase map must have the native SLM size [%d %d]; it is not resized automatically.", ...
        expectedSize(1), expectedSize(2));
end
phase = 2 * pi .* phaseImage;
end

function write_outputs(grayHologram, reconstruction, fullReconstruction, target, errors, ...
        phaseComponents, algorithmInfo, activeRegionMask, activeRegion, config)
outputDir = char(config.output_dir);
if ~isfolder(outputDir)
    mkdir(outputDir);
end
pngPath = fullfile(outputDir, "hologram.png");
imwrite(grayHologram, pngPath, "png");
if config.write_bmp
    imwrite(grayHologram, fullfile(outputDir, "hologram.bmp"), "bmp");
end
if config.write_preview
    preview = uint8(round(min(max(reconstruction, 0), 1) .* 255));
    imwrite(preview, fullfile(outputDir, "reconstruction_preview.png"), "png");
    fullPreview = uint8(round(min(max(fullReconstruction, 0), 1) .* 255));
    imwrite(fullPreview, fullfile(outputDir, "reconstruction_full.png"), "png");
end
targetImage = uint8(round(min(max(target, 0), 1) .* 255));
imwrite(targetImage, fullfile(outputDir, "target_used.png"), "png");
imwrite(uint8(activeRegionMask) .* 255, ...
    fullfile(outputDir, "active_region_mask.png"), "png");
iteration = (1:numel(errors))';
convergence = table(iteration, errors, algorithmInfo.uniformity_history, ...
    VariableNames=["iteration", "normalized_mse", "spot_uniformity"]);
writetable(convergence, fullfile(outputDir, "convergence.csv"));

metadata = struct();
if strcmp(algorithmInfo.resolved, "wgs")
    metadata.algorithm = "Weighted Gerchberg-Saxton Fourier phase hologram";
elseif strcmp(algorithmInfo.resolved, "mraf")
    metadata.algorithm = "Mixed-region amplitude freedom Fourier phase hologram";
else
    metadata.algorithm = "Gerchberg-Saxton Fourier phase hologram";
end
metadata.algorithm_requested = algorithmInfo.requested;
metadata.algorithm_resolved = algorithmInfo.resolved;
metadata.generated_at = char(datetime("now", "Format", "yyyy-MM-dd'T'HH:mm:ss"));
metadata.slm_size = config.slm_size;
metadata.wavelength_nm = config.wavelength_nm;
metadata.pixel_pitch_um = config.pixel_pitch_um;
metadata.iterations = config.iterations;
metadata.phase_levels = config.phase_levels;
metadata.grating_period_x_px = config.grating_period_x_px;
metadata.grating_period_y_px = config.grating_period_y_px;
metadata.phase_offset_rad = config.phase_offset_rad;
metadata.invert_grayscale = logical(config.invert_grayscale);
metadata.target_gamma = config.target_gamma;
metadata.target_description = char(config.target_description);
metadata.target_parameters = config.target_parameters;
metadata.phase_lut_file = char(config.phase_lut_file);
metadata.illumination_amplitude_file = char(config.illumination_amplitude_file);
metadata.background_phase_map_file = char(config.background_phase_map_file);
metadata.zernike_radius_px = config.zernike_radius_px;
metadata.tilt_x_cycles = config.tilt_x_cycles;
metadata.tilt_y_cycles = config.tilt_y_cycles;
metadata.fresnel_focal_length_mm = config.fresnel_focal_length_mm;
metadata.defocus_waves = config.defocus_waves;
metadata.astigmatism_0_waves = config.astigmatism_0_waves;
metadata.astigmatism_45_waves = config.astigmatism_45_waves;
metadata.phase_components = phaseComponents;
metadata.active_region = activeRegion;
metadata.final_normalized_mse = errors(end);
metadata.pre_export_normalized_mse = algorithmInfo.pre_export_normalized_mse;
metadata.signal_metrics = algorithmInfo.signal_metrics;
metadata.mraf = struct("signal_threshold", config.mraf_signal_threshold, ...
    "guard_px", config.mraf_guard_px, ...
    "signal_fraction", algorithmInfo.mraf_signal_fraction, ...
    "signal_pixel_count", algorithmInfo.mraf_signal_pixel_count);
metadata.wgs = struct( ...
    "feedback_strength", algorithmInfo.feedback_strength, ...
    "spot_radius_px", algorithmInfo.spot_radius_px, ...
    "focus_centers_px", algorithmInfo.focus_centers_px, ...
    "final_weights", algorithmInfo.final_weights, ...
    "final_spot_powers", algorithmInfo.final_spot_powers, ...
    "final_uniformity", algorithmInfo.final_uniformity);
metadata.files = struct( ...
    "hologram", "hologram.png", ...
    "target", "target_used.png", ...
    "active_region_mask", "active_region_mask.png", ...
    "preview", "reconstruction_preview.png", ...
    "full_preview", "reconstruction_full.png", ...
    "convergence", "convergence.csv");
metadataPath = fullfile(outputDir, "metadata.json");
file = fopen(metadataPath, "w");
if file < 0
    error("slm_hologram:MetadataWrite", "Unable to write metadata to: %s", metadataPath);
end
fileCleanup = onCleanup(@() fclose(file));
fprintf(file, "%s\n", jsonencode(metadata, "PrettyPrint", true));
end
