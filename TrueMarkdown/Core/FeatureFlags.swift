import Foundation

/// Compile-time feature toggles controlled by the DIRECT_DOWNLOAD build flag.
enum FeatureFlags {
    /// Pandoc-based import (PDF/HTML → Markdown). Direct download only.
#if DIRECT_DOWNLOAD
    static let pandocEnabled = true
    /// Sparkle auto-updater. Direct download only.
    static let sparkleEnabled = true
#else
    static let pandocEnabled = false
    static let sparkleEnabled = false
#endif
}
