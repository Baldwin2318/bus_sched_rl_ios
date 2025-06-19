//
//  bus_sched_rl_iosApp.swift
//  bus_sched_rl_ios
//
//  Created by Baldwin Kiel Malabanan on 2025-06-18.
//

import SwiftUI

@main
struct bus_sched_rl_iosApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
