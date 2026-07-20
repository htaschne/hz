//
//  hzApp.swift
//  hz
//
//  Created by Agatha Schneider on 16/04/25.
//
//  MIT License
//  See LICENSE file for details.

import SwiftUI

@main
struct hzApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 640, height: 480)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open File...") {
                    NotificationCenter.default.post(name: .hzOpenFileCommand, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("New Operation") {
                    NotificationCenter.default.post(name: .hzNewOperationCommand, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let hzOpenFileCommand = Notification.Name("hzOpenFileCommand")
    static let hzNewOperationCommand = Notification.Name("hzNewOperationCommand")
}
