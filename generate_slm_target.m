function [target, description, parameters] = generate_slm_target(patternType, slmSize, userParameters)
%GENERATE_SLM_TARGET Create a normalized target intensity image for GS/IFTA.
%
% [target, description, parameters] = generate_slm_target(type, slmSize, p)
% creates a double image in the range 0..1 with exactly the requested SLM
% size [height, width]. Supported types are:
%   "grid"       - rectangular array of equal Gaussian focal spots
%   "ring_spots" - equal Gaussian focal spots placed on a circle
%   "gaussian"   - a single centered Gaussian focal spot
%   "annulus"    - a continuous Gaussian annulus
%   "disk"       - a circular flat-top target with a controllable edge
%
% Parameters use target-plane pixels. The returned parameter structure is
% complete and can be saved in metadata to reproduce the target.

if nargin < 3
    userParameters = struct();
end
if ~isnumeric(slmSize) || numel(slmSize) ~= 2 || any(slmSize <= 0) || ...
        any(mod(slmSize, 1) ~= 0)
    error("slm_target:InvalidSize", "slmSize must be [positive_integer_height, positive_integer_width].");
end
if ~isstruct(userParameters)
    error("slm_target:InvalidParameters", "Target parameters must be a structure.");
end

slmSize = double(reshape(slmSize, 1, 2));
patternType = lower(string(patternType));
defaults = struct( ...
    "rows", 5, ...
    "columns", 5, ...
    "spacing_x_px", 80, ...
    "spacing_y_px", 80, ...
    "spot_count", 12, ...
    "spot_sigma_px", 5, ...
    "ring_radius_px", 220, ...
    "ring_width_px", 12, ...
    "disk_radius_px", 180, ...
    "edge_width_px", 2, ...
    "rotation_deg", 0);
parameters = merge_parameters(defaults, userParameters);
validate_parameters(parameters);

height = slmSize(1);
width = slmSize(2);
centerX = (width + 1) / 2;
centerY = (height + 1) / 2;
target = zeros(height, width);
focusCenters = zeros(0, 2);

switch patternType
    case "grid"
        rowOffsets = ((0:parameters.rows - 1) - (parameters.rows - 1) / 2) .* parameters.spacing_y_px;
        colOffsets = ((0:parameters.columns - 1) - (parameters.columns - 1) / 2) .* parameters.spacing_x_px;
        [offsetX, offsetY] = meshgrid(colOffsets, rowOffsets);
        angle = deg2rad(parameters.rotation_deg);
        rotatedX = cos(angle) .* offsetX - sin(angle) .* offsetY;
        rotatedY = sin(angle) .* offsetX + cos(angle) .* offsetY;
        centers = [centerX + rotatedX(:), centerY + rotatedY(:)];
        target = add_gaussian_spots(target, centers, parameters.spot_sigma_px);
        focusCenters = centers;
        description = sprintf("二维多焦点阵列 · %d × %d · 间距 %.3g × %.3g px", ...
            parameters.rows, parameters.columns, parameters.spacing_x_px, parameters.spacing_y_px);

    case "ring_spots"
        angles = deg2rad(parameters.rotation_deg) + (0:parameters.spot_count - 1)' .* (2 * pi / parameters.spot_count);
        centers = [centerX + parameters.ring_radius_px .* cos(angles), ...
                   centerY + parameters.ring_radius_px .* sin(angles)];
        target = add_gaussian_spots(target, centers, parameters.spot_sigma_px);
        focusCenters = centers;
        description = sprintf("环形多焦点阵列 · %d 点 · 半径 %.3g px", ...
            parameters.spot_count, parameters.ring_radius_px);

    case "gaussian"
        target = add_gaussian_spots(target, [centerX, centerY], parameters.spot_sigma_px);
        focusCenters = [centerX, centerY];
        description = sprintf("单高斯光斑 · σ = %.3g px", parameters.spot_sigma_px);

    case "annulus"
        [x, y] = meshgrid(1:width, 1:height);
        radius = hypot(x - centerX, y - centerY);
        target = exp(-0.5 .* ((radius - parameters.ring_radius_px) ./ parameters.ring_width_px).^2);
        description = sprintf("连续环形光束 · 半径 %.3g px · 宽度 σ = %.3g px", ...
            parameters.ring_radius_px, parameters.ring_width_px);

    case "disk"
        [x, y] = meshgrid(1:width, 1:height);
        radius = hypot(x - centerX, y - centerY);
        if parameters.edge_width_px > 0
            exponent = min(max((radius - parameters.disk_radius_px) ./ parameters.edge_width_px, -60), 60);
            target = 1 ./ (1 + exp(exponent));
        else
            target = double(radius <= parameters.disk_radius_px);
        end
        description = sprintf("圆形平顶光斑 · 半径 %.3g px", parameters.disk_radius_px);

    otherwise
        error("slm_target:UnknownPattern", ...
            "Unknown target type '%s'. Use grid, ring_spots, gaussian, annulus, or disk.", patternType);
