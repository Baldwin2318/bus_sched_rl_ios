import Foundation

protocol AppConfigurationProviding {
    var stmAPIKey: String { get }
}

struct BundleAppConfiguration: AppConfigurationProviding {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var stmAPIKey: String {
        guard let value = bundle.object(forInfoDictionaryKey: "STMApiKey") as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return value
    }
}
