import Foundation
import PackagePlugin

@main
struct MetalCompilerPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }

        let contents = try FileManager.default.contentsOfDirectory(
            at: sourceTarget.directoryURL,
            includingPropertiesForKeys: nil
        )
        let metalFiles = contents.filter { $0.pathExtension == "metal" }
        guard !metalFiles.isEmpty else { return [] }

        let metallib = context.pluginWorkDirectoryURL.appending(path: "default.metallib")

        return [
            .buildCommand(
                displayName: "Compiling Metal shaders to default.metallib",
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["metal", "-o", metallib.path] + metalFiles.map(\.path),
                inputFiles: metalFiles,
                outputFiles: [metallib]
            )
        ]
    }
}
