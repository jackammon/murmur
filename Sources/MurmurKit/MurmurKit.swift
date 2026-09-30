import Foundation
@_exported import MurmurPlatform
@_exported import MurmurStreaming

public enum MurmurKit {
    /// Re-exported from `MurmurPlatform.version` so existing call sites keep working.
    public static var version: String { MurmurPlatform.version }
}
