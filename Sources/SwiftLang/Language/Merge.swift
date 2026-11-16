import Foundation

public enum MergeStatementsError: Error, Equatable, Sendable {
    case budgetExceeded
}

/// Merge with the shared parser's statement spans. A rejected operation never
/// returns a partial program or silently substitutes either input.
public func mergeStatements(_ existing: String, _ patch: String, rootId: String = "root") throws -> String {
    // Check the raw arguments before JavaScript allocates, tokenizes or strips
    // whitespace. Each source has its own input cap; the core charges both
    // sources and the root ID against one cumulative merge work allowance.
    guard OpenUIRuntimeBudget.acceptsSource(existing),
          OpenUIRuntimeBudget.acceptsSource(patch),
          OpenUIRuntimeBudget.acceptsSource(rootId) else {
        throw MergeStatementsError.budgetExceeded
    }
    let core = SharedCore.shared
    return try core.sync {
        let result = core.call("merge", [existing, patch, rootId])
        guard !result.forProperty("limitExceeded").toBool() else {
            throw MergeStatementsError.budgetExceeded
        }
        return result.forProperty("value").toString()
    }
}
