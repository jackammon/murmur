import ArgumentParser
import Foundation
import MurmurKit

@main
struct MurmurCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "murmur-cli",
        abstract: "Transcribe audio locally with WhisperKit.",
        version: MurmurKit.version,
        subcommands: [Transcribe.self, Models.self],
        defaultSubcommand: Transcribe.self
    )
}

// MARK: - transcribe

struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe a single audio file."
    )

    @Argument(help: "Audio file path (.wav / .mp3 / .flac / .m4a).")
    var file: String

    @Option(name: [.customShort("m"), .long],
            help: "WhisperKit model identifier. E.g. tiny, small, distil-large-v3.")
    var model: String = "small"

    @Option(name: .long,
            help: "Force language code (en, zh, ja, …). Default: auto-detect.")
    var language: String?

    @Flag(help: "Emit JSON instead of plain text.")
    var json: Bool = false

    @Flag(name: [.customShort("v"), .long],
          help: "Verbose progress (model load, timings) on stderr.")
    var verbose: Bool = false

    func run() async throws {
        let url = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("File not found: \(file)")
        }

        if verbose {
            err("◇ whisperkit / \(model): loading...")
        }
        let start = Date()
        let eng = try await WhisperKitEngine(model: model)
        let coldStart = Date().timeIntervalSince(start)
        if verbose {
            err("  ✓ loaded in \(fmt(coldStart, 2)) s")
        }

        let result = try await eng.transcribe(audioFile: url, language: language)
        let rtf = result.audioSeconds > 0 ? result.wallSeconds / result.audioSeconds : 0

        if json {
            var payload: [String: Any] = [
                "text": result.text,
                "audio_seconds": result.audioSeconds,
                "wall_seconds": result.wallSeconds,
                "rtf": rtf,
                "engine": "whisperkit",
                "model": model,
                "cold_start_seconds": coldStart,
            ]
            if let lang = result.detectedLanguage {
                payload["language"] = lang
            }
            if let ttft = result.timeToFirstToken {
                payload["ttft_seconds"] = ttft
            }
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        } else {
            print(result.text)
            if verbose {
                err("  audio=\(fmt(result.audioSeconds, 2))s wall=\(fmt(result.wallSeconds, 2))s rtf=\(fmt(rtf, 2))× \(result.detectedLanguage.map { "lang=\($0)" } ?? "")")
            }
        }
    }
}

// MARK: - models

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "List the suggested WhisperKit model identifiers."
    )

    func run() throws {
        print("[whisperkit]")
        for model in WhisperKitEngine.suggestedModels {
            print("  \(model)")
        }
    }
}

// MARK: - helpers

private func err(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8) ?? Data())
}
private func fmt(_ x: Double, _ frac: Int) -> String {
    String(format: "%.\(frac)f", x)
}
