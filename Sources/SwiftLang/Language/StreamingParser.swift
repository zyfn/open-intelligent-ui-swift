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
            if selectedSource != nil || messageProbe.protectedPrefix(complete: complete) != nil {
                return selectInput(complete: complete)
            }
            // Ordinary Lang chunks never rescan the accumulated input for
            // message markers or rebuild the shared parser's statement cache.
            return accept(parse("push", [chunk, complete]))
        }
    }
    @discardableResult func set(_ fullText: String, complete: Bool = false) -> ParseResult {
        core.sync {
            let extends = fullText.utf16.starts(with: input.utf16)
            if !extends { lastGood = nil }
            blocked = false; limitError = nil; inputEnvelope = NativeSourceEnvelope()
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
            if selectedSource != nil || messageProbe.protectedPrefix(complete: complete) != nil {
                return selectInput(complete: complete)
            }
            return accept(parse("getResult", [complete]))
        }
    }
    private func selectInput(complete: Bool) -> ParseResult {
        if let prefix = messageProbe.protectedPrefix(complete: complete) {
            // The official protocol handles partial lines, mid-line retries,
            // CRLF and the last content frame. A new frame can replace a broken
            // quoted prefix, so it must not be appended to that prefix's parser.
            selectedSource = parseMessageContent(input, streaming: !complete, protectedPrefix: prefix)
            selectedEnvelope = NativeSourceEnvelope()
            guard selectedEnvelope.append(selectedSource!) else {
                blocked = true; return limited
            }
        } else {
            selectedSource = nil
        }
        return accept(parse("set", [source, complete]))
    }
    private func parse(_ method: String, _ arguments: [Any]) -> ParseResult {
        let result = NativeRuntimeTrace.measure("Parse") { parser.invokeMethod(method, withArguments: arguments)! }
        return NativeRuntimeTrace.measure("Parse projection") { core.parseResult(result) }
    }
    private func accept(_ result: ParseResult) -> ParseResult {
        guard !result.nativeLimitExceeded else {
            blocked = true; limitError = result.meta.errors.last
            return limited
        }
        lastGood = result
        return result
    }
}
