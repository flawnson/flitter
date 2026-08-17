//
//  AppConfig.swift
//  fwitter
//
//  Created by Flawnson Tong on 2026-03-30.
//

import Foundation

enum AppConfig {
    static let baseURL = URL(string: "https://flawnson.com/api/micro-posts.php")!
    // The real token lives in Secrets.swift, which is gitignored because this
    // repo is public. See the header comment there for how to recreate it.
    static let adminToken = Secrets.adminToken
}
