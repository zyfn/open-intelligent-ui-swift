import XCTest
import Foundation
import OpenUILang
import OpenUISwiftUI
@testable import SwiftIntelligentUI

final class FunctionTests: XCTestCase {
    func testEveryExtensionFunctionAgainstGoldenData() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-03T12:00:00Z"))
        let engine = try FunctionLibrary(fixedNow: date)
        let cases = try parseJSONPreservingOrder(Self.cases).arrayItems ?? []
        let names = Set(cases.compactMap { $0.field("name")?.stringValue })
        XCTAssertEqual(names, Set(try engine.definitions().map(\.name)))
        XCTAssertEqual(names.count, 59)
        for item in cases {
            let name = try XCTUnwrap(item.field("name")?.stringValue)
            let args = Dictionary(uniqueKeysWithValues: (item.field("args")?.objectFields ?? []).map { ($0.0, Self.value($0.1)) })
            var expected = Self.value(item.field("expected") ?? .null)
            if name == "Today" {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
                expected = .string(OpenUIString(formatter.string(from: date)))
            }
            XCTAssertEqual(try engine.call(name, args), expected, name)
        }
    }

    func testInvalidArgumentsBecomeNullAndAllocationConservesAmount() throws {
        let engine = try FunctionLibrary()
        XCTAssertEqual(try engine.call("Range", ["start": .number(0), "end": .number(100_000)]), .null)
        XCTAssertEqual(try engine.call("Sqrt", ["number": .number(-1)]), .null)
        XCTAssertEqual(try engine.call("Payment", ["principal": .number(100), "rate": .number(2), "periods": .number(0)]), .null)
        XCTAssertEqual(try engine.call("AddDays", ["date": .string("2026-02-30"), "days": .number(1)]), .null)
        XCTAssertEqual(try engine.call("Default", ["value": .boolean(false), "fallback": .number(1)]), .boolean(false))
        let allocation = try engine.call("Allocate", ["total": .number(-100), "weights": .array([.number(1), .number(1), .number(1)])])
        XCTAssertEqual(ValueReading.array(allocation).compactMap { ValueReading.number($0) }.reduce(0, +), -100, accuracy: 0.000001)
        let rounded = try engine.call("Allocate", ["total": .number(100.001), "weights": .array([.number(1), .number(1), .number(1)])])
        XCTAssertEqual(ValueReading.array(rounded).compactMap { ValueReading.number($0) }.reduce(0, +), 100, accuracy: 0.000001)
    }

    @MainActor func testFunctionsExecuteThroughLangAndStateBindings() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource("root = Col([Input($total, \"总额\", \"number\"), Text(@Join(@Allocate($total, [1,1,1]), \" / \"))])\n$total = 100")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let first = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        try XCTUnwrap(state.binding(for: first, prop: "value")).wrappedValue = .number(90)
        let last = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).last)
        XCTAssertEqual(PropValue.string(last, "text"), "30 / 30 / 30")
    }

    private static func value(_ json: JSONValue) -> Value {
        switch json {
        case .null: return .null
        case .string(let s): return .string(s)
        case .number(let n): return .number(n)
        case .boolean(let b): return .boolean(b)
        case .array(let a): return .array(OpenUIArray(a.map(value)))
        case .object(let o): return .object(OpenUIObject(o.map { .init(key: $0.key, value: value($0.value)) }))
        }
    }

    private static let cases = #"""
    [
      {"name":"Append","args":{"list":[1,2],"item":3},"expected":[1,2,3]},
      {"name":"Prepend","args":{"list":[2,3],"item":1},"expected":[1,2,3]},
      {"name":"Concat","args":{"list":[1],"more":[2,3]},"expected":[1,2,3]},
      {"name":"Remove","args":{"list":[{"id":1},{"id":2}],"field":"id","value":"1"},"expected":[{"id":2}]},
      {"name":"RemoveAt","args":{"list":[1,2,3],"index":-1},"expected":[1,2]},
      {"name":"Update","args":{"list":[{"id":1,"done":false}],"field":"id","value":1,"setField":"done","setValue":true},"expected":[{"id":1,"done":true}]},
      {"name":"Toggle","args":{"list":[1,2],"item":"2"},"expected":[1]},
      {"name":"Includes","args":{"list":"hello","item":"ell"},"expected":true},
      {"name":"Find","args":{"list":[{"id":1}],"field":"id","value":"1"},"expected":{"id":1}},
      {"name":"IndexOf","args":{"list":[1,2],"item":"2"},"expected":1},
      {"name":"Take","args":{"list":[1,2,3],"n":-2},"expected":[2,3]},
      {"name":"Slice","args":{"list":"A😀B","start":1,"end":3},"expected":"😀"},
      {"name":"Unique","args":{"list":[1,"1",2]},"expected":[1,2]},
      {"name":"Reverse","args":{"list":[1,2]},"expected":[2,1]},
      {"name":"Range","args":{"start":0,"end":5,"step":2},"expected":[0,2,4]},
      {"name":"Pick","args":{"list":[7]},"expected":7},
      {"name":"Shuffle","args":{"list":[7]},"expected":[7]},
      {"name":"Flatten","args":{"list":[[1,[2]],3]},"expected":[1,[2],3]},
      {"name":"Chunk","args":{"list":[1,2,3],"size":2},"expected":[[1,2],[3]]},
      {"name":"Pow","args":{"base":2,"exponent":3},"expected":8},
      {"name":"Sqrt","args":{"number":9},"expected":3},
      {"name":"Random","args":{"min":5,"max":5,"integer":true},"expected":5},
      {"name":"Clamp","args":{"number":12,"min":0,"max":10},"expected":10},
      {"name":"Percent","args":{"part":1,"total":4},"expected":25},
      {"name":"Lerp","args":{"a":2,"b":10,"t":0.5},"expected":6},
      {"name":"Allocate","args":{"total":100,"weights":[1,1,1]},"expected":[33.34,33.33,33.33]},
      {"name":"Payment","args":{"principal":1200,"rate":0,"periods":12},"expected":100},
      {"name":"Convert","args":{"value":20,"from":"c","to":"f"},"expected":68},
      {"name":"Format","args":{"value":1234.5,"kind":"currency","decimals":2,"currency":"USD"},"expected":"$1,234.50"},
      {"name":"Join","args":{"list":[{"name":"A"},{"name":"B"}],"field":"name"},"expected":"A, B"},
      {"name":"Plural","args":{"n":2,"word":"apple"},"expected":"2 apples"},
      {"name":"Pad","args":{"value":5,"length":3},"expected":"005"},
      {"name":"Upper","args":{"text":"abc"},"expected":"ABC"},
      {"name":"Lower","args":{"text":"ABC"},"expected":"abc"},
      {"name":"Trim","args":{"text":"  a  "},"expected":"a"},
      {"name":"Capitalize","args":{"text":"new york"},"expected":"New York"},
      {"name":"Split","args":{"text":"a, b,,c"},"expected":["a","b","c"]},
      {"name":"Replace","args":{"text":"a-a","find":"a","replacement":"b"},"expected":"b-b"},
      {"name":"Duration","args":{"seconds":65,"style":"clock"},"expected":"1:05"},
      {"name":"Default","args":{"value":"","fallback":7},"expected":7},
      {"name":"MixColor","args":{"from":"#000","to":"#fff","t":0.5},"expected":"#808080"},
      {"name":"Now","args":{},"expected":"2026-11-03T12:00:00.000Z"},
      {"name":"Today","args":{},"expected":"__TODAY__"},
      {"name":"FormatDate","args":{"date":"2026-11-03","style":"iso"},"expected":"2026-11-03"},
      {"name":"AddDays","args":{"date":"2026-11-03","days":7},"expected":"2026-11-10"},
      {"name":"AddMonths","args":{"date":"2026-01-31","months":1},"expected":"2026-02-28"},
      {"name":"DaysBetween","args":{"from":"2026-11-03","to":"2026-11-10"},"expected":7},
      {"name":"MonthsBetween","args":{"from":"2026-01-31","to":"2026-03-30"},"expected":1},
      {"name":"StartOf","args":{"date":"2026-11-03","unit":"week"},"expected":"2026-11-02"},
      {"name":"GroupBy","args":{"rows":[{"k":"a","v":2},{"k":"a","v":3}],"key":"k","field":"v"},"expected":[{"key":"a","value":5}]},
      {"name":"Pivot","args":{"rows":[{"k":"A","c":"one","v":3},{"k":"A","c":"two","v":4}],"rowKey":"k","colKey":"c","field":"v"},"expected":[{"key":"A","one":3,"two":4}]},
      {"name":"Top","args":{"rows":[{"v":1},{"v":3},{"v":2}],"field":"v","n":2},"expected":[{"v":3},{"v":2}]},
      {"name":"Between","args":{"rows":[{"v":1},{"v":3}],"field":"v","min":2,"max":4},"expected":[{"v":3}]},
      {"name":"Bucket","args":{"rows":[{"date":"2026-01-01","v":2},{"date":"2026-01-03","v":4}],"dateField":"date","unit":"day","field":"v"},"expected":[{"key":"2026-01-01","value":2},{"key":"2026-01-02","value":0},{"key":"2026-01-03","value":4}]},
      {"name":"Cumulative","args":{"rows":[1,2,3],"field":""},"expected":[1,3,6]},
      {"name":"MovingAvg","args":{"rows":[2,4,6],"field":"","window":2},"expected":[2,3,5]},
      {"name":"Change","args":{"current":120,"previous":100},"expected":20},
      {"name":"Histogram","args":{"values":[0,1,2],"bins":2,"min":0,"max":2},"expected":[{"key":"0","value":1,"start":0,"end":1},{"key":"1","value":2,"start":1,"end":2}]},
      {"name":"Stats","args":{"values":[1,3]},"expected":{"count":2,"min":1,"max":3,"mean":2,"median":2,"stdev":1}}
    ]
    """#
}
