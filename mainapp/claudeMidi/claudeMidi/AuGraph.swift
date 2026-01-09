//import SwiftUI
//import CoreMIDI
//import AudioToolbox
//import AVFoundation
//import UniformTypeIdentifiers
//
//// MARK: - Audio Class
//class AudioClass {
//    
//    // MARK: - Properties
//    private var processingGraph: AUGraph?
//     var samplerUnit: AudioUnit?
//    private var ioUnit: AudioUnit?
//    
//    // MARK: - Singleton
//    static let shared = AudioClass()
//    
//    private init() {}
//    
//    // MARK: - Create AU Graph
//    func createAUGraph() -> Bool {
//        var result: OSStatus = noErr
//        var samplerNode = AUNode()
//        var ioNode = AUNode()
//        
//        // Setup audio component description
//        var cd = AudioComponentDescription(
//            componentType: kAudioUnitType_MusicDevice,
//            componentSubType: kAudioUnitSubType_Sampler,
//            componentManufacturer: kAudioUnitManufacturer_Apple,
//            componentFlags: 0,
//            componentFlagsMask: 0
//        )
//        
//        // Create new AUGraph
//        result = NewAUGraph(&processingGraph)
//        guard result == noErr else {
//            print("Failed to create AUGraph: \(result)")
//            return false
//        }
//        
//        guard let graph = processingGraph else { return false }
//        
//        // Add Sampler node
//        result = AUGraphAddNode(graph, &cd, &samplerNode)
//        guard result == noErr else {
//            print("Failed to add Sampler node: \(result)")
//            return false
//        }
//        
//        // Setup Output unit
//        cd.componentType = kAudioUnitType_Output
//        cd.componentSubType = kAudioUnitSubType_RemoteIO
//        
//        // Add Output node
//        result = AUGraphAddNode(graph, &cd, &ioNode)
//        guard result == noErr else {
//            print("Failed to add Output node: \(result)")
//            return false
//        }
//        
//        // Open the graph
//        result = AUGraphOpen(graph)
//        guard result == noErr else {
//            print("Failed to open graph: \(result)")
//            return false
//        }
//        
//        // Connect nodes
//        result = AUGraphConnectNodeInput(graph, samplerNode, 0, ioNode, 0)
//        guard result == noErr else {
//            print("Failed to connect nodes: \(result)")
//            return false
//        }
//        
//        // Get references to audio units
//        var tempSamplerUnit: AudioUnit?
//        result = AUGraphNodeInfo(graph, samplerNode, nil, &tempSamplerUnit)
//        samplerUnit = tempSamplerUnit
//        guard result == noErr else {
//            print("Failed to get Sampler unit: \(result)")
//            return false
//        }
//        
//        var tempIoUnit: AudioUnit?
//        result = AUGraphNodeInfo(graph, ioNode, nil, &tempIoUnit)
//        ioUnit = tempIoUnit
//        guard result == noErr else {
//            print("Failed to get IO unit: \(result)")
//            return false
//        }
//        
//        // Set maximum frames per slice
//        if let sampler = samplerUnit {
//            var maxFPS: UInt32 = 4096
//            AudioUnitSetProperty(
//                sampler,
//                kAudioUnitProperty_MaximumFramesPerSlice,
//                kAudioUnitScope_Global,
//                0,
//                &maxFPS,
//                UInt32(MemoryLayout<UInt32>.size)
//            )
//        }
//        
//        return true
//    }
//    
//    // MARK: - Configure and Start Graph
//    func configureAndStartAudioProcessingGraph() {
//        guard let graph = processingGraph else { return }
//        
//        var result = AUGraphInitialize(graph)
//        guard result == noErr else {
//            print("Failed to initialize graph: \(result)")
//            return
//        }
//        
//        result = AUGraphStart(graph)
//        guard result == noErr else {
//            print("Failed to start graph: \(result)")
//            return
//        }
//        
//        print("Audio graph started successfully")
//    }
//    
//    // MARK: - Load Sound Font
//    func loadSoundFont(url: URL? = nil, presetNumber: Int = 0, isDrum: Bool = false) {
//        guard let sampler = samplerUnit else {
//            print("Sampler unit not available")
//            return
//        }
//        
//        // Create the bank preset data structure matching AUSamplerBankPresetData layout
//        struct BankPresetData {
//            var bankURL: Unmanaged<CFURL>?
//            var bankMSB: UInt8
//            var bankLSB: UInt8
//            var presetID: UInt8
//        }
//        
//        let bankMSB = isDrum ? UInt8(kAUSampler_DefaultPercussionBankMSB) : UInt8(kAUSampler_DefaultMelodicBankMSB)
//        
//        var presetData = BankPresetData(
//            bankURL: url != nil ? Unmanaged.passUnretained(url! as CFURL) : nil,
//            bankMSB: bankMSB,
//            bankLSB: UInt8(kAUSampler_DefaultBankLSB),
//            presetID: UInt8(presetNumber)
//        )
//        
//        let result = withUnsafePointer(to: &presetData) { ptr in
//            AudioUnitSetProperty(
//                sampler,
//                kAUSamplerProperty_LoadPresetFromBank,
//                kAudioUnitScope_Global,
//                0,
//                ptr,
//                UInt32(MemoryLayout<BankPresetData>.size)
//            )
//        }
//        
//        if result == noErr {
//            if let url = url {
//                print("Successfully loaded custom sound font: \(url.lastPathComponent) - preset \(presetNumber)")
//            } else {
//                print("Successfully loaded default GM sound bank - preset \(presetNumber)")
//            }
//        } else {
//            print("Failed to load sound font: \(result)")
//        }
//    }
//    
//    // MARK: - Load Default Sound Font
//    func loadDefaultSoundFont(presetNumber: Int = 0) {
//        loadSoundFont(url: nil, presetNumber: presetNumber, isDrum: false)
//    }
//    
//    // MARK: - Load Custom Sound Font from URL
//    func loadCustomSoundFont(url: URL, presetNumber: Int = 0, isDrum: Bool = false) {
//        loadSoundFont(url: url, presetNumber: presetNumber, isDrum: isDrum)
//    }
//    
//    // MARK: - Audio Init
//    func audioInit() {
//        print("Initializing audio...")
//        
//        // Configure audio session
//        do {
//            let audioSession = AVAudioSession.sharedInstance()
//            try audioSession.setCategory(.playback, mode: .default)
//            try audioSession.setActive(true)
//            print("Audio session configured")
//        } catch {
//            print("Failed to setup audio session: \(error)")
//        }
//        
//        if createAUGraph() {
//            configureAndStartAudioProcessingGraph()
//            loadDefaultSoundFont(presetNumber: 0) // Acoustic Grand Piano
//        }
//    }
//    
//    // MARK: - Send MIDI Event
//    func midiEvent(status: UInt8, param1: UInt8, param2: UInt8) {
//        guard let sampler = samplerUnit,
//              status > 0x7F && param1 < 0x80 && param2 < 0x80 else {
//            return
//        }
//        
//        let result = MusicDeviceMIDIEvent(sampler, UInt32(status), UInt32(param1), UInt32(param2), 0)
//        if result != noErr {
//            print("MIDI event error: \(result)")
//        }
//    }
//    
//    // MARK: - All Notes Off
//    func allNotesOff(channel: UInt8 = 0) {
//        // Send All Notes Off (CC 123)
//        let status: UInt8 = 0xB0 | (channel & 0x0F)
//        midiEvent(status: status, param1: 123, param2: 0)
//    }
//    
//    // MARK: - Change Instrument
//    func changeInstrument(program: UInt8, channel: UInt8 = 0) {
//        loadDefaultSoundFont(presetNumber: Int(program))
//        
//        // Also send program change MIDI message
//        let status: UInt8 = 0xC0 | (channel & 0x0F)
//        guard let sampler = samplerUnit else { return }
//        MusicDeviceMIDIEvent(sampler, UInt32(status), UInt32(program), 0, 0)
//    }
//}
//
//// MARK: - MIDI File Player
//class MIDIFilePlayer: ObservableObject {
//    @Published var isPlaying = false
//    @Published var isPaused = false
//    @Published var currentTime: TimeInterval = 0
//    @Published var duration: TimeInterval = 0
//    @Published var tempo: Float = 1.0
//    @Published var trackNames: [String] = []
//    
//    private var musicPlayer: MusicPlayer?
//    private var musicSequence: MusicSequence?
//    private var playbackTimer: Timer?
//    
//    static let shared = MIDIFilePlayer()
//    
//    private init() {}
//    
//    // MARK: - Load MIDI File
//    func loadMIDIFile(url: URL) -> Bool {
//        print("Loading MIDI file: \(url.lastPathComponent)")
//        
//        // Dispose previous sequence
//        if let sequence = musicSequence {
//            DisposeMusicSequence(sequence)
//            musicSequence = nil
//        }
//        
//        if let player = musicPlayer {
//            DisposeMusicPlayer(player)
//            musicPlayer = nil
//        }
//        
//        // Create new sequence
//        var newSequence: MusicSequence?
//        var result = NewMusicSequence(&newSequence)
//        guard result == noErr, let sequence = newSequence else {
//            print("Failed to create sequence: \(result)")
//            return false
//        }
//        
//        // Load MIDI file
//        result = MusicSequenceFileLoad(sequence, url as CFURL, .midiType, [])
//        guard result == noErr else {
//            print("Failed to load MIDI file: \(result)")
//            DisposeMusicSequence(sequence)
//            return false
//        }
//        
//        musicSequence = sequence
//        
//        // Get sequence info
//        getSequenceInfo()
//        
//        // Create music player
//        var newPlayer: MusicPlayer?
//        result = NewMusicPlayer(&newPlayer)
//        guard result == noErr, let player = newPlayer else {
//            print("Failed to create player: \(result)")
//            return false
//        }
//        
//        musicPlayer = player
//        
//        // Set the sequence to the player
//        result = MusicPlayerSetSequence(player, sequence)
//        guard result == noErr else {
//            print("Failed to set sequence: \(result)")
//            return false
//        }
//        
//        // Connect to audio unit
//        setupAudioUnit()
//        
//        // Preroll
//        result = MusicPlayerPreroll(player)
//        guard result == noErr else {
//            print("Failed to preroll: \(result)")
//            return false
//        }
//        
//        print("MIDI file loaded successfully")
//        return true
//    }
//    
//    private func setupAudioUnit() {
//        guard let sequence = musicSequence,
//              let player = musicPlayer else { return }
//        
//        // Get the sampler unit from AudioClass
//        if let samplerUnit = AudioClass.shared.samplerUnit {
//            var trackCount: UInt32 = 0
//            MusicSequenceGetTrackCount(sequence, &trackCount)
//            
//            for i in 0..<trackCount {
//                var track: MusicTrack?
//                MusicSequenceGetIndTrack(sequence, UInt32(i), &track)
//                
//                if let track = track {
//                    MusicTrackSetDestNode(track, 0) // Use default node
//                }
//            }
//        }
//    }
//    
//    private func getSequenceInfo() {
//        guard let sequence = musicSequence else { return }
//        
//        // Get duration
//        var sequenceLength: MusicTimeStamp = 0
//        var trackCount: UInt32 = 0
//        MusicSequenceGetTrackCount(sequence, &trackCount)
//        
//        for i in 0..<trackCount {
//            var track: MusicTrack?
//            MusicSequenceGetIndTrack(sequence, UInt32(i), &track)
//            
//            if let track = track {
//                var trackLength: MusicTimeStamp = 0
//                var propSize: UInt32 = UInt32(MemoryLayout<MusicTimeStamp>.size)
//                MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &trackLength, &propSize)
//                
//                if trackLength > sequenceLength {
//                    sequenceLength = trackLength
//                }
//            }
//        }
//        
//        DispatchQueue.main.async {
//            self.duration = TimeInterval(sequenceLength)
//            self.trackNames = []
//            
//            for i in 0..<trackCount {
//                self.trackNames.append("Track \(i + 1)")
//            }
//        }
//    }
//    
//    // MARK: - Playback Controls
//    func play() {
//        guard let player = musicPlayer else { return }
//        
//        var result: OSStatus
//        
//        if isPaused {
//            // Resume from pause
//            result = MusicPlayerStart(player)
//        } else {
//            // Start from beginning or current position
//            result = MusicPlayerStart(player)
//        }
//        
//        if result == noErr {
//            DispatchQueue.main.async {
//                self.isPlaying = true
//                self.isPaused = false
//            }
//            startTimer()
//            print("Playback started")
//        } else {
//            print("Failed to start playback: \(result)")
//        }
//    }
//    
//    func pause() {
//        guard let player = musicPlayer else { return }
//        
//        let result = MusicPlayerStop(player)
//        if result == noErr {
//            DispatchQueue.main.async {
//                self.isPlaying = false
//                self.isPaused = true
//            }
//            stopTimer()
//            print("Playback paused")
//        }
//    }
//    
//    func stop() {
//        guard let player = musicPlayer else { return }
//        
//        var result = MusicPlayerStop(player)
//        if result == noErr {
//            result = MusicPlayerSetTime(player, 0)
//            DispatchQueue.main.async {
//                self.isPlaying = false
//                self.isPaused = false
//                self.currentTime = 0
//            }
//            stopTimer()
//            
//            // All notes off
//            AudioClass.shared.allNotesOff()
//            print("Playback stopped")
//        }
//    }
//    
//    func seek(to time: TimeInterval) {
//        guard let player = musicPlayer else { return }
//        
//        let result = MusicPlayerSetTime(player, MusicTimeStamp(time))
//        if result == noErr {
//            DispatchQueue.main.async {
//                self.currentTime = time
//            }
//        }
//    }
//    
//    func setTempo(_ tempo: Float) {
//        guard let player = musicPlayer else { return }
//        
//        let result = MusicPlayerSetPlayRateScalar(player, Float64(tempo))
//        if result == noErr {
//            DispatchQueue.main.async {
//                self.tempo = tempo
//            }
//            print("Tempo set to: \(tempo)")
//        }
//    }
//    
//    // MARK: - Timer for UI Updates
//    private func startTimer() {
//        stopTimer()
//        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
//            self?.updateCurrentTime()
//        }
//    }
//    
//    private func stopTimer() {
//        playbackTimer?.invalidate()
//        playbackTimer = nil
//    }
//    
//    private func updateCurrentTime() {
//        guard let player = musicPlayer else { return }
//        
//        var time: MusicTimeStamp = 0
//        MusicPlayerGetTime(player, &time)
//        
//        DispatchQueue.main.async {
//            self.currentTime = TimeInterval(time)
//            
//            // Auto-stop at end
//            if self.currentTime >= self.duration {
//                self.stop()
//            }
//        }
//    }
//}
//
//// MARK: - Document Picker
//struct DocumentPicker: UIViewControllerRepresentable {
//    enum PickerType {
//        case midi
//        case soundFont
//    }
//    
//    @Binding var isPresented: Bool
//    let pickerType: PickerType
//    let onFileSelected: (URL) -> Void
//    
//    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
//        let contentTypes: [UTType]
//        
//        switch pickerType {
//        case .midi:
//            contentTypes = [
//                UTType(filenameExtension: "mid")!,
//                UTType(filenameExtension: "midi")!
//            ]
//        case .soundFont:
//            contentTypes = [
//                UTType(filenameExtension: "sf2")!,
//                UTType(filenameExtension: "dls")!,
//                UTType(filenameExtension: "SF2")!,
//                UTType(filenameExtension: "DLS")!
//            ]
//        }
//        
//        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
//        picker.delegate = context.coordinator
//        picker.allowsMultipleSelection = false
//        return picker
//    }
//    
//    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
//    
//    func makeCoordinator() -> Coordinator {
//        Coordinator(self)
//    }
//    
//    class Coordinator: NSObject, UIDocumentPickerDelegate {
//        let parent: DocumentPicker
//        
//        init(_ parent: DocumentPicker) {
//            self.parent = parent
//        }
//        
//        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
//            if let url = urls.first {
//                // Start accessing security-scoped resource
//                if url.startAccessingSecurityScopedResource() {
//                    parent.onFileSelected(url)
//                    url.stopAccessingSecurityScopedResource()
//                }
//            }
//            parent.isPresented = false
//        }
//        
//        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
//            parent.isPresented = false
//        }
//    }
//}
//
//// MARK: - Main Content View
//struct ContentView: View {
//    @StateObject private var midiPlayer = MIDIFilePlayer.shared
//    @State private var isInitialized = false
//    @State private var showMIDIPicker = false
//    @State private var showSoundFontPicker = false
//    @State private var selectedFileName = "No file selected"
//    @State private var selectedSoundFont = "Default Apple GM"
//    @State private var soundFontURL: URL?
//    @State private var showError = false
//    @State private var errorMessage = ""
//    
//    var body: some View {
//        NavigationView {
//            VStack(spacing: 20) {
//                // Status Section
//                VStack(spacing: 10) {
//                    HStack {
//                        Circle()
//                            .fill(isInitialized ? Color.green : Color.red)
//                            .frame(width: 12, height: 12)
//                        Text(isInitialized ? "Audio Engine Running" : "Not Initialized")
//                            .font(.subheadline)
//                            .foregroundColor(.secondary)
//                    }
//                    
//                    if !selectedFileName.isEmpty && selectedFileName != "No file selected" {
//                        HStack {
//                            Image(systemName: "music.note")
//                                .foregroundColor(.blue)
//                            Text(selectedFileName)
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                                .lineLimit(1)
//                        }
//                    }
//                    
//                    HStack {
//                        Image(systemName: "waveform")
//                            .foregroundColor(.purple)
//                        Text("SoundFont: \(selectedSoundFont)")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
//                            .lineLimit(1)
//                    }
//                }
//                .padding()
//                .background(Color.gray.opacity(0.1))
//                .cornerRadius(10)
//                
//                // File Selection Buttons
//                VStack(spacing: 12) {
//                    Button(action: {
//                        if !isInitialized {
//                            AudioClass.shared.audioInit()
//                            isInitialized = true
//                        }
//                        showSoundFontPicker = true
//                    }) {
//                        Label("Load Custom SoundFont (.sf2/.dls)", systemImage: "waveform.circle")
//                            .font(.headline)
//                            .foregroundColor(.white)
//                            .padding()
//                            .frame(maxWidth: .infinity)
//                            .background(Color.purple)
//                            .cornerRadius(10)
//                    }
//                    
//                    Button(action: {
//                        if !isInitialized {
//                            AudioClass.shared.audioInit()
//                            isInitialized = true
//                        }
//                        showMIDIPicker = true
//                    }) {
//                        Label("Select MIDI File (.mid/.midi)", systemImage: "folder")
//                            .font(.headline)
//                            .foregroundColor(.white)
//                            .padding()
//                            .frame(maxWidth: .infinity)
//                            .background(Color.blue)
//                            .cornerRadius(10)
//                    }
//                }
//                .padding(.horizontal)
//                .sheet(isPresented: $showMIDIPicker) {
//                    DocumentPicker(isPresented: $showMIDIPicker, pickerType: .midi) { url in
//                        loadMIDIFile(url: url)
//                    }
//                }
//                .sheet(isPresented: $showSoundFontPicker) {
//                    DocumentPicker(isPresented: $showSoundFontPicker, pickerType: .soundFont) { url in
//                        loadSoundFont(url: url)
//                    }
//                }
//                
//                // Playback Info
//                if midiPlayer.duration > 0 {
//                    VStack(spacing: 15) {
//                        // Progress Bar
//                        VStack(alignment: .leading, spacing: 5) {
//                            HStack {
//                                Text(formatTime(midiPlayer.currentTime))
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                                Spacer()
//                                Text(formatTime(midiPlayer.duration))
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                            }
//                            
//                            GeometryReader { geometry in
//                                ZStack(alignment: .leading) {
//                                    Rectangle()
//                                        .fill(Color.gray.opacity(0.3))
//                                        .frame(height: 4)
//                                        .cornerRadius(2)
//                                    
//                                    Rectangle()
//                                        .fill(Color.blue)
//                                        .frame(width: geometry.size.width * CGFloat(midiPlayer.currentTime / max(midiPlayer.duration, 1)), height: 4)
//                                        .cornerRadius(2)
//                                }
//                            }
//                            .frame(height: 4)
//                        }
//                        .padding(.horizontal)
//                        
//                        // Playback Controls
//                        HStack(spacing: 30) {
//                            Button(action: { midiPlayer.stop() }) {
//                                Image(systemName: "stop.fill")
//                                    .font(.system(size: 30))
//                                    .foregroundColor(midiPlayer.isPlaying || midiPlayer.isPaused ? .red : .gray)
//                            }
//                            .disabled(!midiPlayer.isPlaying && !midiPlayer.isPaused)
//                            
//                            Button(action: {
//                                if midiPlayer.isPlaying {
//                                    midiPlayer.pause()
//                                } else {
//                                    midiPlayer.play()
//                                }
//                            }) {
//                                Image(systemName: midiPlayer.isPlaying ? "pause.fill" : "play.fill")
//                                    .font(.system(size: 40))
//                                    .foregroundColor(.blue)
//                            }
//                        }
//                        .padding()
//                        
//                        // Tempo Control
//                        VStack(spacing: 10) {
//                            HStack {
//                                Text("Tempo: \(String(format: "%.2f", midiPlayer.tempo))x")
//                                    .font(.subheadline)
//                                    .foregroundColor(.secondary)
//                                
//                                Spacer()
//                                
//                                Button("Reset") {
//                                    midiPlayer.setTempo(1.0)
//                                }
//                                .font(.caption)
//                            }
//                            
//                            Slider(value: Binding(
//                                get: { Double(midiPlayer.tempo) },
//                                set: { midiPlayer.setTempo(Float($0)) }
//                            ), in: 0.5...2.0, step: 0.1)
//                        }
//                        .padding(.horizontal)
//                        
//                        // Track Info
//                        if !midiPlayer.trackNames.isEmpty {
//                            VStack(alignment: .leading, spacing: 5) {
//                                Text("Tracks: \(midiPlayer.trackNames.count)")
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                            }
//                            .frame(maxWidth: .infinity, alignment: .leading)
//                            .padding(.horizontal)
//                        }
//                    }
//                    .padding()
//                    .background(Color.gray.opacity(0.1))
//                    .cornerRadius(10)
//                }
//                
//                Spacer()
//                
//                // Initialize Button
//                if !isInitialized {
//                    Button(action: {
//                        AudioClass.shared.audioInit()
//                        isInitialized = true
//                    }) {
//                        Label("Initialize Audio Engine", systemImage: "play.circle.fill")
//                            .font(.headline)
//                            .foregroundColor(.white)
//                            .padding()
//                            .frame(maxWidth: .infinity)
//                            .background(Color.green)
//                            .cornerRadius(10)
//                    }
//                    .padding()
//                }
//            }
//            .navigationTitle("MIDI Player")
//            .navigationBarTitleDisplayMode(.inline)
//            .alert("Error", isPresented: $showError) {
//                Button("OK", role: .cancel) {}
//            } message: {
//                Text(errorMessage)
//            }
//        }
//    }
//    
//    private func loadSoundFont(url: URL) {
//        // Copy to app documents directory for persistent access
//        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//        let destinationURL = documentsPath.appendingPathComponent(url.lastPathComponent)
//        
//        do {
//            // Remove existing file if it exists
//            if FileManager.default.fileExists(atPath: destinationURL.path) {
//                try FileManager.default.removeItem(at: destinationURL)
//            }
//            
//            // Copy the file
//            try FileManager.default.copyItem(at: url, to: destinationURL)
//            
//            // Load the sound font
//            AudioClass.shared.loadCustomSoundFont(url: destinationURL, presetNumber: 0, isDrum: false)
//            
//            soundFontURL = destinationURL
//            selectedSoundFont = url.lastPathComponent
//            
//            print("SoundFont loaded successfully: \(url.lastPathComponent)")
//        } catch {
//            errorMessage = "Failed to load SoundFont: \(error.localizedDescription)"
//            showError = true
//            print("Error loading SoundFont: \(error)")
//        }
//    }
//    
//    private func loadMIDIFile(url: URL) {
//        selectedFileName = url.lastPathComponent
//        
//        if midiPlayer.loadMIDIFile(url: url) {
//            print("MIDI file loaded successfully: \(url.lastPathComponent)")
//        } else {
//            errorMessage = "Failed to load MIDI file"
//            showError = true
//        }
//    }
//    
//    private func formatTime(_ time: TimeInterval) -> String {
//        let minutes = Int(time) / 60
//        let seconds = Int(time) % 60
//        return String(format: "%d:%02d", minutes, seconds)
//    }
//}
//
