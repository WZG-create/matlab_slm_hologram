function [phase, description, parameters] = generate_phase_component(componentType, slmConfig, userParameters)
%GENERATE_PHASE_COMPONENT Create one directly programmable SLM phase element.
%
% The returned phase is unwrapped radians so multiple components can be
% added before the final modulo, quantization and calibrated grayscale map.

if nargin < 3
    userParameters = struct();
end
requiredConfig = {"slm_size", "wavelength_nm", "pixel_pitch_um"};
for index = 1:numel(requiredConfig)
    if ~isfield(slmConfig, requiredConfig{index})
        error("slm_phase:MissingConfig", "slmConfig is missing %s.", requiredConfig{index});
    end
end
slmSize = double(slmConfig.slm_size);
if numel(slmSize) ~= 2 || any(slmSize <= 0)
    error("slm_phase:InvalidSize", "slm_size must be [height,width].");
end
height = slmSize(1);
width = slmSize(2);
defaults = struct( ...
    "period_px", 16, ...
    "angle_deg", 0, ...
    "diffraction_order", 1, ...
    "phase_span_waves", 1, ...
    "phase_depth_waves", 0.5, ...
    "duty_cycle", 0.5, ...
    "focal_length_mm", 300, ...
    "orientation_deg", 0, ...
    "radial_period_px", 32, ...
    "vortex_charge", 1, ...
    "radius_px", min(slmSize) / 4, ...
    "rect_width_px", width / 2, ...
    "rect_height_px", height / 2, ...
    "slit_width_px", 20, ...
    "slit_separation_px", 100, ...
    "ring_period_px", 32, ...
    "seed", 42, ...
    "phase_offset_rad", 0, ...
    "zernike_coefficients_waves", zeros(14, 1), ...
    "zernike_radius_px", min(slmSize) / 2 - 0.5);
componentType = lower(string(componentType));
parameters = merge_parameters(defaults, userParameters);
% Compatibility with projects saved before blazed gratings exposed an
% explicit diffraction order. Their phase_span_waves was the sawtooth
% depth, so retain it as phase_depth_waves at the default first order.
if componentType == "blazed_grating"
    if isfield(userParameters, "phase_span_waves") && ...
            ~isfield(userParameters, "phase_depth_waves")
        parameters.phase_depth_waves = userParameters.phase_span_waves;
    elseif ~isfield(userParameters, "phase_depth_waves")
        parameters.phase_depth_waves = 1;
    end
end
validate_common(parameters);

[pixelX, pixelY] = meshgrid(1:width, 1:height);
x = pixelX - (width + 1) / 2;
y = pixelY - (height + 1) / 2;
radius = hypot(x, y);
theta = atan2(y, x);
angle = deg2rad(parameters.angle_deg);
linearCoordinate = x .* cos(angle) + y .* sin(angle);
phase = zeros(height, width);

