//
//  MindlodyApp.swift
//  Mindlody
//
//  Created by Teancum Tian on 2/15/26.
//

import SwiftUI
import CoreData

@main
struct MindlodyApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
