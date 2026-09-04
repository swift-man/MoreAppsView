//
//  MoreAppsHTTPSPolicy.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

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