switch componentType
    case "blank"
        phase(:) = parameters.phase_offset_rad;
        description = sprintf("均匀相位 · %.4g rad", parameters.phase_offset_rad);

    case "blazed_grating"
        require_positive(parameters.period_px, "period_px");
        phase = 2 * pi * parameters.phase_depth_waves .* ...
            mod(parameters.diffraction_order .* linearCoordinate ./ parameters.period_px, 1);
        description = sprintf("闪耀光栅 · m = %d · 周期 %.4g px · 角度 %.4g° · 深度 %.4g wave", ...
            parameters.diffraction_order, parameters.period_px, parameters.angle_deg, ...
            parameters.phase_depth_waves);

    case "binary_grating"
        require_positive(parameters.period_px, "period_px");
        high = mod(linearCoordinate, parameters.period_px) < parameters.period_px * parameters.duty_cycle;
        phase = 2 * pi * parameters.phase_depth_waves .* double(high);
        description = sprintf("二值相位光栅 · 周期 %.4g px · 占空比 %.3g", ...
            parameters.period_px, parameters.duty_cycle);

    case "sinusoidal_grating"
        require_positive(parameters.period_px, "period_px");
        phase = pi * parameters.phase_span_waves .* ...
            (1 + sin(2 * pi .* linearCoordinate ./ parameters.period_px));
        description = sprintf("正弦相位光栅 · 周期 %.4g px · 角度 %.4g°", ...
            parameters.period_px, parameters.angle_deg);

    case "crossed_grating"
        require_positive(parameters.period_px, "period_px");
        binaryX = mod(x, parameters.period_px) < parameters.period_px * parameters.duty_cycle;
        binaryY = mod(y, parameters.period_px) < parameters.period_px * parameters.duty_cycle;
        phase = 2 * pi * parameters.phase_depth_waves .* double(xor(binaryX, binaryY));
        description = sprintf("交叉二值光栅 · 周期 %.4g px", parameters.period_px);

    case "fresnel_lens"
        require_nonzero(parameters.focal_length_mm, "focal_length_mm");
        wavelengthM = slmConfig.wavelength_nm * 1e-9;
        pitchM = slmConfig.pixel_pitch_um * 1e-6;
        focalM = parameters.focal_length_mm * 1e-3;
        phase = -pi .* ((x .* pitchM).^2 + (y .* pitchM).^2) ./ (wavelengthM .* focalM);
        description = sprintf("Fresnel 透镜 · f = %.5g mm", parameters.focal_length_mm);

    case "binary_fresnel_lens"
        require_nonzero(parameters.focal_length_mm, "focal_length_mm");
        wavelengthM = slmConfig.wavelength_nm * 1e-9;
        pitchM = slmConfig.pixel_pitch_um * 1e-6;
        focalM = parameters.focal_length_mm * 1e-3;
        continuous = mod(-pi .* ((x .* pitchM).^2 + (y .* pitchM).^2) ./ ...
            (wavelengthM .* focalM), 2 * pi);
        phase = 2 * pi * parameters.phase_depth_waves .* double(continuous >= pi);
        description = sprintf("二值 Fresnel 透镜 · f = %.5g mm", parameters.focal_length_mm);

    case "cylindrical_lens"
        require_nonzero(parameters.focal_length_mm, "focal_length_mm");
        wavelengthM = slmConfig.wavelength_nm * 1e-9;
        pitchM = slmConfig.pixel_pitch_um * 1e-6;
        focalM = parameters.focal_length_mm * 1e-3;
        orientation = deg2rad(parameters.orientation_deg);
        lensCoordinate = x .* cos(orientation) + y .* sin(orientation);
        phase = -pi .* (lensCoordinate .* pitchM).^2 ./ (wavelengthM .* focalM);
        description = sprintf("柱面 Fresnel 透镜 · f = %.5g mm · 方向 %.4g°", ...
            parameters.focal_length_mm, parameters.orientation_deg);

    case "axicon"
        require_positive(parameters.radial_period_px, "radial_period_px");
        phase = 2 * pi .* radius ./ parameters.radial_period_px + parameters.vortex_charge .* theta;
        description = sprintf("轴锥/贝塞尔相位 · 径向周期 %.4g px · 拓扑荷 %d", ...
            parameters.radial_period_px, parameters.vortex_charge);

    case "binary_axicon"
        require_positive(parameters.radial_period_px, "radial_period_px");
        high = mod(radius, parameters.radial_period_px) < parameters.radial_period_px / 2;
        phase = 2 * pi * parameters.phase_depth_waves .* double(high);
        description = sprintf("二值轴锥 · 径向周期 %.4g px", parameters.radial_period_px);

    case "vortex"
        phase = parameters.vortex_charge .* theta;
        description = sprintf("涡旋相位 · 拓扑荷 %d", parameters.vortex_charge);

    case "concentric_rings"
        require_positive(parameters.ring_period_px, "ring_period_px");
        high = mod(radius, parameters.ring_period_px) < parameters.ring_period_px / 2;
        phase = 2 * pi * parameters.phase_depth_waves .* double(high);
        description = sprintf("同心二值环 · 周期 %.4g px", parameters.ring_period_px);

    case "circular_aperture"
        require_positive(parameters.radius_px, "radius_px");
        phase = 2 * pi * parameters.phase_depth_waves .* double(radius > parameters.radius_px);
        description = sprintf("圆形二值相位孔径 · 半径 %.4g px", parameters.radius_px);

    case "rectangular_aperture"
        require_positive(parameters.rect_width_px, "rect_width_px");
        require_positive(parameters.rect_height_px, "rect_height_px");
        inside = abs(x) <= parameters.rect_width_px / 2 & abs(y) <= parameters.rect_height_px / 2;
        phase = 2 * pi * parameters.phase_depth_waves .* double(~inside);
        description = sprintf("矩形二值相位孔径 · %.4g × %.4g px", ...
            parameters.rect_width_px, parameters.rect_height_px);

    case "single_slit"
        require_positive(parameters.slit_width_px, "slit_width_px");
        slitCoordinate = x .* cos(angle) + y .* sin(angle);
        inside = abs(slitCoordinate) <= parameters.slit_width_px / 2;
        phase = 2 * pi * parameters.phase_depth_waves .* double(~inside);
        description = sprintf("单缝二值相位 · 缝宽 %.4g px · 角度 %.4g°", ...
            parameters.slit_width_px, parameters.angle_deg);

    case "double_slit"
        require_positive(parameters.slit_width_px, "slit_width_px");
        require_positive(parameters.slit_separation_px, "slit_separation_px");
        slitCoordinate = x .* cos(angle) + y .* sin(angle);
        inside = abs(abs(slitCoordinate) - parameters.slit_separation_px / 2) <= parameters.slit_width_px / 2;
        phase = 2 * pi * parameters.phase_depth_waves .* double(~inside);
        description = sprintf("双缝二值相位 · 缝宽 %.4g px · 间距 %.4g px", ...
            parameters.slit_width_px, parameters.slit_separation_px);

    case "split_horizontal"
        phase(y >= 0) = 2 * pi * parameters.phase_depth_waves;
        description = "水平二分相位屏";

    case "split_vertical"
        phase(x >= 0) = 2 * pi * parameters.phase_depth_waves;
        description = "垂直二分相位屏";

    case "random_phase"
        previous = rng;
        cleanup = onCleanup(@() rng(previous));
        rng(parameters.seed, "twister");
        phase = 2 * pi * parameters.phase_span_waves .* rand(height, width);
        description = sprintf("随机相位 · seed %d", parameters.seed);

    case "random_binary"
        previous = rng;
        cleanup = onCleanup(@() rng(previous));
        rng(parameters.seed, "twister");
        phase = 2 * pi * parameters.phase_depth_waves .* double(rand(height, width) >= 0.5);
        description = sprintf("随机二值相位 · seed %d", parameters.seed);

    case "zernike14"
        [phase, details] = generate_zernike14_phase( ...
            parameters.zernike_coefficients_waves, slmSize, parameters.zernike_radius_px, []);
        activeCount = numel(details.active_keys);
        description = sprintf("14 项 Zernike 像差 · %d 项非零 · 半径 %.4g px", ...
            activeCount, parameters.zernike_radius_px);

    otherwise
        error("slm_phase:UnknownComponent", "Unknown phase component type: %s", componentType);
