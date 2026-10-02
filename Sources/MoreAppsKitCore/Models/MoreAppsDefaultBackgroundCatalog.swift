import Foundation

/// Fixed first App Store screenshots for the package's supported catalog entries.
enum MoreAppsDefaultBackgroundCatalog {
  private static let images: [String: [String: URL]] = {
    guard let url = Bundle.module.url(forResource: "DefaultBackgrounds", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let catalog = try? JSONDecoder().decode([String: [String: URL]].self, from: data)
    else { return [:] }
    return catalog
  }()

  static func imageURL(bundleIdentifier: String, platform: MoreAppsPlatform) -> URL? {
    images[bundleIdentifier]?[platform.rawValue]
  }
}
