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
            if authViewModel.isLoading {
                ProgressView()
            } else if authViewModel.session == nil {
                SignInView(authViewModel: authViewModel)
            } else {
                Text("Signed in") // replaced by RootView in Task 7
            }
        }
    }
}
