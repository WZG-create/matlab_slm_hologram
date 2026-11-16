% DEMO_GENERATE_HOLOGRAM Generate an SLM-ready hologram from a synthetic target.
% Replace `target` with a filename such as "my_target.png" for an experiment.

config = default_slm_config();
config.slm_size = [1080, 1920];
config.iterations = 150;
config.grating_period_x_px = 8;
config.output_dir = fullfile(pwd, "output_demo");

[x, y] = meshgrid(linspace(-1, 1, config.slm_size(2)), ...
                  linspace(-1, 1, config.slm_size(1)));
ring = exp(-((sqrt(x.^2 + y.^2) - 0.35) ./ 0.08).^2);
spot = exp(-((x + 0.38).^2 + (y - 0.18).^2) ./ 0.012);
target = max(ring, spot);

[grayHologram, result] = generate_slm_hologram(target, config);
fprintf("Wrote %s (%d x %d, uint8). Final normalized MSE: %.6g\n", ...
    fullfile(config.output_dir, "hologram.png"), size(grayHologram, 2), ...
    size(grayHologram, 1), result.final_normalized_mse);

figure("Name", "SLM hologram diagnostic");
subplot(1, 2, 1);
imagesc(grayHologram); axis image off; colormap gray;
title("SLM 8-bit hologram");
subplot(1, 2, 2);
imagesc(result.reconstruction); axis image off; colormap gray;
title("Numerical Fourier reconstruction");
