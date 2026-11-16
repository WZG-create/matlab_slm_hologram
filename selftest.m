function selftest()
%SELFTEST Run a compact end-to-end test without Image Processing Toolbox.

testRoot = tempname;
mkdir(testRoot);
cleanup = onCleanup(@() rmdir(testRoot, "s"));

targetParameters = struct( ...
    "rows", 3, "columns", 4, ...
    "spacing_x_px", 7, "spacing_y_px", 7, ...
    "spot_sigma_px", 1.2);
[target, targetDescription, completeTargetParameters] = generate_slm_target( ...
    "grid", [32, 48], targetParameters);
assert(isequal(size(target), [32, 48]) && abs(max(target, [], "all") - 1) < eps, ...
    "Generated grid target has the wrong size or normalization.");
assert(strlength(targetDescription) > 0 && strcmp(completeTargetParameters.pattern_type, "grid"), ...
    "Generated target metadata is incomplete.");
config = default_slm_config();
config.slm_size = [32, 48];
config.iterations = 6;
config.random_seed = 1;
config.grating_period_x_px = 8;
config.output_dir = testRoot;
config.target_description = targetDescription;
config.target_parameters = completeTargetParameters;

[grayHologram, result] = generate_slm_hologram(target, config);
assert(isequal(size(grayHologram), [32, 48]), "Hologram size is incorrect.");
assert(isa(grayHologram, "uint8"), "Hologram must be uint8.");
assert(numel(result.error_history) == 6, "Iteration history size is incorrect.");
assert(result.algorithm == "wgs" && size(result.focus_centers_px, 1) == 12, ...
    "Automatic mode did not select WGS for the multi-focus grid.");
assert(isfinite(result.final_spot_uniformity) && ...
    result.final_spot_uniformity >= result.spot_uniformity_history(1), ...
    "WGS did not improve the multi-focus uniformity.");
assert(isfile(fullfile(testRoot, "hologram.png")), "PNG was not generated.");
assert(isfile(fullfile(testRoot, "hologram.bmp")), "BMP was not generated.");
assert(isfile(fullfile(testRoot, "target_used.png")), "The actual target image was not saved.");
assert(isfile(fullfile(testRoot, "active_region_mask.png")), ...
    "The active-region verification mask was not saved.");
assert(isfile(fullfile(testRoot, "convergence.csv")), "WGS convergence CSV was not generated.");
metadata = jsondecode(fileread(fullfile(testRoot, "metadata.json")));
convergence = readtable(fullfile(testRoot, "convergence.csv"));
assert(strcmp(metadata.algorithm_resolved, "wgs") && height(convergence) == config.iterations && ...
    all(ismember(["normalized_mse", "spot_uniformity"], ...
    string(convergence.Properties.VariableNames))), ...
    "WGS metadata or convergence columns are incomplete.");
info = imfinfo(fullfile(testRoot, "hologram.png"));
assert(info.Width == 48 && info.Height == 32 && info.BitDepth == 8, ...
    "PNG is not a 48x32 8-bit image.");
assert(isequal(imread(fullfile(testRoot, "hologram.png")), grayHologram) && ...
    isfile(fullfile(testRoot, "reconstruction_full.png")), ...
    "The exported gray image or full-field preview is missing.");
[x, ~] = meshgrid(0:47, 0:31);
grayPhase = 2 * pi * double(grayHologram) / 255;
replayed = abs(fftshift(fft2(exp(1i * (grayPhase - 2 * pi * x / 8))))).^2;
replayed = replayed / max(replayed, [], "all");
assert(max(abs(replayed - result.reconstruction), [], "all") < 1e-10, ...
    "The aligned preview must be propagated from the exported gray codes.");
assert(isfinite(result.signal_metrics.signal_nrmse) && ...
    result.signal_metrics.signal_power_fraction > 0 && ...
    isfinite(metadata.pre_export_normalized_mse), ...
    "The final-gray signal metrics were not recorded.");

invertedConfig = config;
invertedConfig.invert_grayscale = true;
invertedConfig.output_dir = fullfile(testRoot, "inverted_gray");
[invertedGray, invertedResult] = generate_slm_hologram(target, invertedConfig);
invertedPhase = 2 * pi * double(invertedGray) / 255;
invertedReplay = abs(fftshift(fft2(exp(1i * ...
    (invertedPhase - 2 * pi * x / 8))))).^2;
invertedReplay = invertedReplay / max(invertedReplay, [], "all");
assert(max(abs(invertedReplay - invertedResult.reconstruction), [], "all") < 1e-10 && ...
    max(abs(invertedResult.reconstruction - result.reconstruction), [], "all") > 0.1, ...
    "Inverted gray must change the physical replay and final preview.");

