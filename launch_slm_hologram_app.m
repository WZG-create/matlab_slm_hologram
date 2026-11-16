function app = launch_slm_hologram_app()
%LAUNCH_SLM_HOLOGRAM_APP Start the interactive HOLOEYE-oriented MATLAB UI.
%
% Keep the returned handle if you want to control the app from the command
% window.  The app produces 8-bit PNG/BMP files and can place a frameless
% diagnostic window on a selected monitor in an extended desktop setup.

app = SLMHologramWorkbench();
end
