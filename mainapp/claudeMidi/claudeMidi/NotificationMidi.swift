//import SwiftUI
//import AVFoundation
//import MediaPlayer
//
//// MIDI Player Manager
//class MIDIPlayerManager: ObservableObject {
//    @Published var isPlaying = false
//    @Published var currentFileName = "No file loaded"
//    @Published var currentTime: TimeInterval = 0
//    @Published var duration: TimeInterval = 0
//    
//    private var audioEngine: AVAudioEngine?
//    private var sampler: AVAudioUnitSampler?
//    private var sequencer: AVAudioSequencer?
//    private var timer: Timer?
//    
//    init() {
//        setupAudioSession()
//        setupRemoteTransportControls()
//    }
//    
//    private func setupAudioSession() {
//        do {
//            let session = AVAudioSession.sharedInstance()
//            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
//            try session.setActive(true)
//        } catch {
//            print("Failed to setup audio session: \(error)")
//        }
//    }
//    
//    func loadMIDIFile(url: URL) {
//        stop()
//        
//        do {
//            // Create audio engine
//            let engine = AVAudioEngine()
//            audioEngine = engine
//            
//            // Create mixer node for combining all samplers
//            let mixer = engine.mainMixerNode
//            
//            // Create sequencer first to analyze tracks
//            let sequencer = AVAudioSequencer(audioEngine: engine)
//            self.sequencer = sequencer
//            
//            // Load MIDI file - use .smfChannelsToTracks to separate channels
//            try sequencer.load(from: url, options: .smf_ChannelsToTracks)
//            
//            // Try to find custom soundfont in bundle first
//            var soundBankURL: URL?
//            
//            // Look for common soundfont names in bundle
//            let soundfontNames = [
//                "GeneralUser GS"     // GeneralUser GS.sf2
//               
//            ]
//            
//            for name in soundfontNames {
//                if let url = Bundle.main.url(forResource: name, withExtension: "sf2") {
//                    soundBankURL = url
//                    print("✅ Found custom soundfont: \(name).sf2")
//                    break
//                }
//            }
//            
//            // Fallback to system soundfonts if no custom one found
//            if soundBankURL == nil {
//                let systemPaths = [
//                    "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls",
//                    "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/CoreAudioResources.bundle/gs_instruments.dls"
//                ]
//                
//                for path in systemPaths {
//                    let url = URL(fileURLWithPath: path)
//                    if FileManager.default.fileExists(atPath: path) {
//                        soundBankURL = url
//                        print("✅ Using system soundfont: \(path)")
//                        break
//                    }
//                }
//            }
//            
//            if soundBankURL == nil {
//                print("⚠️ No soundfont found - using built-in presets")
//            }
//            
//            // Create a sampler for each track/channel
//            var samplers: [AVAudioUnitSampler] = []
//            
//            for (index, track) in sequencer.tracks.enumerated() {
//                // Create sampler for this track
//                let sampler = AVAudioUnitSampler()
//                
//                // Attach to engine
//                engine.attach(sampler)
//                
//                // Connect to mixer
//                let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
//                engine.connect(sampler, to: mixer, format: format)
//                
//                // Load appropriate instrument for this channel
//                // Channel 10 (index 9) is drums in General MIDI
//                let isDrumTrack = (index == 9)
//                
//                // Try to load soundfont, otherwise use preset
//                if let soundBankURL = soundBankURL {
//                    do {
//                        if isDrumTrack {
//                            // Load drum kit
//                            try sampler.loadSoundBankInstrument(
//                                at: soundBankURL,
//                                program: 0,
//                                bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB),
//                                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
//                            )
//                            print("✅ Loaded drums for track \(index)")
//                        } else {
//                            // Load melodic instrument
//                            try sampler.loadSoundBankInstrument(
//                                at: soundBankURL,
//                                program: UInt8(index % 128),
//                                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
//                                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
//                            )
//                            print("✅ Loaded instrument \(index % 128) for track \(index)")
//                        }
//                    } catch {
//                        print("❌ Failed to load soundfont for track \(index): \(error)")
//                        // Fall back to preset
//                        loadPresetForSampler(sampler, isDrum: isDrumTrack, program: UInt8(index % 128))
//                    }
//                } else {
//                    // No soundfont found, use preset
//                    loadPresetForSampler(sampler, isDrum: isDrumTrack, program: UInt8(index % 128))
//                }
//                
//                // Connect this track to its sampler
//                track.destinationAudioUnit = sampler
//                samplers.append(sampler)
//            }
//            
//            self.sampler = samplers.first // Keep reference to first sampler
//            
//            // Prepare and start engine
//            engine.prepare()
//            try engine.start()
//            
//            sequencer.prepareToPlay()
//            
//            // Get duration
//            duration = sequencer.tracks.reduce(0) { max($0, $1.lengthInSeconds) }
//            currentFileName = url.deletingPathExtension().lastPathComponent
//            currentTime = 0
//            
//            print("🎵 Loaded MIDI with \(sequencer.tracks.count) tracks, duration: \(Int(duration))s")
//            
//            // Start playback
//            try sequencer.start()
//            isPlaying = true
//            
//            startTimer()
//            updateNowPlayingInfo()
//            
//        } catch {
//            print("❌ Failed to load MIDI: \(error)")
//            print("Error details: \(error.localizedDescription)")
//        }
//    }
//    
//    private func loadPresetForSampler(_ sampler: AVAudioUnitSampler, isDrum: Bool, program: UInt8) {
////        // Use Apple's built-in instrument presets
////        do {
////            if isDrum {
////                // Load drum kit preset
////                try sampler.loadInstrument(at: URL(fileURLWithPath: ""),
////                                          program: 0,
////                                          bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB),
////                                          bankLSB: UInt8(kAUSampler_DefaultBankLSB))
////            } else {
////                // Load melodic preset
////                try sampler.loadInstrument(at: URL(fileURLWithPath: ""),
////                                          program: program,
////                                          bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
////                                          bankLSB: UInt8(kAUSampler_DefaultBankLSB))
////            }
////        } catch {
////            print("Failed to load preset: \(error)")
////        }
//    }
//    
//    func play() {
//        guard let sequencer = sequencer else { return }
//        
//        if !isPlaying {
//            do {
//                try sequencer.start()
//                isPlaying = true
//                startTimer()
//                updateNowPlayingInfo()
//            } catch {
//                print("Failed to start playback: \(error)")
//            }
//        }
//    }
//    
//    func pause() {
//        sequencer?.stop()
//        isPlaying = false
//        stopTimer()
//        updateNowPlayingInfo()
//    }
//    
//    func stop() {
//        sequencer?.stop()
//        sequencer?.currentPositionInSeconds = 0
//        audioEngine?.stop()
//        
//        audioEngine = nil
//        sampler = nil
//        sequencer = nil
//        
//        isPlaying = false
//        currentTime = 0
//        stopTimer()
//        
//        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
//    }
//    
//    private func startTimer() {
//        stopTimer()
//        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
//            guard let self = self, let sequencer = self.sequencer else { return }
//            
//            DispatchQueue.main.async {
//                self.currentTime = sequencer.currentPositionInSeconds
//                
//                if self.currentTime >= self.duration && self.isPlaying {
//                    self.stop()
//                }
//                
//                self.updateNowPlayingInfo()
//            }
//        }
//    }
//    
//    private func stopTimer() {
//        timer?.invalidate()
//        timer = nil
//    }
//    
//    private func setupRemoteTransportControls() {
//        let commandCenter = MPRemoteCommandCenter.shared()
//        
//        commandCenter.playCommand.isEnabled = true
//        commandCenter.playCommand.addTarget { [weak self] _ in
//            self?.play()
//            return .success
//        }
//        
//        commandCenter.pauseCommand.isEnabled = true
//        commandCenter.pauseCommand.addTarget { [weak self] _ in
//            self?.pause()
//            return .success
//        }
//        
//        commandCenter.stopCommand.isEnabled = true
//        commandCenter.stopCommand.addTarget { [weak self] _ in
//            self?.stop()
//            return .success
//        }
//    }
//    
//    private func updateNowPlayingInfo() {
//        var nowPlayingInfo = [String: Any]()
//        nowPlayingInfo[MPMediaItemPropertyTitle] = currentFileName
//        nowPlayingInfo[MPMediaItemPropertyArtist] = "MIDI Player"
//        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "MIDI Collection"
//        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
//        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
//        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
//        
//        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
//    }
//    
//    deinit {
//        stop()
//    }
//}
//
//// Main View
//struct ContentView: View {
//    @StateObject private var player = MIDIPlayerManager()
//    @State private var showFilePicker = false
//    
//    var body: some View {
//        NavigationView {
//            VStack(spacing: 30) {
//                Spacer()
//                
//                // Album Art Placeholder
//                ZStack {
//                    RoundedRectangle(cornerRadius: 20)
//                        .fill(LinearGradient(
//                            colors: [.blue, .purple],
//                            startPoint: .topLeading,
//                            endPoint: .bottomTrailing
//                        ))
//                        .frame(width: 250, height: 250)
//                    
//                    Image(systemName: "music.note.list")
//                        .font(.system(size: 80))
//                        .foregroundColor(.white)
//                }
//                .shadow(radius: 10)
//                
//                // Track Info
//                VStack(spacing: 8) {
//                    Text(player.currentFileName)
//                        .font(.title2)
//                        .fontWeight(.semibold)
//                        .multilineTextAlignment(.center)
//                    
//                    Text("MIDI File")
//                        .font(.subheadline)
//                        .foregroundColor(.secondary)
//                }
//                .padding(.horizontal)
//                
//                // Progress Bar
//                VStack(spacing: 8) {
//                    ProgressView(value: player.currentTime, total: max(player.duration, 0.1))
//                        .progressViewStyle(LinearProgressViewStyle())
//                    
//                    HStack {
//                        Text(timeString(player.currentTime))
//                        Spacer()
//                        Text(timeString(player.duration))
//                    }
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                }
//                .padding(.horizontal, 30)
//                
//                // Controls
//                HStack(spacing: 40) {
//                    Button(action: { player.stop() }) {
//                        Image(systemName: "stop.fill")
//                            .font(.title)
//                            .foregroundColor(.blue)
//                            .frame(width: 44, height: 44)
//                    }
//                    
//                    Button(action: {
//                        if player.isPlaying {
//                            player.pause()
//                        } else {
//                            player.play()
//                        }
//                    }) {
//                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
//                            .font(.system(size: 70))
//                            .foregroundColor(.blue)
//                    }
//                    
//                    Button(action: { showFilePicker = true }) {
//                        Image(systemName: "folder.fill")
//                            .font(.title)
//                            .foregroundColor(.blue)
//                            .frame(width: 44, height: 44)
//                    }
//                }
//                
//                Spacer()
//                Spacer()
//            }
//            .padding()
//            .navigationTitle("MIDI Player")
//            .navigationBarTitleDisplayMode(.inline)
//            .sheet(isPresented: $showFilePicker) {
//                DocumentPicker { url in
//                    player.loadMIDIFile(url: url)
//                }
//            }
//        }
//    }
//    
//    private func timeString(_ time: TimeInterval) -> String {
//        guard time.isFinite && time >= 0 else { return "0:00" }
//        let minutes = Int(time) / 60
//        let seconds = Int(time) % 60
//        return String(format: "%d:%02d", minutes, seconds)
//    }
//}
//
//// Document Picker
//struct DocumentPicker: UIViewControllerRepresentable {
//    let onPick: (URL) -> Void
//    
//    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
//        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.midi, .audio])
//        picker.delegate = context.coordinator
//        picker.allowsMultipleSelection = false
//        return picker
//    }
//    
//    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
//    
//    func makeCoordinator() -> Coordinator {
//        Coordinator(onPick: onPick)
//    }
//    
//    class Coordinator: NSObject, UIDocumentPickerDelegate {
//        let onPick: (URL) -> Void
//        
//        init(onPick: @escaping (URL) -> Void) {
//            self.onPick = onPick
//        }
//        
//        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
//            guard let url = urls.first else { return }
//            
//            // Start accessing security-scoped resource
//            guard url.startAccessingSecurityScopedResource() else {
//                print("Failed to access security-scoped resource")
//                return
//            }
//            
//            defer { url.stopAccessingSecurityScopedResource() }
//            
//            // Copy to temp location
//            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
//            try? FileManager.default.removeItem(at: tempURL)
//            
//            do {
//                try FileManager.default.copyItem(at: url, to: tempURL)
//                onPick(tempURL)
//            } catch {
//                print("Failed to copy file: \(error)")
//                onPick(url)
//            }
//        }
//    }
//}