regionConfig = config;
regionConfig.active_region_enabled = true;
regionConfig.active_region_shape = "rectangle";
regionConfig.active_region_size_px = [13, 21];
regionConfig.active_region_offset_px = [3, -2];
regionConfig.output_dir = fullfile(testRoot, "active_region");
[regionMask, regionDetails] = slm_active_region_mask(regionConfig);
assert(nnz(regionMask) == 13 * 21 && regionDetails.enabled && ...
    isequal(regionDetails.size_px, [13, 21]), ...
    "The rectangular active-region mask has the wrong geometry.");
[activeGray, activeResult] = generate_slm_hologram(target, regionConfig);
assert(activeResult.active_region.enabled && all(activeGray(~regionMask) == 0) && ...
    isfile(fullfile(regionConfig.output_dir, "active_region_mask.png")), ...
    "GS/WGS did not enforce or export the active loading region.");
regionConfig.active_region_shape = "ellipse";
ellipseMask = slm_active_region_mask(regionConfig);
assert(nnz(ellipseMask) > 0 && nnz(ellipseMask) < nnz(regionMask), ...
    "The elliptical active-region mask is invalid.");
regionConfig.active_region_offset_px = [30, 0];
try
    slm_active_region_mask(regionConfig);
    error("selftest:RegionBounds", "Out-of-bounds active region unexpectedly succeeded.");
catch exception
    assert(strcmp(exception.identifier, "slm_region:OutsideSLM"), ...
        "Wrong error for an out-of-bounds active region.");
end

config.algorithm = "gs";
config.output_dir = fullfile(testRoot, "standard_gs");
[~, gsResult] = generate_slm_hologram(target, config);
assert(gsResult.algorithm == "gs" && all(isnan(gsResult.spot_uniformity_history)), ...
    "Explicit standard GS selection failed.");

config.algorithm = "wgs";
config.target_parameters = struct();
config.output_dir = fullfile(testRoot, "wgs_peak_detection");
[~, detectedWgsResult] = generate_slm_hologram(target, config);
assert(detectedWgsResult.algorithm == "wgs" && ...
    size(detectedWgsResult.focus_centers_px, 1) == 12, ...
    "Explicit WGS did not detect the external multi-focus target.");
config.algorithm = "auto";
config.target_parameters = completeTargetParameters;

ringParameters = struct("ring_radius_px", 28, "ring_width_px", 3);
[ringTarget, ~, ringMetadata] = generate_slm_target("annulus", [128, 160], ringParameters);
ringConfig = default_slm_config();
ringConfig.slm_size = [128, 160];
ringConfig.iterations = 40;
ringConfig.random_seed = 42;
ringConfig.grating_period_x_px = 8;
ringConfig.target_parameters = ringMetadata;
ringConfig.output_dir = fullfile(testRoot, "ring_gs");
ringConfig.algorithm = "gs";
[~, ringGs] = generate_slm_hologram(ringTarget, ringConfig);
ringConfig.output_dir = fullfile(testRoot, "ring_mraf");
ringConfig.algorithm = "auto";
[~, ringMraf] = generate_slm_hologram(ringTarget, ringConfig);
assert(ringMraf.algorithm == "mraf" && ...
    ringMraf.signal_metrics.signal_nrmse < ringGs.signal_metrics.signal_nrmse, ...
    "MRAF must improve this fixed continuous-ring benchmark over GS.");

otherParameters = struct( ...
    "spot_count", 8, "spot_sigma_px", 1.5, ...
    "ring_radius_px", 9, "ring_width_px", 2, ...
    "disk_radius_px", 8, "edge_width_px", 1);
for pattern = ["ring_spots", "gaussian", "annulus", "disk"]
    generated = generate_slm_target(pattern, [32, 48], otherParameters);
    assert(isequal(size(generated), [32, 48]) && max(generated, [], "all") > 0, ...
        "Target type %s failed.", pattern);
end

catalog = zernike14_catalog();
assert(numel(catalog.index) == 14 && numel(catalog.name_zh) == 14, ...
    "The 14-mode aberration catalog is incomplete.");
coefficients = zeros(14, 1);
coefficients(3) = 0.25;
[zernikePhase, zernikeDetails] = generate_zernike14_phase(coefficients, [32, 48], 14, []);
assert(isequal(size(zernikePhase), [32, 48]) && isscalar(zernikeDetails.active_keys), ...
    "Zernike phase generation failed.");

