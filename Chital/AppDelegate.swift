//
//  AppDelegate.swift
//  Chital
//
//  Created by Alex Titarenko on 10/15/24.
//

import Foundation
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainWindow = NSApp.windows[0]
        mainWindow.delegate = self
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false
    }
}
