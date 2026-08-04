//
//  ClosetApp.swift
//  Closet
//
//  Created by Aashna Kshirsagar on 8/3/26.
//

import SwiftUI

@main
struct ClosetApp: App {
    @State private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(authViewModel: authViewModel)
        }
    }
}