phaseConfig = default_slm_config();
phaseConfig.slm_size = [32, 48];
phaseConfig.output_dir = fullfile(testRoot, "direct_phase");
phaseParameters = struct( ...
    "period_px", 8, "focal_length_mm", 100, "radial_period_px", 7, ...
    "radius_px", 10, "rect_width_px", 20, "rect_height_px", 12, ...
    "slit_width_px", 3, "slit_separation_px", 10, "ring_period_px", 6, ...
    "zernike_radius_px", 14, "zernike_coefficients_waves", coefficients);
phaseTypes = ["blank", "blazed_grating", "binary_grating", "sinusoidal_grating", ...
    "crossed_grating", "fresnel_lens", "binary_fresnel_lens", "cylindrical_lens", ...
    "axicon", "binary_axicon", "vortex", "concentric_rings", "circular_aperture", ...
    "rectangular_aperture", "single_slit", "double_slit", "split_horizontal", ...
    "split_vertical", "random_phase", "random_binary", "zernike14"];
for phaseType = phaseTypes
    componentPhase = generate_phase_component(phaseType, phaseConfig, phaseParameters);
    assert(isequal(size(componentPhase), [32, 48]) && all(isfinite(componentPhase), "all"), ...
        "Phase component %s failed.", phaseType);
end

firstOrderBlaze = generate_phase_component("blazed_grating", phaseConfig, ...
    struct("period_px", 8, "diffraction_order", 1, "phase_depth_waves", 1));
secondOrderBlaze = generate_phase_component("blazed_grating", phaseConfig, ...
    struct("period_px", 8, "diffraction_order", 2, "phase_depth_waves", 1));
legacyBlaze = generate_phase_component("blazed_grating", phaseConfig, ...
    struct("period_px", 8, "phase_span_waves", 0.7));
depthBlaze = generate_phase_component("blazed_grating", phaseConfig, ...
    struct("period_px", 8, "diffraction_order", 1, "phase_depth_waves", 0.7));
assert(~isequal(firstOrderBlaze, secondOrderBlaze) && isequal(legacyBlaze, depthBlaze), ...
    "Blazed-grating diffraction-order control or legacy compatibility failed.");
try
    generate_phase_component("blazed_grating", phaseConfig, ...
        struct("diffraction_order", 1.5));
    error("selftest:FractionalDiffractionOrder", ...
        "A fractional blazed-grating diffraction order unexpectedly succeeded.");
catch exception
    assert(strcmp(exception.identifier, "slm_phase:InvalidInteger"), ...
        "Wrong error for a fractional blazed-grating diffraction order.");
end

phaseConfig.output_dir = fullfile(testRoot, "reference_phase");
emptyComponents = struct("type", {}, "parameters", {}, "description", {});
[referenceGray, referenceResult] = generate_slm_phase_hologram(emptyComponents, phaseConfig);
referenceMetadata = jsondecode(fileread(fullfile(phaseConfig.output_dir, "metadata.json")));
assert(referenceResult.mode == "reference_phase" && ...
    all(referenceGray == referenceGray(1), "all") && ...
    isfile(fullfile(phaseConfig.output_dir, "reference_phase.png")) && ...
    strcmp(referenceMetadata.output_mode, "reference_phase"), ...
    "Uniform reference-phase generation failed.");

phaseConfig.output_dir = fullfile(testRoot, "direct_phase");
components = struct( ...
    "type", {"blazed_grating", "fresnel_lens", "zernike14"}, ...
    "parameters", {phaseParameters, phaseParameters, phaseParameters});
[directGray, directResult] = generate_slm_phase_hologram(components, phaseConfig);
assert(isa(directGray, "uint8") && isequal(size(directGray), [32, 48]) && ...
    numel(directResult.components) == 3, "Direct phase composition failed.");
assert(isfile(fullfile(phaseConfig.output_dir, "phase_data.mat")) && ...
    isfile(fullfile(phaseConfig.output_dir, "metadata.json")), ...
    "Direct phase outputs were not saved.");

phaseConfig.active_region_enabled = true;
phaseConfig.active_region_shape = "ellipse";
phaseConfig.active_region_size_px = [18, 26];
phaseConfig.active_region_offset_px = [2, -1];
phaseConfig.output_dir = fullfile(testRoot, "direct_phase_active_region");
[directRegionGray, directRegionResult] = generate_slm_phase_hologram(components, phaseConfig);
directRegionMask = slm_active_region_mask(phaseConfig);
assert(directRegionResult.active_region.enabled && ...
    all(directRegionGray(~directRegionMask) == 0) && ...
    isfile(fullfile(phaseConfig.output_dir, "active_region_mask.png")), ...
    "Direct phase composition did not enforce the active loading region.");
