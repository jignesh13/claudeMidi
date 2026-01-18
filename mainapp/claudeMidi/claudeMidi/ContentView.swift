import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    
    @StateObject private var player = MIDIFluidPlayer()
    @State private var showSFPicker = false
    @State private var showMIDIPicker = false
    @State private var tempoValue: Double = 120.0
    @State private var sliderTime: Double = 0
    @State private var isDraggingSlider = false
    @State private var speedValue: Double = 1.0
    @State private var transposeValue: Int = 0
    @State private var currentPage = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                // Page Control
                HStack(spacing: 20) {
                    PageTab(title: "Player", icon: "play.circle.fill", isSelected: currentPage == 0) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage = 0
                        }
                    }
                    
                    PageTab(title: "Controls", icon: "dial.max", isSelected: currentPage == 1) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage = 1
                        }
                    }
                    
                    PageTab(title: "Mixer", icon: "slider.horizontal.3", isSelected: currentPage == 2) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage = 2
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemGray6))
                
                Divider()
                
                // Page Content
                TabView(selection: $currentPage) {
                    PlayerPage(
                        player: player,
                        showSFPicker: $showSFPicker,
                        showMIDIPicker: $showMIDIPicker,
                        sliderTime: $sliderTime,
                        isDraggingSlider: $isDraggingSlider
                    )
                    .tag(0)
                    
                    ControlsPage(
                        player: player,
                        speedValue: $speedValue,
                        transposeValue: $transposeValue
                    )
                    .tag(1)
                    
                    MixerPage(player: player)
                    .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                
            }
            .navigationTitle("Fluid MIDI Player")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showSFPicker) {
            DocumentPicker(types: [.sf2]) { url in
                showSFPicker = false
                guard url.startAccessingSecurityScopedResource() else { return }
                player.loadSoundFont(url)
                url.stopAccessingSecurityScopedResource()
            }
        }
        .sheet(isPresented: $showMIDIPicker) {
            DocumentPicker(types: [.midi]) { url in
                showMIDIPicker = false
                guard url.startAccessingSecurityScopedResource() else { return }
                player.loadMIDI(url)
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}

// MARK: - Page Tab Component
struct PageTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? .blue : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
    }
}