end

maximum = max(target, [], "all");
if maximum <= 0 || ~isfinite(maximum)
    error("slm_target:EmptyTarget", "The selected parameters produced an empty target.");
end
target = target ./ maximum;
parameters.pattern_type = char(patternType);
parameters.slm_size = slmSize;
parameters.focus_centers_px = focusCenters;
end

function parameters = merge_parameters(defaults, userParameters)
parameters = defaults;
names = fieldnames(userParameters);
validNames = fieldnames(defaults);
for index = 1:numel(names)
    name = names{index};
    if ~ismember(name, validNames)
        error("slm_target:UnknownParameter", "Unknown target parameter: %s", name);
    end
    parameters.(name) = userParameters.(name);
end
end

function validate_parameters(parameters)
integerNames = {"rows", "columns", "spot_count"};
for index = 1:numel(integerNames)
    name = integerNames{index};
    value = parameters.(name);
    if ~isscalar(value) || value < 1 || mod(value, 1) ~= 0
        error("slm_target:InvalidInteger", "%s must be a positive integer.", name);
    end
end
positiveNames = {"spacing_x_px", "spacing_y_px", "spot_sigma_px", ...
    "ring_radius_px", "ring_width_px", "disk_radius_px"};
for index = 1:numel(positiveNames)
    name = positiveNames{index};
    value = parameters.(name);
    if ~isscalar(value) || value <= 0 || ~isfinite(value)
        error("slm_target:InvalidPositive", "%s must be a positive finite scalar.", name);
    end
end
if ~isscalar(parameters.edge_width_px) || parameters.edge_width_px < 0 || ~isfinite(parameters.edge_width_px)
    error("slm_target:InvalidEdge", "edge_width_px must be zero or positive.");
end
if ~isscalar(parameters.rotation_deg) || ~isfinite(parameters.rotation_deg)
    error("slm_target:InvalidRotation", "rotation_deg must be finite.");
end
end

function target = add_gaussian_spots(target, centers, sigma)
[height, width] = size(target);
if any(centers(:, 1) < 1 | centers(:, 1) > width | centers(:, 2) < 1 | centers(:, 2) > height)
    error("slm_target:OutsideCanvas", ...
        "One or more focal-spot centers fall outside the target canvas. Reduce spacing or radius.");
end
support = max(2, ceil(4 * sigma));
for index = 1:size(centers, 1)
    centerX = centers(index, 1);
    centerY = centers(index, 2);
    xRange = max(1, floor(centerX - support)):min(width, ceil(centerX + support));
    yRange = max(1, floor(centerY - support)):min(height, ceil(centerY + support));
    [x, y] = meshgrid(xRange, yRange);
    patch = exp(-((x - centerX).^2 + (y - centerY).^2) ./ (2 * sigma^2));
    target(yRange, xRange) = target(yRange, xRange) + patch;
end
end
