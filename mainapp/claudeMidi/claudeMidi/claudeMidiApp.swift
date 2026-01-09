//
//  claudeMidiApp.swift
//  claudeMidi
//
//  Created by macmini1 on 29/12/25.
//

import SwiftUI
import AVFoundation

@main
struct claudeMidiApp: App {

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