// MARK: - Player Page
struct PlayerPage: View {
    @ObservedObject var player: MIDIFluidPlayer
    @Binding var showSFPicker: Bool
    @Binding var showMIDIPicker: Bool
    @Binding var sliderTime: Double
    @Binding var isDraggingSlider: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // File Info Section
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "music.note.list")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            Text("SoundFont:")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(player.soundFontFileName)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.purple)
                                .frame(width: 20)
                            Text("MIDI File:")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(player.midiFileName)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(10)
                    
                    // File Load Buttons
                    HStack(spacing: 12) {
                        Button(action: { showSFPicker = true }) {
                            Label("Load SoundFont", systemImage: "square.and.arrow.down")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        
                        Button(action: { showMIDIPicker = true }) {
                            Label("Load MIDI", systemImage: "music.note")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                // Transport Controls
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        Button(action: {
                            if player.isPlaying {
                                player.pause()
                            } else {
                                player.play()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16))
                                Text(player.isPlaying ? "Pause" : "Play")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(width: 100, height: 40)
                            .background(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.8), Color.green],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .shadow(color: Color.green.opacity(0.3), radius: 4, y: 2)
                        }
                        
                        Button(action: { player.stop() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 16))
                                Text("Stop")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(width: 100, height: 40)
                            .background(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.8), Color.red],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .shadow(color: Color.red.opacity(0.3), radius: 4, y: 2)
                        }
                    }
                    
                    // Time Display and Slider
                    VStack(spacing: 10) {
                        HStack {
                            Text(formatTime(isDraggingSlider ? sliderTime : player.currentTime))
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(width: 60, alignment: .leading)
                            
                            Spacer()
                            
                            Text(formatTime(player.totalDuration))
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                        
                        Slider(
                            value: $sliderTime,
                            in: 0...max(player.totalDuration, 0.1),
                            onEditingChanged: { editing in
                                isDraggingSlider = editing
                                
                                if !editing {
                                    player.seek(to: sliderTime)
                                }
                            }
                        )
                        .accentColor(.blue)
                        .frame(height: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 16)
                .onChange(of: player.currentTime) { newTime in
                    if !isDraggingSlider {
                        sliderTime = newTime
                    }
                }
                
                Spacer()
            }
            .padding(.top, 16)
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Controls Page
struct ControlsPage: View {
    @ObservedObject var player: MIDIFluidPlayer
    @Binding var speedValue: Double
    @Binding var transposeValue: Int
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // Playback Speed Control
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(.orange)
                            .font(.system(size: 20))
                        
                        Text(String(format: "Speed: %.2fx", speedValue))
                            .font(.system(size: 16, weight: .semibold))
                        
                        Spacer()
                        
                        Button("Reset") {
                            speedValue = 1.0
                            player.setPlaybackSpeed(1.0)
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(6)
                    }
                    
                    Slider(
                        value: $speedValue,
                        in: 0.5...1.5,
                        step: 0.01
                    ) { _ in
                        player.setPlaybackSpeed(speedValue)
                    }
                    .accentColor(.orange)
                    
                    // Preset buttons
                    HStack(spacing: 12) {
                        speedPresetButton(0.5)
                        speedPresetButton(0.75)
                        speedPresetButton(1.25)
                    }
                }
                .padding(16)
                .background(Color(uiColor: .systemGray6))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                
                // Transpose Control
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.purple)
                            .font(.system(size: 20))
                        
                        Text("Transpose")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Spacer()
                        
                        Text("\(transposeValue > 0 ? "+" : "")\(transposeValue)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(transposeValue) },
                            set: {
                                transposeValue = Int($0)
                                player.transpose = transposeValue
                                player.synth.allNotesOff()

                            }
                        ),
                        in: -24...24,
                        step: 1
                    )
                    .accentColor(.purple)
                    
                    // Presets
                    HStack(spacing: 12) {
                        transposePreset(0)
                        transposePreset(-12)
                        transposePreset(12)
                    }
                }
                .padding(16)
                .background(Color(uiColor: .systemGray6))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                
                Spacer()
            }
            .padding(.top, 16)
        }
    }
    
    private func speedPresetButton(_ value: Double) -> some View {
        Button(String(format: "%.2fx", value)) {
            speedValue = value
            player.setPlaybackSpeed(value)
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.2))
        .foregroundColor(.orange)
        .cornerRadius(8)
    }
    
    private func transposePreset(_ value: Int) -> some View {
        Button(value == 0 ? "0" : "\(value > 0 ? "+" : "")\(value)") {
            transposeValue = value
            player.transpose = value
            player.synth.allNotesOff()

        }
        .font(.system(size: 14, weight: .semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.2))
        .foregroundColor(.purple)
        .cornerRadius(8)
    }
}

// MARK: - Mixer Page
struct MixerPage: View {
    @ObservedObject var player: MIDIFluidPlayer
    
    var body: some View {
        VStack(spacing: 0) {
            // Channel Mixer Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.blue)
                Text("Channel Mixer")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(action: {
                    for ch in player.channels {
                        if ch.muted {
                            ch.muted = false
                            player.setChannelMute(ch.channel, muted: false)
                        }
                        if ch.solo {
                            ch.solo = false
                            player.setChannelSolo(ch.channel, solo: false)
                        }
                    }
                }) {
                    Text("Reset All")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemGray6))
            
            Divider()
            
            // Channels List
            List(player.channels) { ch in
                HStack(spacing: 12) {
                    // Channel indicator
                    Circle()
                        .fill(ch.muted ? Color.red : (ch.solo ? Color.green : Color.blue))
                        .frame(width: 8, height: 8)
                    
                    Text(ch.name)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        // Mute Button
                        Button(action: {
                            ch.muted.toggle()
                            player.setChannelMute(ch.channel, muted: ch.muted)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: ch.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 13))
                                Text("M")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(ch.muted ? .white : .primary)
                            .frame(width: 50, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(ch.muted ? Color.red : Color.gray.opacity(0.2))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(ch.muted ? Color.red.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Solo Button
                        Button(action: {
                            ch.solo.toggle()
                            player.setChannelSolo(ch.channel, solo: ch.solo)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: ch.solo ? "star.fill" : "star")
                                    .font(.system(size: 13))
                                Text("S")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(ch.solo ? .white : .primary)
                            .frame(width: 50, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(ch.solo ? Color.green : Color.gray.opacity(0.2))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(ch.solo ? Color.green.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(PlainListStyle())
        }
    }
}


import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
