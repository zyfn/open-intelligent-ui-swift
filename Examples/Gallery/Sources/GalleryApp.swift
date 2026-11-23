import SwiftUI

#if os(macOS)
import AppKit

final class GalleryAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif

@main @MainActor struct GalleryApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(GalleryAppDelegate.self) private var delegate
    #endif
    private let options: GalleryOptions

    init() {
        #if DEBUG && os(iOS)
        if ProcessInfo.processInfo.environment["OPENUI_UI_TEST_SCENARIO"] != nil {
            options = GalleryOptions()
            return
        }
        #endif
        do {
            let parsed = try GalleryOptions.parse(Array(CommandLine.arguments.dropFirst()))
            if parsed.help { print(GalleryOptions.usage); exit(0) }
            if let directory = parsed.exportContracts {
                try GalleryValidation.exportContracts(to: URL(fileURLWithPath: directory, isDirectory: true))
                print("Exported openui.json and openintelligentui.json reader specifications")
            }
            if parsed.validate {
                let catalog = try GalleryCatalog(resourceRoot: GalleryResources.root())
                let report = GalleryValidation.validate(catalog)
                print("Validated \(report.variants) Gallery variants; batch=\(report.batchChecks), streamed=\(report.streamChecks), failures=\(report.failures.count)")
                report.failures.forEach { print($0) }
                exit(report.failures.isEmpty ? 0 : 1)
            }
            if parsed.exportContracts != nil { exit(0) }
            options = parsed
        } catch {
            print("OpenUIGallery: " + error.localizedDescription)
            exit(2)
        }
    }

    var body: some Scene {
        WindowGroup("OpenUI Gallery") {
            #if DEBUG && os(iOS)
            if let scenario = ProcessInfo.processInfo.environment["OPENUI_UI_TEST_SCENARIO"] {
                GalleryNativeValidationView(scenario: scenario)
            } else {
                GalleryView(options: options)
            }
            #else
            GalleryView(options: options)
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 560)
                #endif
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1240, height: 920)
        #endif
    }
}
