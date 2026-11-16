import Foundation
import JavaScriptCore

/// Native transport and budgets around the shared parser. No second lexer or
/// parser is introduced. A failed append preserves the last successful prefix.
final class CoreStreamParser: StreamParser {
    private let core = SharedCore.shared
    private let parser: JSValue
    private var input = ""
    private var inputEnvelope = NativeSourceEnvelope()
    private var selectedSource: String?
    private var selectedEnvelope = NativeSourceEnvelope()
    private var messageProbe = MessageProbe()
    private var budgetChecked = false
    private var blocked = false
    private var lastGood: ParseResult?
    private var limitError: OpenUIError?

    private var source: String { selectedSource ?? input }
    private var limited: ParseResult { limitedParseResult(preserving: lastGood, error: limitError) }

    init(schema: LibrarySchema) {
        parser = SharedCore.shared.sync {
            SharedCore.shared.core("createStreamingParser", [
                SharedCore.shared.json(SharedCore.shared.schemaJSON(schema)), schema.rootComponent as Any,
            ])
        }
    }
    @discardableResult func push(_ chunk: String, complete: Bool = false) -> ParseResult {
        core.sync {
            guard !blocked else { return limited }
            // Budget the entire wire message, including discarded attempts and
            // context. Keep it intact for a later retry frame or set -> push.
            guard inputEnvelope.append(chunk) else { blocked = true; return limited }
            input += chunk
            messageProbe.append(chunk)
            if selectedSource != nil || messageProbe.requiresSelection(complete: complete) {
                return selectInput(complete: complete)
            }
            // Ordinary Lang chunks never rescan the accumulated input for
            // message markers or rebuild the shared parser's statement cache.
            if !chunk.isEmpty { budgetChecked = false }
            guard withinBudget else { return limited }
            return accept(core.parseResult(parser.invokeMethod("push", withArguments: [chunk, complete])))
        }
    }
    @discardableResult func set(_ fullText: String, complete: Bool = false) -> ParseResult {
        core.sync {
            let extends = fullText.utf16.starts(with: input.utf16)
            if !extends { lastGood = nil }
            blocked = false; limitError = nil; budgetChecked = false; inputEnvelope = NativeSourceEnvelope()
            guard inputEnvelope.append(fullText) else {
                blocked = true; return limited
            }
            input = fullText
            messageProbe = MessageProbe(); messageProbe.append(fullText)
            return selectInput(complete: complete)
        }
    }
    func getResult(complete: Bool = false) -> ParseResult {
        core.sync {
            guard !blocked else { return limited }
            if selectedSource != nil || messageProbe.requiresSelection(complete: complete) {
                return selectInput(complete: complete)
            }
            guard withinBudget else { return limited }
            return accept(core.parseResult(parser.invokeMethod("getResult", withArguments: [complete])))
        }
    }
    private func selectInput(complete: Bool) -> ParseResult {
        if messageProbe.requiresSelection(complete: complete) {
            // The official protocol handles partial lines, mid-line retries,
            // CRLF and the last content frame. A new frame can replace a broken
            // quoted prefix, so it must not be appended to that prefix's parser.
            selectedSource = parseMessageContent(input, streaming: !complete)
            selectedEnvelope = NativeSourceEnvelope()
            guard selectedEnvelope.append(selectedSource!) else {
                blocked = true; return limited
            }
        } else {
            selectedSource = nil
        }
        budgetChecked = false
        guard withinBudget else { return limited }
        return accept(core.parseResult(parser.invokeMethod("set", withArguments: [source, complete])))
    }
    private func accept(_ result: ParseResult) -> ParseResult {
        guard !result.nativeLimitExceeded else {
            blocked = true; limitError = result.meta.errors.last
            return limited
        }
        lastGood = result
        return result
    }
    private var withinBudget: Bool {
        if blocked { return false }
        if budgetChecked { return true }
        let envelope = selectedSource == nil ? inputEnvelope : selectedEnvelope
        blocked = !envelope.triviallySafe && expressionSourceExceedsLimits(source)
        budgetChecked = !blocked
        return !blocked
    }
}

/// Only detects when to ask the official message parser to select content.
/// Bounded state and a scan of the new bytes keep unframed input incremental.
private struct MessageProbe {
    private var hasMarker = false
    private var trailingBrackets = 0
    private var lineBrackets: Int? = 0

    mutating func append(_ chunk: String) {
        guard !hasMarker else { return }
        for byte in chunk.utf8 {
            if byte == 62, trailingBrackets == 2 { hasMarker = true; return }
            trailingBrackets = byte == 93 ? min(2, trailingBrackets + 1) : 0
            if byte == 10 { lineBrackets = 0 }
            else if let count = lineBrackets {
                lineBrackets = byte == 93 && count < 2 ? count + 1 : nil
            }
        }
    }
    func requiresSelection(complete: Bool) -> Bool {
        hasMarker || (!complete && (lineBrackets == 1 || lineBrackets == 2))
    }
}
