import Foundation

/// Only SDK-owned interface copy belongs here. Source text, prices, URLs and
/// protocol date strings must never be used as localization keys.
enum SDKStrings {
    private static let languages = ["en", "zh-Hans", "ar"]
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues:
        languages.compactMap { language in
            // SwiftPM lowercases localization directory names; Xcode resources
            // can retain the source casing. Resolve either packaged form.
            guard let url = Bundle.module.url(forResource: language, withExtension: "lproj")
                    ?? Bundle.module.url(forResource: language.lowercased(), withExtension: "lproj"),
                  let bundle = Bundle(url: url) else { return nil }
            return (language, bundle)
        })

    /// Resolves against the SwiftUI host's locale, independently of the process
    /// language. Unsupported languages fall back to the package's English copy.
    static func text(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        let preferences = [locale.identifier.replacingOccurrences(of: "_", with: "-"), "en"]
        let language = Bundle.preferredLocalizations(from: languages, forPreferences: preferences).first ?? "en"
        let fallback = bundles["en"]?.localizedString(forKey: key, value: key, table: "OpenIntelligentUI") ?? key
        let format = bundles[language]?.localizedString(forKey: key, value: fallback, table: "OpenIntelligentUI") ?? fallback
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }
}
