//
//  AppDelegate.swift
//  LogLady
//
//  Created by Jens Alfke on 3/5/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Display an Open panel instead of creating an untitled doc, on launch
        DispatchQueue.main.async {
            NSDocumentController.shared.openDocument(self)
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @IBAction func openLogDirectory(_ sender: AnyObject) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedFileTypes = ["cbllog"]
        panel.begin { resultCode in
            if resultCode == .cancel {
                return
            }
            let urls = panel.urls

            do {
                guard let first = urls.first else {
                    return
                }
                let doc = try LogDocument(contentsOf: first, ofType: first.pathExtension)
                try doc.addFiles(Array(urls.dropFirst()))

                NSDocumentController.shared.addDocument(doc)
                doc.makeWindowControllers()
                doc.showWindows()
            } catch {
                NSApp.presentError(error)
            }
        }
    }

}

