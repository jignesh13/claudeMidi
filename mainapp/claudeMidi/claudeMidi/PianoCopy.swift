//import SwiftUI
//import AVFoundation
//import CoreMIDI
//import AudioToolbox
//import Combine
//
//// MARK: - Models
//
//struct MIDIFile: Identifiable, Codable {
//    let id: UUID
//    let name: String
//    let url: URL
//    var artist: String?
//    var imageName: String?
//    
//    init(id: UUID = UUID(), name: String, url: URL, artist: String? = nil, imageName: String? = nil) {
//        self.id = id
//        self.name = name
//        self.url = url
//        self.artist = artist
//        self.imageName = imageName
//    }
//}
//
//struct PlaybackState {
//    var isPlaying: Bool = false
//    var isPaused: Bool = false
//    var currentTime: TimeInterval = 0
//    var duration: TimeInterval = 0
//    var tempo: Float = 1.0
//    var transpose: Int = 0
//    var volume: Float = 0.8
//}
//
//// MARK: - Audio Unit Manager
//
//class AudioUnitManager: ObservableObject {
//    private var processingGraph: AUGraph?
//    private var samplerUnit: AudioUnit?
//    private var ioUnit: AudioUnit?
//    
//    @Published var isInitialized = false
//    
//    init() {
//        setupAudioGraph()
//    }
//    
//    private func setupAudioGraph() {
//        var graph: AUGraph?
//        var status = NewAUGraph(&graph)
//        guard status == noErr, let graph = graph else {
//            print("Failed to create AUGraph")
//            return
//        }
//        
//        self.processingGraph = graph
//        
//        var samplerDescription = AudioComponentDescription(
//            componentType: kAudioUnitType_MusicDevice,
//            componentSubType: kAudioUnitSubType_Sampler,
//            componentManufacturer: kAudioUnitManufacturer_Apple,
//            componentFlags: 0,
//            componentFlagsMask: 0
//        )
//        
//        var outputDescription = AudioComponentDescription(
//            componentType: kAudioUnitType_Output,
//            componentSubType: kAudioUnitSubType_RemoteIO,
//            componentManufacturer: kAudioUnitManufacturer_Apple,
//            componentFlags: 0,
//            componentFlagsMask: 0
//        )
//        
//        var samplerNode = AUNode()
//        var outputNode = AUNode()
//        
//        status = AUGraphAddNode(graph, &samplerDescription, &samplerNode)
//        guard status == noErr else {
//            print("Failed to add sampler node")
//            return
//        }
//        
//        status = AUGraphAddNode(graph, &outputDescription, &outputNode)
//        guard status == noErr else {
//            print("Failed to add output node")
//            return
//        }
//        
//        status = AUGraphOpen(graph)
//        guard status == noErr else {
//            print("Failed to open graph")
//            return
//        }
//        
//        status = AUGraphConnectNodeInput(graph, samplerNode, 0, outputNode, 0)
//        guard status == noErr else {
//            print("Failed to connect nodes")
//            return
//        }
//        
//        status = AUGraphNodeInfo(graph, samplerNode, nil, &samplerUnit)
//        status = AUGraphNodeInfo(graph, outputNode, nil, &ioUnit)
//        
//        status = AUGraphInitialize(graph)
//        guard status == noErr else {
//            print("Failed to initialize graph")
//            return
//        }
//        
//        status = AUGraphStart(graph)
//        guard status == noErr else {
//            print("Failed to start graph")
//            return
//        }
//        
//        DispatchQueue.main.async {
//            self.isInitialized = true
//        }
//    }
//    
////    func loadSoundFont(url: URL, program: UInt8) {
////        guard let sampler = samplerUnit else { return }
////
////        var bankData = AUSamplerBankPresetData(
////            bankURL: Unmanaged.passRetained(url as CFURL),
////            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
////            bankLSB: UInt8(kAUSampler_DefaultBankLSB),
////            presetID: program
////        )
////
////        let status = AudioUnitSetProperty(
////            sampler,
////            AudioUnitPropertyID(kAUSamplerProperty_LoadPresetFromBank),
////            AudioUnitScope(kAudioUnitScope_Global),
////            0,
////            &bankData,
////            UInt32(MemoryLayout<AUSamplerBankPresetData>.size)
////        )
////
////        if status != noErr {
////            print("Failed to load sound font: \(status)")
////        }
////    }
//    
//    func sendMIDIEvent(status: UInt8, data1: UInt8, data2: UInt8) {
//        guard let sampler = samplerUnit else { return }
//        MusicDeviceMIDIEvent(sampler, UInt32(status), UInt32(data1), UInt32(data2), 0)
//    }
//    
//    func setInstrument(program: UInt8, channel: UInt8 = 0) {
//        sendMIDIEvent(status: 0xC0 | channel, data1: program, data2: 0)
//    }
//    
//    func setVolume(_ volume: Float, channel: UInt8 = 0) {
//        let scaledVolume = UInt8(min(max(volume * 127, 0), 127))
//        sendMIDIEvent(status: 0xB0 | channel, data1: 0x07, data2: scaledVolume)
//    }
//    
//    func allNotesOff() {
//        for channel: UInt8 in 0..<16 {
//            sendMIDIEvent(status: 0xB0 | channel, data1: 0x7B, data2: 0x00)
//        }
//    }
//    
//    deinit {
//        if let graph = processingGraph {
//            AUGraphStop(graph)
//            AUGraphUninitialize(graph)
//            AUGraphClose(graph)
//            DisposeAUGraph(graph)
//        }
//    }
//}
//
//// MARK: - MIDI Player Manager
//
//class MIDIPlayerManager: ObservableObject {
//    private var musicPlayer: MusicPlayer?
//    private var musicSequence: MusicSequence?
//    private var updateTimer: Timer?
//    private let audioManager: AudioUnitManager
//    
//    @Published var state = PlaybackState()
//    @Published var currentFile: MIDIFile?
//    
//    init(audioManager: AudioUnitManager) {
//        self.audioManager = audioManager
//    }
//    
//    var currentTime: MusicTimeStamp {
//        guard let player = musicPlayer else { return 0 }
//        var time: MusicTimeStamp = 0
//        MusicPlayerGetTime(player, &time)
//        return time
//    }
//    
//    var duration: MusicTimeStamp {
//        guard let sequence = musicSequence else { return 0 }
//        var maxLength: MusicTimeStamp = 0
//        var trackCount: UInt32 = 0
//        MusicSequenceGetTrackCount(sequence, &trackCount)
//        
//        for i in 0..<trackCount {
//            var track: MusicTrack?
//            MusicSequenceGetIndTrack(sequence, i, &track)
//            
//            if let track = track {
//                var length: MusicTimeStamp = 0
//                var size = UInt32(MemoryLayout<MusicTimeStamp>.size)
//                MusicTrackGetProperty(
//                    track,
//                    kSequenceTrackProperty_TrackLength,
//                    &length,
//                    &size
//                )
//                maxLength = max(maxLength, length)
//            }
//        }
//        return maxLength
//    }
//    
//    func loadMIDIFile(_ file: MIDIFile) -> Bool {
//        stop()
//        currentFile = file
//        
//        var sequence: MusicSequence?
//        var status = NewMusicSequence(&sequence)
//        guard status == noErr, let sequence = sequence else {
//            print("Failed to create music sequence")
//            return false
//        }
//        
//        status = MusicSequenceFileLoad(
//            sequence,
//            file.url as CFURL,
//            .midiType,
//            .smf_ChannelsToTracks
//        )
//        guard status == noErr else {
//            print("Failed to load MIDI file")
//            return false
//        }
//        
//        self.musicSequence = sequence
//        
//        var player: MusicPlayer?
//        status = NewMusicPlayer(&player)
//        guard status == noErr, let player = player else {
//            print("Failed to create music player")
//            return false
//        }
//        
//        self.musicPlayer = player
//        
//        status = MusicPlayerSetSequence(player, sequence)
//        guard status == noErr else {
//            print("Failed to set sequence")
//            return false
//        }
//        
//        MusicPlayerPreroll(player)
//        
//        state.duration = TimeInterval(duration)
//        state.currentTime = 0
//        
//        return true
//    }
//    
//    func play() {
//        guard let player = musicPlayer else { return }
//        
//        if state.isPaused {
//            MusicPlayerStart(player)
//            state.isPaused = false
//        } else {
//            MusicPlayerSetTime(player, 0)
//            MusicPlayerStart(player)
//        }
//        
//        state.isPlaying = true
//        applyTempo()
//        startUpdateTimer()
//    }
//    
//    func pause() {
//        guard let player = musicPlayer else { return }
//        MusicPlayerStop(player)
//        state.isPaused = true
//        state.isPlaying = false
//        stopUpdateTimer()
//        audioManager.allNotesOff()
//    }
//    
//    func stop() {
//        guard let player = musicPlayer else { return }
//        MusicPlayerStop(player)
//        MusicPlayerSetTime(player, 0)
//        state.isPlaying = false
//        state.isPaused = false
//        state.currentTime = 0
//        stopUpdateTimer()
//        audioManager.allNotesOff()
//    }
//    
//    func seek(to time: TimeInterval) {
//        guard let player = musicPlayer else { return }
//        let wasPlaying = state.isPlaying
//        
//        if wasPlaying {
//            MusicPlayerStop(player)
//        }
//        
//        MusicPlayerSetTime(player, time)
//        state.currentTime = time
//        
//        if wasPlaying {
//            MusicPlayerStart(player)
//        }
//    }
//    
//    func setTempo(_ tempo: Float) {
//        state.tempo = max(0.05, min(3.0, tempo))
//        applyTempo()
//    }
//    
//    func setTranspose(_ semitones: Int) {
//        state.transpose = max(-5, min(6, semitones))
//    }
//    
//    func setVolume(_ volume: Float) {
//        state.volume = max(0, min(1, volume))
//        audioManager.setVolume(volume)
//    }
//    
//    private func applyTempo() {
//        guard let player = musicPlayer else { return }
//       // MusicPlayerSetPlayRateScalar(player, state.tempo)
//    }
//    
//    private func startUpdateTimer() {
//        stopUpdateTimer()
//        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
//            self?.updatePlaybackPosition()
//        }
//    }
//    
//    private func stopUpdateTimer() {
//        updateTimer?.invalidate()
//        updateTimer = nil
//    }
//    
//    private func updatePlaybackPosition() {
//        state.currentTime = TimeInterval(currentTime)
//        
//        if state.isPlaying && state.currentTime >= state.duration {
//            stop()
//        }
//    }
//    
//    deinit {
//        stop()
//        if let player = musicPlayer {
//            DisposeMusicPlayer(player)
//        }
//        if let sequence = musicSequence {
//            DisposeMusicSequence(sequence)
//        }
//    }
//}
//
//// MARK: - File Manager
//
//class MIDIFileManager: ObservableObject {
//    @Published var files: [MIDIFile] = []
//    private let documentsURL: URL
//    
//    init() {
//        documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//        loadFiles()
//    }
//    
//    func loadFiles() {
//        do {
//            let fileURLs = try FileManager.default.contentsOfDirectory(
//                at: documentsURL,
//                includingPropertiesForKeys: nil
//            ).filter { $0.pathExtension.lowercased() == "mid" || $0.pathExtension.lowercased() == "midi" }
//            
//            files = fileURLs.map { url in
//                MIDIFile(
//                    name: url.deletingPathExtension().lastPathComponent,
//                    url: url
//                )
//            }.sorted { $0.name < $1.name }
//        } catch {
//            print("Error loading files: \(error)")
//        }
//    }
//    
//    func deleteFile(_ file: MIDIFile) {
//        do {
//            try FileManager.default.removeItem(at: file.url)
//            loadFiles()
//        } catch {
//            print("Error deleting file: \(error)")
//        }
//    }
//}
//
//// MARK: - Main View
//
//struct MIDIPlayerView: View {
//    @StateObject private var audioManager = AudioUnitManager()
//    @StateObject private var fileManager = MIDIFileManager()
//    @StateObject private var playerManager: MIDIPlayerManager
//    
//    @State private var showingFileList = false
//    
//    init() {
//        let audio = AudioUnitManager()
//        _audioManager = StateObject(wrappedValue: audio)
//        _playerManager = StateObject(wrappedValue: MIDIPlayerManager(audioManager: audio))
//    }
//    
//    var body: some View {
//        NavigationView {
//            ZStack {
//                LinearGradient(
//                    colors: [Color.black, Color.blue.opacity(0.3)],
//                    startPoint: .top,
//                    endPoint: .bottom
//                )
//                .ignoresSafeArea()
//                
//                VStack(spacing: 20) {
//                    // Header
//                    Text("MIDI Player")
//                        .font(.system(size: 32, weight: .bold, design: .rounded))
//                        .foregroundColor(.white)
//                        .padding(.top, 20)
//                    
//                    // Current File Display
//                    currentFileCard
//                    
//                    // Playback Controls
//                    playbackControls
//                    
//                    // Transport Controls
//                    transportControls
//                    
//                    // Settings
//                    settingsSection
//                    
//                    Spacer()
//                    
//                    // File List Button
//                    Button(action: { showingFileList = true }) {
//                        HStack {
//                            Image(systemName: "music.note.list")
//                            Text("Song Library")
//                        }
//                        .font(.headline)
//                        .foregroundColor(.white)
//                        .frame(maxWidth: .infinity)
//                        .padding()
//                        .background(Color.blue)
//                        .cornerRadius(15)
//                    }
//                    .padding(.horizontal)
//                }
//            }
//            .sheet(isPresented: $showingFileList) {
//                FileListView(
//                    fileManager: fileManager,
//                    playerManager: playerManager
//                )
//            }
//        }
//    }
//    
//    // MARK: - View Components
//    
//    private var currentFileCard: some View {
//        VStack(spacing: 12) {
//            if let file = playerManager.currentFile {
//                Image(systemName: "music.note")
//                    .font(.system(size: 60))
//                    .foregroundColor(.white)
//                    .frame(width: 120, height: 120)
//                    .background(
//                        Circle()
//                            .fill(Color.white.opacity(0.1))
//                    )
//                
//                Text(file.name)
//                    .font(.title3)
//                    .fontWeight(.semibold)
//                    .foregroundColor(.white)
//                    .lineLimit(2)
//                    .multilineTextAlignment(.center)
//                
//                if let artist = file.artist {
//                    Text(artist)
//                        .font(.subheadline)
//                        .foregroundColor(.white.opacity(0.7))
//                }
//            } else {
//                Image(systemName: "music.note.slash")
//                    .font(.system(size: 60))
//                    .foregroundColor(.white.opacity(0.5))
//                    .frame(width: 120, height: 120)
//                
//                Text("No file selected")
//                    .font(.title3)
//                    .foregroundColor(.white.opacity(0.7))
//            }
//        }
//        .frame(maxWidth: .infinity)
//        .padding(.vertical, 30)
//        .background(
//            RoundedRectangle(cornerRadius: 20)
//                .fill(Color.white.opacity(0.1))
//        )
//        .padding(.horizontal)
//    }
//    
//    private var playbackControls: some View {
//        VStack(spacing: 15) {
//            // Progress Bar
//            VStack(spacing: 8) {
//                HStack {
//                    Text(formatTime(playerManager.state.currentTime))
//                        .font(.caption)
//                        .foregroundColor(.white.opacity(0.7))
//                    
//                    Spacer()
//                    
//                    Text(formatTime(playerManager.state.duration))
//                        .font(.caption)
//                        .foregroundColor(.white.opacity(0.7))
//                }
//                
//                GeometryReader { geometry in
//                    ZStack(alignment: .leading) {
//                        RoundedRectangle(cornerRadius: 4)
//                            .fill(Color.white.opacity(0.2))
//                            .frame(height: 8)
//                        
//                        RoundedRectangle(cornerRadius: 4)
//                            .fill(Color.blue)
//                            .frame(
//                                width: playerManager.state.duration > 0
//                                    ? geometry.size.width * CGFloat(playerManager.state.currentTime / playerManager.state.duration)
//                                    : 0,
//                                height: 8
//                            )
//                    }
//                }
//                .frame(height: 8)
//                .gesture(
//                    DragGesture(minimumDistance: 0)
//                        .onChanged { value in
//                            let ratio = value.location.x / UIScreen.main.bounds.width * 0.9
//                            let newTime = playerManager.state.duration * TimeInterval(ratio)
//                            playerManager.seek(to: max(0, min(newTime, playerManager.state.duration)))
//                        }
//                )
//            }
//            .padding(.horizontal)
//        }
//    }
//    
//    private var transportControls: some View {
//        HStack(spacing: 30) {
//            // Previous (Rewind)
//            Button(action: {
//                playerManager.seek(to: max(0, playerManager.state.currentTime - 10))
//            }) {
//                Image(systemName: "backward.fill")
//                    .font(.system(size: 24))
//                    .foregroundColor(.white)
//            }
//            .disabled(playerManager.currentFile == nil)
//            
//            // Play/Pause
//            Button(action: {
//                if playerManager.state.isPlaying {
//                    playerManager.pause()
//                } else {
//                    playerManager.play()
//                }
//            }) {
//                Image(systemName: playerManager.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
//                    .font(.system(size: 64))
//                    .foregroundColor(.white)
//            }
//            .disabled(playerManager.currentFile == nil)
//            
//            // Stop
//            Button(action: {
//                playerManager.stop()
//            }) {
//                Image(systemName: "stop.fill")
//                    .font(.system(size: 24))
//                    .foregroundColor(.white)
//            }
//            .disabled(playerManager.currentFile == nil)
//            
//            // Next (Fast Forward)
//            Button(action: {
//                playerManager.seek(to: min(playerManager.state.duration, playerManager.state.currentTime + 10))
//            }) {
//                Image(systemName: "forward.fill")
//                    .font(.system(size: 24))
//                    .foregroundColor(.white)
//            }
//            .disabled(playerManager.currentFile == nil)
//        }
//        .padding(.vertical)
//    }
//    
//    private var settingsSection: some View {
//        VStack(spacing: 20) {
//            // Volume
//            VStack(alignment: .leading, spacing: 8) {
//                HStack {
//                    Image(systemName: "speaker.fill")
//                        .foregroundColor(.white)
//                    Text("Volume")
//                        .foregroundColor(.white)
//                    Spacer()
//                    Text("\(Int(playerManager.state.volume * 100))%")
//                        .foregroundColor(.white.opacity(0.7))
//                }
//                
//                Slider(value: Binding(
//                    get: { playerManager.state.volume },
//                    set: { playerManager.setVolume($0) }
//                ), in: 0...1)
//                    .accentColor(.blue)
//            }
//            
//            // Tempo
//            VStack(alignment: .leading, spacing: 8) {
//                HStack {
//                    Image(systemName: "metronome")
//                        .foregroundColor(.white)
//                    Text("Tempo")
//                        .foregroundColor(.white)
//                    Spacer()
//                    Text(String(format: "%.2f", playerManager.state.tempo))
//                        .foregroundColor(.white.opacity(0.7))
//                }
//                
//                HStack {
//                    Button(action: {
//                        playerManager.setTempo(playerManager.state.tempo - 0.05)
//                    }) {
//                        Image(systemName: "minus.circle")
//                            .foregroundColor(.white)
//                    }
//                    
//                    Slider(value: Binding(
//                        get: { playerManager.state.tempo },
//                        set: { playerManager.setTempo($0) }
//                    ), in: 0.5...2.0)
//                        .accentColor(.blue)
//                    
//                    Button(action: {
//                        playerManager.setTempo(playerManager.state.tempo + 0.05)
//                    }) {
//                        Image(systemName: "plus.circle")
//                            .foregroundColor(.white)
//                    }
//                    
//                    Button(action: {
//                        playerManager.setTempo(1.0)
//                    }) {
//                        Text("Reset")
//                            .font(.caption)
//                            .foregroundColor(.white)
//                            .padding(.horizontal, 8)
//                            .padding(.vertical, 4)
//                            .background(Color.blue)
//                            .cornerRadius(8)
//                    }
//                }
//            }
//            
//            // Transpose
//            VStack(alignment: .leading, spacing: 8) {
//                HStack {
//                    Image(systemName: "music.note")
//                        .foregroundColor(.white)
//                    Text("Transpose")
//                        .foregroundColor(.white)
//                    Spacer()
//                    Text("\(playerManager.state.transpose > 0 ? "+" : "")\(playerManager.state.transpose)")
//                        .foregroundColor(.white.opacity(0.7))
//                }
//                
//                HStack {
//                    Button(action: {
//                        playerManager.setTranspose(playerManager.state.transpose - 1)
//                    }) {
//                        Image(systemName: "minus.circle")
//                            .foregroundColor(.white)
//                    }
//                    
//                    Slider(value: Binding(
//                        get: { Double(playerManager.state.transpose) },
//                        set: { playerManager.setTranspose(Int($0)) }
//                    ), in: -5...6, step: 1)
//                        .accentColor(.blue)
//                    
//                    Button(action: {
//                        playerManager.setTranspose(playerManager.state.transpose + 1)
//                    }) {
//                        Image(systemName: "plus.circle")
//                            .foregroundColor(.white)
//                    }
//                    
//                    Button(action: {
//                        playerManager.setTranspose(0)
//                    }) {
//                        Text("Reset")
//                            .font(.caption)
//                            .foregroundColor(.white)
//                            .padding(.horizontal, 8)
//                            .padding(.vertical, 4)
//                            .background(Color.blue)
//                            .cornerRadius(8)
//                    }
//                }
//            }
//        }
//        .padding()
//        .background(
//            RoundedRectangle(cornerRadius: 15)
//                .fill(Color.white.opacity(0.1))
//        )
//        .padding(.horizontal)
//    }
//    
//    private func formatTime(_ time: TimeInterval) -> String {
//        let minutes = Int(time) / 60
//        let seconds = Int(time) % 60
//        return String(format: "%d:%02d", minutes, seconds)
//    }
//}
//
//// MARK: - File List View
//
//struct FileListView: View {
//    @ObservedObject var fileManager: MIDIFileManager
//    @ObservedObject var playerManager: MIDIPlayerManager
//    @Environment(\.dismiss) var dismiss
//    
//    var body: some View {
//        NavigationView {
//            List {
//                ForEach(fileManager.files) { file in
//                    Button(action: {
//                        if playerManager.loadMIDIFile(file) {
//                            dismiss()
//                        }
//                    }) {
//                        HStack {
//                            Image(systemName: "music.note")
//                                .foregroundColor(.blue)
//                                .frame(width: 30)
//                            
//                            VStack(alignment: .leading) {
//                                Text(file.name)
//                                    .font(.headline)
//                                
//                                if let artist = file.artist {
//                                    Text(artist)
//                                        .font(.caption)
//                                        .foregroundColor(.secondary)
//                                }
//                            }
//                            
//                            Spacer()
//                            
//                            if playerManager.currentFile?.id == file.id {
//                                Image(systemName: "checkmark.circle.fill")
//                                    .foregroundColor(.green)
//                            }
//                        }
//                    }
//                }
//                .onDelete { indexSet in
//                    indexSet.forEach { index in
//                        fileManager.deleteFile(fileManager.files[index])
//                    }
//                }
//            }
//            .navigationTitle("MIDI Files")
//            .navigationBarItems(
//                leading: Button("Done") { dismiss() },
//                trailing: Button(action: { fileManager.loadFiles() }) {
//                    Image(systemName: "arrow.clockwise")
//                }
//            )
//        }
//    }
//}
//
//// MARK: - App Entry Point
//
//@main
//struct MIDIPlayerApp: App {
//    init() {
//        setupAudioSession()
//    }
//    
//    var body: some Scene {
//        WindowGroup {
//            MIDIPlayerView()
//        }
//    }
//    
//    private func setupAudioSession() {
//        let session = AVAudioSession.sharedInstance()
//        do {
//            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
//            try session.setActive(true)
//        } catch {
//            print("Failed to setup audio session: \(error)")
//        }
//    }
//}
