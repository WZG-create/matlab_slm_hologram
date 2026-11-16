function [mask, details] = slm_active_region_mask(config)
%SLM_ACTIVE_REGION_MASK Build the configurable SLM loading aperture.
%
% The returned logical mask always has config.slm_size. Region size uses
% [height,width], while the offset uses [x,y] pixels from the SLM center.

required = {"slm_size", "active_region_enabled", "active_region_shape", ...
    "active_region_size_px", "active_region_offset_px"};
for index = 1:numel(required)
    if ~isfield(config, required{index})
        error("slm_region:MissingConfig", "config is missing %s.", required{index});
    end
end

slmSize = double(config.slm_size);
if numel(slmSize) ~= 2 || any(slmSize <= 0) || any(mod(slmSize, 1) ~= 0)
    error("slm_region:InvalidSLMSize", "slm_size must be [height,width].");
end
slmSize = reshape(slmSize, 1, 2);
enabled = logical(config.active_region_enabled);
if ~isscalar(enabled)
    error("slm_region:InvalidEnabled", "active_region_enabled must be scalar.");
end

regionSize = double(config.active_region_size_px);
if isempty(regionSize)
    regionSize = slmSize;
end
if numel(regionSize) ~= 2 || any(regionSize <= 0) || ...
        any(mod(regionSize, 1) ~= 0) || any(regionSize > slmSize)
    error("slm_region:InvalidSize", ...
        "active_region_size_px must be integer [height,width] within the SLM size.");
end
regionSize = reshape(regionSize, 1, 2);

offset = double(config.active_region_offset_px);
if numel(offset) ~= 2 || any(~isfinite(offset)) || any(mod(offset, 1) ~= 0)
    error("slm_region:InvalidOffset", ...
        "active_region_offset_px must be integer [x,y].");
end
offset = reshape(offset, 1, 2);
shape = lower(string(config.active_region_shape));
if ~isscalar(shape) || ~ismember(shape, ["rectangle", "ellipse"])
    error("slm_region:InvalidShape", ...
        "active_region_shape must be rectangle or ellipse.");
end

height = slmSize(1);
width = slmSize(2);
regionHeight = regionSize(1);
regionWidth = regionSize(2);
centerX = (width + 1) / 2 + offset(1);
centerY = (height + 1) / 2 + offset(2);
left = floor(centerX - regionWidth / 2) + 1;
right = left + regionWidth - 1;
top = floor(centerY - regionHeight / 2) + 1;
bottom = top + regionHeight - 1;
if left < 1 || right > width || top < 1 || bottom > height
    error("slm_region:OutsideSLM", ...
        "The active loading region extends outside the SLM canvas.");
end

if enabled
    actualCenterX = (left + right) / 2;
    actualCenterY = (top + bottom) / 2;
    if shape == "rectangle"
        mask = false(height, width);
        mask(top:bottom, left:right) = true;
    else
        [x, y] = meshgrid(1:width, 1:height);
        radiusX = max(regionWidth / 2, eps);
        radiusY = max(regionHeight / 2, eps);
        mask = ((x - actualCenterX) ./ radiusX).^2 + ...
               ((y - actualCenterY) ./ radiusY).^2 <= 1 & ...
               x >= left & x <= right & y >= top & y <= bottom;
    end
    centerX = actualCenterX;
    centerY = actualCenterY;
else
    mask = true(height, width);
    shape = "full";
    regionSize = slmSize;
    offset = [0, 0];
    centerX = (width + 1) / 2;
    centerY = (height + 1) / 2;
    left = 1; right = width; top = 1; bottom = height;
end

details = struct();
details.enabled = enabled;
details.shape = char(shape);
details.size_px = regionSize;
details.offset_xy_px = offset;
details.center_xy_px = [centerX, centerY];
details.bounds_lrtb_px = [left, right, top, bottom];
details.active_pixel_count = nnz(mask);
details.fill_fraction = nnz(mask) / numel(mask);
details.outside_behavior = "calibrated base phase; physical aperture or matched illumination recommended";
end
