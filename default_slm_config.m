function config = default_slm_config()
%DEFAULT_SLM_CONFIG Return a safe starting configuration for an SLM hologram.
%
% slm_size uses MATLAB image order: [height, width].  Replace it with the
% physical pixel dimensions of the actual spatial light modulator.

config = struct();
config.slm_size = [1080, 1920];
config.wavelength_nm = 532;
config.pixel_pitch_um = 8.0;
config.iterations = 150;
config.random_seed = 42;
config.progress_callback = [];
config.target_gamma = 1.0;
config.preserve_aspect = true;
config.target_description = "";
config.target_parameters = struct();

% Optional SLM loading aperture. The output image always keeps slm_size;
% pixels outside this region are returned to the calibrated base phase.
config.active_region_enabled = false;
config.active_region_shape = "rectangle";
config.active_region_size_px = [];
config.active_region_offset_px = [0, 0]; % [x,y] from the SLM center

% "auto" selects WGS for parameterized multi-focus targets, MRAF for
% parameterized continuous targets, and GS for other images.
config.algorithm = "auto";
config.mraf_signal_threshold = 0.02;
config.mraf_guard_px = 4;
config.mraf_signal_fraction = 0.7;
config.wgs_feedback_strength = 0.8;
config.wgs_spot_radius_px = 0;
config.wgs_detection_threshold = 0.25;
config.wgs_max_spots = 512;
config.wgs_focus_centers_px = zeros(0, 2);

config.phase_levels = 256;
config.grating_period_x_px = 0;
config.grating_period_y_px = 0;
config.phase_offset_rad = 0;
config.invert_grayscale = false;
config.phase_lut_file = "";
config.illumination_amplitude_file = ""; % Native-size measured beam amplitude.
config.background_phase_map_file = "";
config.phase_components = struct("type", {}, "parameters", {}, "description", {});

% Additive phase terms, expressed in waves.  The Zernike radius is in SLM
% pixels; leave it empty to use min(height,width)/2 - 0.5 as in HES 3.3.
config.zernike_radius_px = [];
config.tilt_x_cycles = 0;
config.tilt_y_cycles = 0;
config.fresnel_focal_length_mm = 0;
config.defocus_waves = 0;
config.astigmatism_0_waves = 0;
config.astigmatism_45_waves = 0;

config.output_dir = fullfile(pwd, "output");
config.write_bmp = true;
config.write_preview = true;
end
