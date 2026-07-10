import Foundation

public struct DockerRunCommand: Equatable {
    public let executable: String
    public let arguments: [String]
    public let containerName: String
    public let estimatedGenerationSeconds: TimeInterval?
    public let estimatedGenerationSource: String?

    public var displayCommand: String {
        ShellQuoting.commandLine(executable: "docker", arguments: arguments)
    }
}

public enum DockerCommandBuilder {
    public static func make(
        sessionID: String,
        voice: String,
        cfgScale: String,
        ddpmInferenceSteps: Int = AppDefaults.defaultDDPMInferenceSteps,
        projectRoot: URL = AppDefaults.projectRoot,
        estimatedGenerationSeconds: TimeInterval? = nil,
        estimatedGenerationSource: String? = nil
    ) -> DockerRunCommand {
        let containerName = "vibevoice_batch_" + sanitizedContainerComponent(sessionID)
        let executable = resolveDockerExecutable()
        let normalizedEstimatedGenerationSeconds = estimatedGenerationSeconds.flatMap { $0 > 0 ? $0 : nil }
        var environmentArguments = [
            "-e", "OMP_NUM_THREADS=5",
            "-e", "TOKENIZERS_PARALLELISM=false"
        ]
        if let normalizedEstimatedGenerationSeconds {
            let formattedEstimate = String(
                format: "%.2f",
                locale: Locale(identifier: "en_US_POSIX"),
                normalizedEstimatedGenerationSeconds
            )
            environmentArguments.append(contentsOf: ["-e", "FONIM_ESTIMATED_GENERATION_SECONDS=\(formattedEstimate)"])
        }

        let arguments = [
            "run", "--rm", "-it",
            "--name", containerName,
            "--platform", "linux/amd64",
            "--cpus=5",
            "--memory=22g",
        ] + environmentArguments + [
            "-v", "\(projectRoot.outputsDirectory.path):/app/outputs",
            "-v", "\(projectRoot.hfCacheDirectory.path):/root/.cache/huggingface",
            "-v", "\(projectRoot.stagingInputFile.path):/app/input.txt:ro",
            "-v", "\(projectRoot.inferenceScriptOverrideFile.path):/app/demo/realtime_model_inference_from_file.py:ro",
            AppDefaults.dockerImage,
            "python", "demo/realtime_model_inference_from_file.py",
            "--device", "cpu",
            "--model_path", AppDefaults.modelPath,
            "--txt_path", "/app/input.txt",
            "--speaker_name", voice,
            "--cfg_scale", cfgScale,
            "--ddpm_inference_steps", "\(ddpmInferenceSteps)",
            "--output_dir", "/app/outputs"
        ]
        return DockerRunCommand(
            executable: executable,
            arguments: arguments,
            containerName: containerName,
            estimatedGenerationSeconds: normalizedEstimatedGenerationSeconds,
            estimatedGenerationSource: normalizedEstimatedGenerationSeconds == nil ? nil : estimatedGenerationSource
        )
    }

    private static func resolveDockerExecutable() -> String {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "docker"
    }

    private static func sanitizedContainerComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scalars).prefix(90).description
    }
}
