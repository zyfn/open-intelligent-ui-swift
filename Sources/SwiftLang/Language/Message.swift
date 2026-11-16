import Foundation

/// The shared message protocol: context is parsed JSON or raw text, and end
/// identifies a complete winning content section.
public struct ParsedMessage: Sendable {
    public var content: String
    public var context: JSONValue
    public var attributes: [String: String]
    public var end: Bool

    public init(content: String, context: JSONValue = .null,
                attributes: [String: String] = [:], end: Bool = false) {
        self.content = content; self.context = context
        self.attributes = attributes; self.end = end
    }
}

public func parseMessage(_ text: String, streaming: Bool = false) -> ParsedMessage {
    let core = SharedCore.shared
    return core.sync {
        let value = core.core("parseMessage", [text, ["streaming": streaming]])
        return ParsedMessage(content: value.forProperty("content").toString(),
            context: core.authoringJSON(value.forProperty("context")),
            attributes: Dictionary(core.entries(value.forProperty("attributes")).map {
                ($0.0.displayString, $0.1.toString()!)
            }, uniquingKeysWith: { _, new in new }), end: value.forProperty("end").toBool())
    }
}

/// Lang parsing consumes only content. Keep message selection in the shared
/// protocol parser without projecting its unused context into Swift on every
/// streamed chunk. The public message API still returns the full context.
func parseMessageContent(_ text: String, streaming: Bool = false, protectedPrefix: Int = 0) -> String {
    let core = SharedCore.shared
    return core.sync {
        core.call("messageContent", [text, streaming, protectedPrefix]).toString()
    }
}

/// Locates the transport boundary before invoking the shared message parser.
/// Only the raw prefix is protected by Lang's quote/comment delimiters; after
/// the first real frame, the protocol owns retries, including truncated quotes.
/// This scan keeps bounded state and visits each new UTF-16 unit once.
struct MessageProbe {
    private static let prefix = Array("]]>openui:".utf16)
    private static let content = Array("content".utf16)
    private var boundary: Int?
    private var candidate: Candidate?
    private var units = 0
    private var quote: UInt16?
    private var escaped = false
    private var comment = false
    private var slash = false
    private var lineStart = true

    private struct Candidate {
        let start: Int
        let lineStart: Bool
        var matched = 1
        var kindLength = 0
        var content = true
        var query = false
        var carriageReturn = false

        var valid: Bool {
            matched == MessageProbe.prefix.count && kindLength > 0
                && (lineStart || (content && kindLength == MessageProbe.content.count))
        }

        var held: Bool {
            // The official protocol holds a partial line marker, or a mid-line
            // content retry once its "]]>" prefix has arrived.
            lineStart || matched >= 3
        }

        mutating func append(_ unit: UInt16) -> Bool {
            if matched < MessageProbe.prefix.count {
                guard unit == MessageProbe.prefix[matched] else { return false }
                matched += 1
                return true
            }
            if query { return true }
            if unit == 10 { return valid }
            if carriageReturn { return false }
            if (97...122).contains(unit) {
                content = content && kindLength < MessageProbe.content.count
                    && unit == MessageProbe.content[kindLength]
                kindLength += 1
                return lineStart || content
            }
            if unit == 63, valid { query = true; return true }
            if unit == 13, valid { carriageReturn = true; return true }
            return false
        }
    }

    mutating func append(_ chunk: String) {
        guard boundary == nil else { return }
        for unit in chunk.utf16 {
            let offset = units
            units += 1
            if var current = candidate {
                if current.append(unit) {
                    candidate = current
                    if unit == 10 {
                        boundary = current.start
                        candidate = nil
                        return
                    }
                    lineStart = false
                    continue
                }
                if current.matched == 2, unit == 93 {
                    // In "]]]>" the last two brackets can start a mid-line
                    // retry; do not lose that overlap at a chunk boundary.
                    candidate = Candidate(start: offset - 1, lineStart: false, matched: 2)
                    lineStart = false
                    continue
                }
                candidate = nil
            }

            if let delimiter = quote {
                if escaped { escaped = false }
                else if unit == 92 { escaped = true }
                else if unit == delimiter { quote = nil }
            } else if comment {
                if unit == 10 { comment = false }
            } else if unit == 35 || (slash && unit == 47) {
                comment = true
            } else if unit == 34 || unit == 39 {
                quote = unit
            } else if unit == 93 {
                candidate = Candidate(start: offset, lineStart: lineStart)
            }
            slash = quote == nil && !comment && unit == 47
            lineStart = unit == 10
        }
    }

    /// nil keeps ordinary Lang on the incremental parser path. A temporary
    /// partial marker is reconsidered if more bytes invalidate it or completion
    /// makes it actual input; only a newline confirms a permanent boundary.
    func protectedPrefix(complete: Bool) -> Int? {
        if let boundary { return boundary }
        guard let candidate else { return nil }
        guard complete ? candidate.valid : candidate.held else { return nil }
        return candidate.start
    }
}

public func buildMessage(content: String, context: JSONValue? = nil,
                         attributes: [(String, String)] = [], end: Bool = false) -> String {
    let core = SharedCore.shared
    return core.sync {
        let js = core.object([
            ("content", core.string(OpenUIString(content))),
            ("attributes", core.object(attributes.map { (OpenUIString($0.0), core.string(OpenUIString($0.1))) })),
        ])
        js.setValue(end, forProperty: "end")
        if let context { js.setValue(core.json(context), forProperty: "context") }
        return core.core("buildMessage", [js]).toString()
    }
}