end

if any(~isfinite(phase), "all")
    error("slm_phase:NonFinite", "The selected parameters produced non-finite phase values.");
end
end

function parameters = merge_parameters(defaults, userParameters)
if ~isstruct(userParameters)
    error("slm_phase:InvalidParameters", "Component parameters must be a structure.");
end
parameters = defaults;
names = fieldnames(userParameters);
validNames = fieldnames(defaults);
for index = 1:numel(names)
    name = names{index};
    if ~ismember(name, validNames)
        error("slm_phase:UnknownParameter", "Unknown phase parameter: %s", name);
    end
    parameters.(name) = userParameters.(name);
end
end

function validate_common(parameters)
finiteScalarNames = {"period_px", "angle_deg", "diffraction_order", "phase_span_waves", ...
    "phase_depth_waves", "duty_cycle", "focal_length_mm", "orientation_deg", ...
    "radial_period_px", "vortex_charge", "radius_px", "rect_width_px", ...
    "rect_height_px", "slit_width_px", "slit_separation_px", "ring_period_px", ...
    "seed", "phase_offset_rad", "zernike_radius_px"};
for index = 1:numel(finiteScalarNames)
    name = finiteScalarNames{index};
    value = parameters.(name);
    if ~isscalar(value) || ~isfinite(value)
        error("slm_phase:InvalidScalar", "%s must be a finite scalar.", name);
    end
end
if parameters.duty_cycle <= 0 || parameters.duty_cycle >= 1
    error("slm_phase:InvalidDutyCycle", "duty_cycle must be strictly between 0 and 1.");
end
if mod(parameters.vortex_charge, 1) ~= 0 || mod(parameters.seed, 1) ~= 0 || ...
        mod(parameters.diffraction_order, 1) ~= 0
    error("slm_phase:InvalidInteger", ...
        "vortex_charge, seed and diffraction_order must be integers.");
end
coefficients = parameters.zernike_coefficients_waves;
if ~isnumeric(coefficients) || numel(coefficients) ~= 14 || any(~isfinite(coefficients))
    error("slm_phase:InvalidZernike", "zernike_coefficients_waves must contain 14 finite values.");
end
parameters.zernike_coefficients_waves = coefficients(:);
end

function require_positive(value, name)
if value <= 0
    error("slm_phase:PositiveRequired", "%s must be positive.", name);
end
end

function require_nonzero(value, name)
if value == 0
    error("slm_phase:NonzeroRequired", "%s must be nonzero.", name);
end
end