inactivePhaseConfig = phaseConfig;
inactivePhaseConfig.active_region_enabled = false;
inactivePhaseConfig.active_region_size_px = [];
inactivePhaseConfig.active_region_offset_px = [0, 0];
activeFunctionPhase = generate_phase_component("axicon", phaseConfig, phaseParameters);
inactiveFunctionPhase = generate_phase_component("axicon", inactivePhaseConfig, phaseParameters);
assert(isequal(activeFunctionPhase, inactiveFunctionPhase), ...
    "The active loading region must not alter optical-library function geometry.");
phaseConfig.active_region_enabled = false;
phaseConfig.active_region_size_px = [];
phaseConfig.active_region_offset_px = [0, 0];

directBackgroundPath = fullfile(testRoot, "direct_background_phase.png");
imwrite(uint8(repmat(0:47, 32, 1) .* 5), directBackgroundPath, "png");
phaseConfig.background_phase_map_file = directBackgroundPath;
phaseConfig.phase_offset_rad = 0.2;
phaseConfig.output_dir = fullfile(testRoot, "direct_phase_corrected");
directCorrected = generate_slm_phase_hologram(components, phaseConfig);
assert(~isequal(directGray, directCorrected), ...
    "Direct phase background compensation and phase offset should affect the hologram.");
phaseConfig.background_phase_map_file = "";
phaseConfig.phase_offset_rad = 0;

config.phase_components = components(3);
config.output_dir = fullfile(testRoot, "gs_with_component");
[grayWithComponent, resultWithComponent] = generate_slm_hologram(target, config);
assert(isscalar(resultWithComponent.phase_components) && ...
    ~isequal(grayHologram, grayWithComponent), ...
    "Optical-library phase components were not superposed onto the GS hologram.");
config.phase_components = struct("type", {}, "parameters", {}, "description", {});

lutPath = fullfile(testRoot, "phase_lut.csv");
file = fopen(lutPath, "w");
fprintf(file, "phase_rad,gray\n0,4\n3.141592654,127\n6.283185307,250\n");
fclose(file);
config.phase_lut_file = lutPath;
config.output_dir = fullfile(testRoot, "with_lut");
grayWithLut = generate_slm_hologram(target, config);
assert(isa(grayWithLut, "uint8"), "LUT output must be uint8.");

illuminationPath = fullfile(testRoot, "illumination_amplitude.png");
imwrite(uint8(repmat(linspace(40, 255, 48), 32, 1)), illuminationPath, "png");
config.illumination_amplitude_file = illuminationPath;
config.output_dir = fullfile(testRoot, "with_illumination");
[grayWithIllumination, illuminatedResult] = generate_slm_hologram(target, config);
assert(~isequal(grayWithLut, grayWithIllumination) && ...
    isfinite(illuminatedResult.signal_metrics.signal_nrmse), ...
    "A measured illumination amplitude must influence optimization.");
config.illumination_amplitude_file = "";

backgroundPath = fullfile(testRoot, "background_phase.png");
background = uint8(repmat(0:47, 32, 1) .* 5);
imwrite(background, backgroundPath, "png");
config.background_phase_map_file = backgroundPath;
config.output_dir = fullfile(testRoot, "with_background");
grayWithBackground = generate_slm_hologram(target, config);
assert(~isequal(grayWithLut, grayWithBackground), ...
    "Native-size background phase compensation should affect the final hologram.");

config.background_phase_map_file = "";
config.fresnel_focal_length_mm = 125;
config.output_dir = fullfile(testRoot, "with_fresnel_lens");
grayWithLens = generate_slm_hologram(target, config);
assert(~isequal(grayWithLut, grayWithLens), ...
    "A nonzero Fresnel lens term should affect the final hologram.");
config.fresnel_focal_length_mm = 0;

badBackgroundPath = fullfile(testRoot, "bad_background_phase.png");
imwrite(uint8(zeros(31, 48)), badBackgroundPath, "png");
config.background_phase_map_file = badBackgroundPath;
config.output_dir = fullfile(testRoot, "bad_background");
try
    generate_slm_hologram(target, config);
    error("selftest:BackgroundCheck", "Mismatched background map unexpectedly succeeded.");
catch exception
    assert(strcmp(exception.identifier, "slm_hologram:BackgroundSize"), ...
        "Wrong error for a mismatched background phase map.");
end

disp("SLM hologram self-test passed.");
end
