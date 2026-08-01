import MoreAppsKit
import UIKit

@MainActor
final class MoreAppsExampleViewController: UIViewController {
    private let moreAppsView = MoreAppsView(
        configuration: .init(
            title: "More Apps on Apple TV",
            cardSpacing: 28,
            contentInsets: .init(
                top: 24,
                leading: 64,
                bottom: 24,
                trailing: 64
            ),
            allowedCustomDeepLinkSchemes: ["andromeda"]
        )
    )

    override func viewDidLoad() {
        super.viewDidLoad()

        moreAppsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(moreAppsView)

        NSLayoutConstraint.activate([
            moreAppsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            moreAppsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            moreAppsView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        moreAppsView.onEvent = { event in
            print("MoreAppsKit event:", event)
        }
        moreAppsView.setApps(Self.catalog)
    }

    private static let catalog = [
        MoreApp(
            id: "andromeda",
            bundleIdentifier: "com.example.andromeda",
            name: "Andromeda 17K",
            subtitle: "A space clock for Apple TV",
            iconURL: URL(string: "https://example.com/andromeda.png"),
            destinations: [
                MoreAppDestination(
                    platform: .tvOS,
                    appStoreURL: URL(
                        string: "https://apps.apple.com/app/id0987654321"
                    )!,
                    deepLinkURL: URL(string: "andromeda://home")
                )
            ],
            sortOrder: 10
        ),
        // This entry is intentionally filtered out by a tvOS host.
        MoreApp(
            id: "phone-notes",
            bundleIdentifier: "com.example.phonenotes",
            name: "Phone Notes",
            destinations: [
                MoreAppDestination(
                    platform: .iOS,
                    appStoreURL: URL(
                        string: "https://apps.apple.com/app/id1111111111"
                    )!
                )
            ],
            sortOrder: 20
        )
    ]
}
