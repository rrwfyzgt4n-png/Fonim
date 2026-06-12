import Foundation

public struct DockerRunCommand: Equatable {
    public let executable: String
    public let arguments: [String]
    public let containerName: String

    public var displayCommand: String {
        ShellQuoting.commandLine(executable: "docker", arguments: arguments)
    }
}

public enum DockerCommandBuilder {
    public static func make(
        sessionID: String,
        voice: String,
        cfgScale: String,
        projectRoot: URL = AppDefaults.projectRoot
    ) -> DockerRunCommand {
        let containerName = "vibevoice_batch_" + sanitizedContainerComponent(sessionID)
        let executable = resolveDockerExecutable()
        let arguments = [
            "run", "--rm", "-it",
            "--name", containerName,
            "--platform", "linux/amd64",
            "--cpus=5",
            "--memory=22g",
            "-e", "OMP_NUM_THREADS=5",
            "-e", "TOKENIZERS_PARALLELISM=false",
            "-v", "\(projectRoot.outputsDirectory.path):/app/outputs",
            "-v", "\(projectRoot.hfCacheDirectory.path):/root/.cache/huggingface",
            "-v", "\(projectRoot.stagingInputFile.path):/app/input.txt:ro",
            AppDefaults.dockerImage,
            "python", "demo/realtime_model_inference_from_file.py",
            "--device", "cpu",
            "--model_path", AppDefaults.modelPath,
            "--txt_path", "/app/input.txt",
            "--speaker_name", voice,
            "--cfg_scale", cfgScale,
            "--output_dir", "/app/outputs"
        ]
        return DockerRunCommand(executable: executable, arguments: arguments, containerName: containerName)
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
