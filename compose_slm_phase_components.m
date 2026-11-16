function [phase, descriptions, normalizedComponents] = compose_slm_phase_components(components, slmConfig)
%COMPOSE_SLM_PHASE_COMPONENTS Add a stack of optical phase functions.

phase = zeros(slmConfig.slm_size);
descriptions = strings(0, 1);
normalizedComponents = struct("type", {}, "parameters", {}, "description", {});
if isempty(components)
    return;
end
if ~isstruct(components) || ~all(isfield(components, {'type', 'parameters'}), "all")
    error("slm_phase:InvalidComponents", "components must be a struct array with type and parameters fields.");
end
descriptions = strings(numel(components), 1);
normalizedComponents = repmat(struct("type", "", "parameters", struct(), "description", ""), 1, numel(components));
for index = 1:numel(components)
    [componentPhase, description, completeParameters] = generate_phase_component( ...
        components(index).type, slmConfig, components(index).parameters);
    phase = phase + componentPhase;
    descriptions(index, 1) = string(description);
    normalizedComponents(index).type = char(string(components(index).type));
    normalizedComponents(index).parameters = completeParameters;
    normalizedComponents(index).description = char(string(description));
end
phase = mod(phase, 2 * pi);
end
