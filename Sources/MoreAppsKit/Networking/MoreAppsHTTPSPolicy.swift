import Alamofire
import Foundation

enum MoreAppsHTTPSPolicy {
    static let redirectHandler = Redirector.modify { _, request, _ in
        isSecure(request.url) ? request : nil
    }

    static func isSecure(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https"
    }
}
