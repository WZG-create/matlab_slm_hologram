function [phase, details] = generate_zernike14_phase(coefficientsWaves, slmSize, radiusPx, centerPx)
%GENERATE_ZERNIKE14_PHASE Generate a summed 14-mode aberration phase map.
%
% coefficientsWaves is a 14-element vector in waves. The phase is applied
% inside a circular pupil and is zero outside it. radiusPx defaults to
% min(height,width)/2 - 0.5, matching the full-pupil convention in HES 3.3.

if nargin < 3 || isempty(radiusPx)
    radiusPx = min(slmSize) / 2 - 0.5;
end
if nargin < 4 || isempty(centerPx)
    centerPx = [(slmSize(2) + 1) / 2, (slmSize(1) + 1) / 2];
end
if ~isnumeric(slmSize) || numel(slmSize) ~= 2 || any(slmSize <= 0) || ...
        any(mod(slmSize, 1) ~= 0)
    error("slm_zernike:InvalidSize", "slmSize must be [positive_integer_height, positive_integer_width].");
end
coefficientsWaves = double(coefficientsWaves(:));
if numel(coefficientsWaves) ~= 14 || any(~isfinite(coefficientsWaves))
    error("slm_zernike:InvalidCoefficients", "coefficientsWaves must contain 14 finite values.");
end
if ~isscalar(radiusPx) || radiusPx <= 0 || ~isfinite(radiusPx)
    error("slm_zernike:InvalidRadius", "radiusPx must be a positive finite scalar.");
end
if ~isnumeric(centerPx) || numel(centerPx) ~= 2 || any(~isfinite(centerPx))
    error("slm_zernike:InvalidCenter", "centerPx must be [x,y].");
end

height = slmSize(1);
width = slmSize(2);
[pixelX, pixelY] = meshgrid(1:width, 1:height);
x = (pixelX - centerPx(1)) ./ radiusPx;
y = (pixelY - centerPx(2)) ./ radiusPx;
r2 = x.^2 + y.^2;
mask = r2 <= 1;
phaseWaves = zeros(height, width);

if coefficientsWaves(1) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(1) .* x;
end
if coefficientsWaves(2) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(2) .* y;
end
if coefficientsWaves(3) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(3) .* (2 .* r2 - 1);
end
if coefficientsWaves(4) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(4) .* (2 .* x .* y);
end
if coefficientsWaves(5) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(5) .* (x.^2 - y.^2);
end
if coefficientsWaves(6) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(6) .* (3 .* x.^2 .* y - y.^3);
end
if coefficientsWaves(7) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(7) .* (x.^3 - 3 .* x .* y.^2);
end
if coefficientsWaves(8) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(8) .* ((3 .* r2 - 2) .* x);
end
if coefficientsWaves(9) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(9) .* ((3 .* r2 - 2) .* y);
end
if coefficientsWaves(10) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(10) .* (6 .* r2.^2 - 6 .* r2 + 1);
end
if coefficientsWaves(11) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(11) .* ((4 .* r2 - 3) .* (2 .* x .* y));
end
if coefficientsWaves(12) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(12) .* ((4 .* r2 - 3) .* (x.^2 - y.^2));
end
if coefficientsWaves(13) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(13) .* (4 .* x .* y .* (x.^2 - y.^2));
end
if coefficientsWaves(14) ~= 0
    phaseWaves = phaseWaves + coefficientsWaves(14) .* (x.^4 - 6 .* x.^2 .* y.^2 + y.^4);
end

phaseWaves(~mask) = 0;
phase = 2 * pi .* phaseWaves;
catalog = zernike14_catalog();
active = find(coefficientsWaves ~= 0);
details = struct();
details.coefficients_waves = coefficientsWaves;
details.radius_px = radiusPx;
details.center_px = reshape(centerPx, 1, 2);
details.active_keys = catalog.key(active);
details.active_names = catalog.name_zh(active);
end
