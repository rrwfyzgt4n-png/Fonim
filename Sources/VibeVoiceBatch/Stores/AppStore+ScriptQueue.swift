import VibeVoiceBatchCore

extension AppStore {
    func queueImportedScripts(_ scripts: [NarrationScript]) {
        for script in scripts {
            enqueueGeneration(
                text: script.text,
                voice: script.defaultVoice,
                cfgScale: script.defaultSettings.cfgScale,
                ddpmInferenceSteps: script.defaultSettings.ddpmInferenceSteps ?? AppDefaults.defaultDDPMInferenceSteps,
                backendID: script.defaultBackendID,
                modelID: script.defaultModelID
            )
        }
        statusMessage = "Queued \(scripts.count) imported scripts"
    }
}
