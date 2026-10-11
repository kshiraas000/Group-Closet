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
    @AppStorage("isDarkMode") private var isDarkMode = false

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.Color.background)
        appearance.shadowColor = .clear
        let titleFont = UIFont(name: "Lora-Medium", size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .medium)
        let largeTitleFont = UIFont(name: "Lora-Medium", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .medium)
        appearance.titleTextAttributes = [.font: titleFont, .foregroundColor: UIColor(Theme.Color.primaryText)]
        appearance.largeTitleTextAttributes = [.font: largeTitleFont, .foregroundColor: UIColor(Theme.Color.primaryText)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView(authViewModel: authViewModel)
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
}
