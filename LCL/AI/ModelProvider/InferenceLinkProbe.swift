import Foundation

// Step 0 probe: proves the MLX dependency graph compiles and links for iOS.
//
// These imports are the point. mlx-swift-lm pulls in mlx-swift (Metal), swift-transformers
// and swift-syntax macros, and CXGrammar (vendored xgrammar C++) — a large native graph
// that we cannot resolve or compile on Windows. Linking it is the single most valuable
// signal from the first CI run.
//
// Deliberately no runtime calls: MLX needs a real Metal GPU, which the iOS Simulator does
// not provide, so any inference here would fail for reasons unrelated to our code. Real
// inference is a device gate (docs/PHASE_1_PLAN.md, Step 7).
//
// Deleted in Step 6/7 when ModelProvider and Gemma4Provider land.

import MLXLMCommon
import MLXLLM
import MLXGuidedGeneration

enum InferenceLinkProbe {
    /// True if the MLX modules are present at compile time.
    ///
    /// Trivially true — the value is in the fact that this file *builds*.
    static let linked = true
}
