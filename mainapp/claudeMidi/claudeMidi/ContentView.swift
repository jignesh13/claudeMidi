//// MARK: - SwiftUI Views
//import SwiftUI
//
//struct ContentView: View {
//    @StateObject private var midiManager = MIDIManager()
//    @State private var showingFilePicker = false
//    @State private var showingMIDIDevices = false
//    @State private var showingMIDILearn = false
//    @State private var settingLoopStart = false
//    
//    var body: some View {
//        NavigationView {
//            VStack(spacing: 20) {
//                VStack(spacing: 12) {
//                    Text(midiManager.currentFileName)
//                        .font(.headline)
//                        .lineLimit(1)
//                    
//                    HStack {
//                        Text(formatTime(midiManager.currentTime))
//                        Text("/")
//                        Text(formatTime(midiManager.totalTime))
//                    }
//                    .font(.subheadline)
//                    .foregroundColor(.secondary)
//                    
//                    HStack(spacing: 20) {
//                        VStack {
//                            Text("Tempo")
//                                .font(.caption)
//                            HStack {
//                                Button("-") {
//                                    midiManager.setTempo(midiManager.tempo - 0.1)
//                                }
//                                .buttonStyle(.bordered)
//                                
//                                Text(String(format: "%.0f%%", midiManager.tempo * 100))
//                                    .frame(width: 60)
//                                    .font(.subheadline)
//                                
//                                Button("+") {
//                                    midiManager.setTempo(midiManager.tempo + 0.1)
//                                }
//                                .buttonStyle(.bordered)
//                            }
//                        }
//                        
//                        VStack {
//                            Text("Transpose")
//                                .font(.caption)
//                            HStack {
//                                Button("-") {
//                                    midiManager.transpose = max(-12, midiManager.transpose - 1)
//                                }
//                                .buttonStyle(.bordered)
//                                
//                                Text("\(midiManager.transpose > 0 ? "+" : "")\(midiManager.transpose)")
//                                    .frame(width: 60)
//                                    .font(.subheadline)
//                                
//                                Button("+") {
//                                    midiManager.transpose = min(12, midiManager.transpose + 1)
//                                }
//                                .buttonStyle(.bordered)
//                            }
//                        }
//                    }
//                    
//                    if midiManager.tracks.contains(where: { $0.isSolo }) {
//                        Button("Clear All Solo") {
//                            midiManager.unsoloAll()
//                        }
//                        .font(.caption)
//                        .foregroundColor(.orange)
//                    }
//                }
//                .padding()
//                
//                ZStack(alignment: .leading) {
//                    if midiManager.loopEnabled {
//                        GeometryReader { geometry in
//                            let totalWidth = geometry.size.width
//                            let startX = CGFloat(midiManager.loopStart / max(midiManager.totalTime, 1)) * totalWidth
//                            let endX = CGFloat(midiManager.loopEnd / max(midiManager.totalTime, 1)) * totalWidth
//                            
//                            Rectangle()
//                                .fill(Color.blue.opacity(0.2))
//                                .frame(width: endX - startX)
//                                .offset(x: startX)
//                        }
//                        .frame(height: 20)
//                    }
//                    
//                    Slider(
//                        value: Binding(
//                            get: { midiManager.currentTime },
//                            set: { midiManager.seek(to: $0) }
//                        ),
//                        in: 0...max(midiManager.totalTime, 1)
//                    )
//                }
//                .padding(.horizontal)
//                
//                HStack(spacing: 15) {
//                    Button(settingLoopStart ? "Set Loop Start" : "A") {
//                        if settingLoopStart {
//                            midiManager.loopStart = midiManager.currentTime
//                            settingLoopStart = false
//                        } else {
//                            settingLoopStart = true
//                        }
//                    }
//                    .buttonStyle(.bordered)
//                    .tint(settingLoopStart ? .blue : .gray)
//                    
//                    Button("B") {
//                        midiManager.loopEnd = midiManager.currentTime
//                        midiManager.loopEnabled = true
//                    }
//                    .buttonStyle(.bordered)
//                    
//                    Button(midiManager.loopEnabled ? "Loop: ON" : "Loop: OFF") {
//                        midiManager.loopEnabled.toggle()
//                    }
//                    .buttonStyle(.bordered)
//                    .tint(midiManager.loopEnabled ? .green : .gray)
//                    
//                    Button("Clear") {
//                        midiManager.loopEnabled = false
//                        midiManager.loopStart = 0
//                        midiManager.loopEnd = midiManager.totalTime
//                    }
//                    .buttonStyle(.bordered)
//                }
//                .font(.caption)
//                
//                HStack(spacing: 30) {
//                    Button(action: { showingFilePicker = true }) {
//                        VStack {
//                            Image(systemName: "folder")
//                                .font(.title2)
//                            Text("Load")
//                                .font(.caption)
//                        }
//                        .foregroundColor(.blue)
//                    }
//                    
//                    Button(action: { showingMIDIDevices = true }) {
//                        VStack {
//                            Image(systemName: "cable.connector")
//                                .font(.title2)
//                            Text("MIDI")
//                                .font(.caption)
//                        }
//                        .foregroundColor(midiManager.selectedInputDevice != nil || midiManager.selectedOutputDevice != nil ? .green : .blue)
//                    }
//                    
//                    Button(action: { midiManager.stop() }) {
//                        VStack {
//                            Image(systemName: "stop.fill")
//                                .font(.title2)
//                            Text("Stop")
//                                .font(.caption)
//                        }
//                        .foregroundColor(.red)
//                    }
//                    
//                    Button(action: {
//                        if midiManager.isPlaying {
//                            midiManager.pause()
//                        } else {
//                            midiManager.play()
//                        }
//                    }) {
//                        VStack {
//                            Image(systemName: midiManager.isPlaying ? "pause.fill" : "play.fill")
//                                .font(.title2)
//                            Text(midiManager.isPlaying ? "Pause" : "Play")
//                                .font(.caption)
//                        }
//                        .foregroundColor(.blue)
//                    }
//                    
//                    Button(action: {
//                        midiManager.metronome.isEnabled.toggle()
//                    }) {
//                        VStack {
//                            Image(systemName: "metronome")
//                                .font(.title2)
//                            Text("Metro")
//                                .font(.caption)
//                        }
//                        .foregroundColor(midiManager.metronome.isEnabled ? .orange : .gray)
//                    }
//                    
//                    Button(action: { showingMIDILearn = true }) {
//                        VStack {
//                            Image(systemName: "slider.horizontal.3")
//                                .font(.title2)
//                            Text("Learn")
//                                .font(.caption)
//                        }
//                        .foregroundColor(.purple)
//                    }
//                }
//                .padding()
//                
//                Divider()
//                
//                ScrollView {
//                    VStack(spacing: 12) {
//                        ForEach(midiManager.tracks) { track in
//                            TrackRow(
//                                track: track,
//                                channels: midiManager.channels,
//                                onToggleMute: {
//                                    midiManager.toggleMute(trackIndex: track.trackNumber)
//                                },
//                                onToggleSolo: {
//                                    midiManager.toggleSolo(trackIndex: track.trackNumber)
//                                }
//                            )
//                        }
//                        
//                        if midiManager.tracks.isEmpty {
//                            Text("No MIDI file loaded")
//                                .foregroundColor(.secondary)
//                                .padding()
//                        }
//                    }
//                    .padding()
//                }
//            }
//            .navigationTitle("MIDI Player")
//            .sheet(isPresented: $showingFilePicker) {
//                MIDIFilePicker(midiManager: midiManager)
//            }
//            .sheet(isPresented: $showingMIDIDevices) {
//                MIDIDeviceView(midiManager: midiManager)
//            }
//            .sheet(isPresented: $showingMIDILearn) {
//                MIDILearnView(midiManager: midiManager)
//            }
//        }
//    }
//    
//    private func formatTime(_ time: Double) -> String {
//        let minutes = Int(time) / 60
//        let seconds = Int(time) % 60
//        return String(format: "%d:%02d", minutes, seconds)
//    }
//}
