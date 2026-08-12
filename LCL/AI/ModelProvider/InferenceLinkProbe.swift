import Foundation

// Step 0 probe: proves the MLX dependency graph compiles and links for iOS.
//
// These imports are the point. mlx-swift-lm pulls in mlx-swift (Metal), swift-transformers
// and swift-syntax macros — a large native graph that we cannot resolve or compile on
// Windows. Linking it is the single most valuable signal from a CI run.
//
// MLXEmbedders is here because docs/CONTEXT_ENGINE.md §4 depends on on-device embeddings
// for semantic rerank, so it is worth proving now rather than in Phase 2.
//
// MLXGuidedGeneration is deliberately absent: it exists only on the package's main branch
// and is not in the 3.31.4 release. See docs/RESEARCH_LOG.md §3.
//
// Deliberately no runtime calls: MLX needs a real Metal GPU, which the iOS Simulator does
// not provide, so any inference here would fail for reasons unrelated to our code. Real
// inference is a device gate (docs/PHASE_1_PLAN.md, Step 7).
//
// Deleted in Step 6/7 when ModelProvider and Gemma4Provider land.

import MLXLMCommon
import MLXLLM
import MLXEmbedders

enum InferenceLinkProbe {
    /// True if the MLX modules are present at compile time.
    ///
    /// Trivially true — the value is in the fact that this file *builds*.
    static let linked = true
}
