import Foundation
import SwiftUI

struct GalleryOptions {
    var library: GalleryLibrary = .openIntelligentUI
    var caseID: String?
    var program: String?
    var streamSuffix: String?
    var validate = false
    var exportContracts: String?
    var help = false
    var dark = false
    var accessibility = false
    var locale = "system"
    var width: Double = 390
    var height: Double = 844
    var zoom: Double = 1

    static func parse(_ arguments: [String]) throws -> GalleryOptions {
        var options = GalleryOptions()
        var explicitLibrary = false
        var index = 0
        func value(for flag: String) throws -> String {
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw GalleryFailure("\(flag) 缺少参数。")
            }
            index += 1
            return arguments[index]
        }
        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "--library":
                let name = try value(for: flag)
                guard let kind = GalleryLibrary(rawValue: name.lowercased()) else {
                    throw GalleryFailure("--library 必须是 openui 或 openintelligentui。")
                }
                options.library = kind; explicitLibrary = true
            case "--case": options.caseID = try value(for: flag)
            case "--program": options.program = try value(for: flag)
            case "--stream-suffix": options.streamSuffix = try value(for: flag)
            case "--export-contracts": options.exportContracts = try value(for: flag)
            case "--validate-fixtures": options.validate = true
            case "--help", "-h": options.help = true
            case "--dark": options.dark = true
            case "--accessibility": options.accessibility = true
            case "--locale":
                let locale = try value(for: flag)
                guard ["system", "en", "zh-Hans", "ar"].contains(locale) else {
                    throw GalleryFailure("--locale 支持 system、en、zh-Hans、ar。")
                }
                options.locale = locale
            case "--width", "--height", "--zoom":
                guard let number = Double(try value(for: flag)), number.isFinite else {
                    throw GalleryFailure("\(flag) 必须是有限数字。")
                }
                let range = flag == "--zoom" ? 0.5...1.5 : flag == "--width" ? 240.0...1600.0 : 320.0...1600.0
                guard range.contains(number) else { throw GalleryFailure("\(flag) 超出范围 \(range)。") }
                if flag == "--width" { options.width = number }
                else if flag == "--height" { options.height = number }
                else { options.zoom = number }
            // LaunchServices/Xcode may add these process preferences.
            case "-NSDocumentRevisionsDebugMode", "-ApplePersistenceIgnoreState": _ = try value(for: flag)
            default: throw GalleryFailure("未知 Gallery 参数：\(flag)；使用 --help 查看用法。")
            }
            index += 1
        }
        if options.program != nil && !explicitLibrary {
            throw GalleryFailure("打开外部程序必须显式指定 --library openui 或 openintelligentui。")
        }
        if options.streamSuffix != nil && options.program == nil {
            throw GalleryFailure("--stream-suffix 必须和 --program 一起使用。")
        }
        if options.program != nil && options.caseID != nil {
            throw GalleryFailure("--program 和 --case 不能同时使用。")
        }
        return options
    }

    static let usage = """
    OpenUIGallery — OpenUI / OpenIntelligentUI
      --library openui|openintelligentui  Select a product
      --case <id>                         Select a scene, component, or DesignSystem
      --program <file.openui|file.json>    Import a program (requires --library)
      --stream-suffix <file.openui>        Keep prefix incomplete; append on demand
      --width 240...1600 --height 320...1600 --zoom 0.5...1.5
      --dark --accessibility --locale system|en|zh-Hans|ar
      --validate-fixtures                 Validate both libraries, batch and stream
      --export-contracts <directory>      Export each library's reader specification
    """
}

struct GalleryViewport: Equatable {
    var width: Double = 390
    var height: Double = 844
    var zoom: Double = 1
    var horizontalSizeClass: UserInterfaceSizeClass { width < GalleryDevice.reading.size.0 ? .compact : .regular }
    var verticalSizeClass: UserInterfaceSizeClass { height <= GalleryDevice.largePhone.size.0 ? .compact : .regular }
    var scaledWidth: Double { width * zoom }
    var scaledHeight: Double { height * zoom }
    mutating func rotate() { let oldWidth = width; width = height; height = max(320, oldWidth) }
}

enum GalleryDevice: String, CaseIterable, Identifiable {
    case compact = "小屏 320×568", phone = "手机 390×844", largePhone = "大屏 430×932"
    case tablet = "平板 768×1024", reading = "阅读 720×1000"
    var id: String { rawValue }
    var size: (Double, Double) {
        switch self {
        case .compact: return (320, 568)
        case .phone: return (390, 844)
        case .largePhone: return (430, 932)
        case .tablet: return (768, 1024)
        case .reading: return (720, 1000)
        }
    }
}
