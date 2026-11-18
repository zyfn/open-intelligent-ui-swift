import Foundation
import SwiftLang

/// Accept both evaluated component references and inline schema objects, just
/// as the upstream chart data helpers do. No schema coercion happens here.
struct NativeChartData: Equatable {
  struct Series: Equatable {
    let name: String
    let values: [Double]
  }
  struct Point: Equatable {
    let x: Double
    let y: Double
    let z: Double?
  }
  struct Scatter: Equatable {
    let name: String
    let points: [Point]
  }
  var labels: [String]
  var series: [Series]
  var slices: [Double]
  var scatter: [Scatter]
  var colorIndices: [Int] = []
  var isProgressive = false
  var invalidData = false
  init() { labels = []; series = []; slices = []; scatter = [] }
  init(context: OpenUIComponentContext) {
    labels = NativeValue.array(context.value("labels")).map { value in
      if case .string(let s) = value { return s.displayString }
      return NativeValue.string(value, "category") ?? ""
    }
    series = NativeValue.array(context.value("series")).map { value in
      Series(
        name: NativeValue.string(value, "category") ?? "",
        values: NativeValue.numbers(NativeValue.prop(value, "values")))
    }
    let rawRows = NativeValue.array(context.value("series"))
    if case .array = rawRows.first {
      let names = Array(labels.dropFirst())
      let rows = rawRows.map { NativeValue.array($0) }
      labels = rows.map { row in
        guard let value = row.first, !value.isNullish else { return "" }
        return toString(value).displayString
      }
      series = names.enumerated().map { index, name in
        Series(name: name, values: rows.map { row in
          let value = row.indices.contains(index + 1) ? toNumber(row[index + 1]) : 0
          return value.isFinite ? value : 0
        })
      }
    }
    // buildChartData creates JavaScript object properties: duplicate series
    // replace values, and integer property names keep ECMAScript key ordering.
    let sourceNames = Self.sourceColorIndices(series.map { OpenUIString($0.name) })
    let keyed = OpenUIObject(series.map { ObjectField(key: $0.name, value: .array($0.values.map(Value.number))) })
    colorIndices = keyed.map { sourceNames[$0.key] ?? 0 }
    series = keyed.map { Series(name: $0.key.displayString, values: NativeValue.numbers($0.value)) }
    let values = NativeValue.numbers(context.value("values"))
    slices =
      values.isEmpty
      ? NativeValue.array(context.value("labels")).compactMap { NativeValue.number($0, "value") }
      : values
    if values.isEmpty, ["PieChart", "RadialChart", "SingleStackedBarChart"].contains(context.element.typeName) {
      let valid = NativeValue.array(context.value("labels")).compactMap { value -> (String, Double)? in
        guard let number = NativeValue.number(value, "value") else { return nil }
        return (NativeValue.string(value, "category") ?? "", number)
      }
      labels = valid.map(\.0)
      slices = valid.map(\.1)
    }
    scatter = NativeValue.array(context.value("datasets")).map { value in
      Scatter(
        name: NativeValue.string(value, "name") ?? "",
        points: NativeValue.array(NativeValue.prop(value, "points")).compactMap { point in
          guard let x = NativeValue.number(point, "x"), let y = NativeValue.number(point, "y")
          else { return nil }
          return Point(x: x, y: y, z: NativeValue.number(point, "z"))
        })
    }
    if context.element.isSourceComplete {
      let polar = ["PieChart", "RadialChart", "SingleStackedBarChart"].contains(context.element.typeName)
      if !rawRows.isEmpty {
        if case .array = rawRows.first {
          let width = NativeValue.array(context.value("labels")).count
          invalidData = rawRows.contains {
            let row = NativeValue.array($0)
            return row.count != width || !row.dropFirst().allSatisfy(Self.validSample)
          }
        } else {
          invalidData = rawRows.contains {
            let raw = NativeValue.array(NativeValue.prop($0, "values"))
            return raw.count != labels.count || !raw.allSatisfy(Self.validSample)
          }
        }
      }
      if polar {
        let raw = NativeValue.array(context.value("values"))
        if !raw.isEmpty { invalidData = invalidData || raw.count != labels.count || !raw.allSatisfy(Self.validSample) }
        else {
          let rawLabels = NativeValue.array(context.value("labels"))
          invalidData = invalidData || rawLabels.count != slices.count
        }
      }
      if context.element.typeName == "ScatterChart" {
        invalidData = NativeValue.array(context.value("datasets")).contains { dataset in
          NativeValue.array(NativeValue.prop(dataset, "points")).contains {
            NativeValue.number($0, "x") == nil || NativeValue.number($0, "y") == nil
              || (NativeValue.prop($0, "z").map { !$0.isNullish && !Self.validSample($0) } ?? false)
          }
        }
      }
    }
  }
  static func validSample(_ value: Value) -> Bool {
    switch value {
    case .number(let number): return number.isFinite
    case .string(let raw):
      let text = raw.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
      return !text.isEmpty && Double(text)?.isFinite == true
    default: return false
    }
  }

  static func sourceColorIndices(_ names: [OpenUIString]) -> [OpenUIString: Int] {
    var indices: [OpenUIString: Int] = [:]
    for name in names where indices[name] == nil { indices[name] = indices.count }
    return indices
  }
  func value(_ seriesIndex: Int, _ labelIndex: Int) -> Double {
    guard series.indices.contains(seriesIndex),
      series[seriesIndex].values.indices.contains(labelIndex)
    else { return 0 }
    return series[seriesIndex].values[labelIndex]
  }
  func hasValue(_ seriesIndex: Int, _ labelIndex: Int) -> Bool {
    !invalidData && series.indices.contains(seriesIndex)
      && series[seriesIndex].values.indices.contains(labelIndex)
      && series[seriesIndex].values[labelIndex].isFinite
  }
  var accessibilityRows: [String] {
    guard !invalidData else { return [] }
    if !scatter.isEmpty {
      return scatter.flatMap { s in
        s.points.map { "\(s.name): x \($0.x), y \($0.y)" + ($0.z.map { ", z \($0)" } ?? "") }
      }
    }
    if !series.isEmpty {
      return labels.indices.compactMap { i in
        let known = series.indices.filter { hasValue($0, i) }
        guard !known.isEmpty else { return nil }
        return labels[i] + ": "
          + known.map { "\(series[$0].name) \(value($0, i))" }.joined(separator: ", ")
      }
    }
    return labels.indices.compactMap { index in
      guard slices.indices.contains(index), slices[index].isFinite else { return nil }
      return "\(labels[index]): \(slices[index])"
    }
  }
}
