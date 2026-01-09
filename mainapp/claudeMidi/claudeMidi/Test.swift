//import SwiftUI
//import AVFoundation
//import CoreMIDI
//import Combine
//
//// MARK: - Models
//struct MIDIFile {
//    let url: URL
//    let name: String
//    let tracks: [MIDITrackData]
//    let format: UInt16
//    let ticksPerQuarterNote: UInt16
//    let tempo: Double
//    let duration: TimeInterval
//}
//
//struct MIDITrackData: Identifiable {
//    let id: Int
//    let name: String
//    let events: [MIDIEvent]
//    var isMuted: Bool = false
//    var isSolo: Bool = false
//    var volume: Float = 1.0
//}
//
//struct MIDIEvent {
//    let timestamp: TimeInterval
//    let type: MIDIEventType
//}
//
//enum MIDIEventType {
//    case noteOn(note: UInt8, velocity: UInt8, channel: UInt8)
//    case noteOff(note: UInt8, channel: UInt8)
//    case programChange(program: UInt8, channel: UInt8)
//    case controlChange(controller: UInt8, value: UInt8, channel: UInt8)
//    case pitchBend(value: UInt16, channel: UInt8)
//}
//
//struct ActiveNote: Identifiable {
//    let id = UUID()
//    let note: UInt8
//    let velocity: UInt8
//    let channel: UInt8
//    let startTime: TimeInterval
//}
//
//// MARK: - MIDI Parser Service
//class MIDIParserService {
//    
//    func parseMIDIFile(url: URL) throws -> MIDIFile {
//        let data = try Data(contentsOf: url)
//        var offset = 0
//        
//        // Parse header chunk
//        guard String(data: data[0..<4], encoding: .ascii) == "MThd" else {
//            throw MIDIError.invalidFormat
//        }
//        
//        offset += 4
//        let headerLength = data.readUInt32(at: &offset)
//        let format = data.readUInt16(at: &offset)
//        let trackCount = data.readUInt16(at: &offset)
//        let division = data.readUInt16(at: &offset)
//        
//        var tracks: [MIDITrackData] = []
//        var tempo: Double = 500000 // Default 120 BPM
//        
//        // Parse tracks
//        for trackIndex in 0..<trackCount {
//            guard offset < data.count else { break }
//            
//            let trackData = try parseTrack(data: data, offset: &offset, trackIndex: Int(trackIndex), division: division, tempo: &tempo)
//            tracks.append(trackData)
//        }
//        
//        let duration = calculateDuration(tracks: tracks)
//        
//        return MIDIFile(
//            url: url,
//            name: url.deletingPathExtension().lastPathComponent,
//            tracks: tracks,
//            format: format,
//            ticksPerQuarterNote: division,
//            tempo: 60000000.0 / tempo,
//            duration: duration
//        )
//    }
//    
//    private func parseTrack(data: Data, offset: inout Int, trackIndex: Int, division: UInt16, tempo: inout Double) throws -> MIDITrackData {
//        guard String(data: data[offset..<offset+4], encoding: .ascii) == "MTrk" else {
//            throw MIDIError.invalidFormat
//        }
//        
//        offset += 4
//        let trackLength = data.readUInt32(at: &offset)
//        let trackEnd = offset + Int(trackLength)
//        
//        var events: [MIDIEvent] = []
//        var currentTime: UInt64 = 0
//        var runningStatus: UInt8 = 0
//        var trackName = "Track \(trackIndex + 1)"
//        
//        while offset < trackEnd {
//            let deltaTime = data.readVariableLength(at: &offset)
//            currentTime += UInt64(deltaTime)
//            
//            var status = data[offset]
//            
//            if status < 0x80 {
//                status = runningStatus
//            } else {
//                offset += 1
//                runningStatus = status
//            }
//            
//            let messageType = status & 0xF0
//            let channel = status & 0x0F
//            
//            let timestamp = ticksToSeconds(ticks: currentTime, division: division, tempo: tempo)
//            
//            switch messageType {
//            case 0x90: // Note On
//                let note = data[offset]
//                let velocity = data[offset + 1]
//                offset += 2
//                
//                if velocity > 0 {
//                    events.append(MIDIEvent(timestamp: timestamp, type: .noteOn(note: note, velocity: velocity, channel: channel)))
//                } else {
//                    events.append(MIDIEvent(timestamp: timestamp, type: .noteOff(note: note, channel: channel)))
//                }
//                
//            case 0x80: // Note Off
//                let note = data[offset]
//                offset += 2
//                events.append(MIDIEvent(timestamp: timestamp, type: .noteOff(note: note, channel: channel)))
//                
//            case 0xB0: // Control Change
//                let controller = data[offset]
//                let value = data[offset + 1]
//                offset += 2
//                events.append(MIDIEvent(timestamp: timestamp, type: .controlChange(controller: controller, value: value, channel: channel)))
//                
//            case 0xC0: // Program Change
//                let program = data[offset]
//                offset += 1
//                events.append(MIDIEvent(timestamp: timestamp, type: .programChange(program: program, channel: channel)))
//                
//            case 0xE0: // Pitch Bend
//                let lsb = data[offset]
//                let msb = data[offset + 1]
//                offset += 2
//                let value = UInt16(msb) << 7 | UInt16(lsb)
//                events.append(MIDIEvent(timestamp: timestamp, type: .pitchBend(value: value, channel: channel)))
//                
//            case 0xF0: // System/Meta events
//                if status == 0xFF {
//                    let metaType = data[offset]
//                    offset += 1
//                    let length = data.readVariableLength(at: &offset)
//                    
//                    if metaType == 0x03 && length > 0 { // Track name
//                        trackName = String(data: data[offset..<offset+Int(length)], encoding: .utf8) ?? trackName
//                    } else if metaType == 0x51 && length == 3 { // Tempo
//                        tempo = Double(data[offset]) * 65536.0 + Double(data[offset + 1]) * 256.0 + Double(data[offset + 2])
//                    }
//                    
//                    offset += Int(length)
//                } else {
//                    // Skip other system messages
//                    offset += 1
//                }
//                
//            default:
//                offset += 1
//            }
//        }
//        
//        return MIDITrackData(id: trackIndex, name: trackName, events: events)
//    }
//    
//    private func ticksToSeconds(ticks: UInt64, division: UInt16, tempo: Double) -> TimeInterval {
//        return Double(ticks) * (tempo / 1000000.0) / Double(division)
//    }
//    
//    private func calculateDuration(tracks: [MIDITrackData]) -> TimeInterval {
//        return tracks.flatMap { $0.events }.map { $0.timestamp }.max() ?? 0
//    }
//}
//
//enum MIDIError: Error {
//    case invalidFormat
//    case fileNotFound
//}
//
//// MARK: - Data Extensions
//extension Data {
//    func readUInt32(at offset: inout Int) -> UInt32 {
//        let value = UInt32(self[offset]) << 24 | UInt32(self[offset+1]) << 16 | UInt32(self[offset+2]) << 8 | UInt32(self[offset+3])
//        offset += 4
//        return value
//    }
//    
//    func readUInt16(at offset: inout Int) -> UInt16 {
//        let value = UInt16(self[offset]) << 8 | UInt16(self[offset+1])
//        offset += 2
//        return value
//    }
//    
//    func readVariableLength(at offset: inout Int) -> UInt32 {
//        var value: UInt32 = 0
//        var byte: UInt8
//        
//        repeat {
//            byte = self[offset]
//            offset += 1
//            value = (value << 7) | UInt32(byte & 0x7F)
//        } while (byte & 0x80) != 0
//        
//        return value
//    }
//}
//
//// MARK: - Audio Engine Service
//class AudioEngineService: ObservableObject {
//    private let engine = AVAudioEngine()
//    private let sampler = AVAudioUnitSampler()
//    private var sequencer: AVAudioSequencer?
//    
//    @Published var isPlaying = false
//    @Published var currentTime: TimeInterval = 0
//    
//    private var displayLink: CADisplayLink?
//    
//    init() {
//        setupAudioEngine()
//    }
//    
//    private func setupAudioEngine() {
//        engine.attach(sampler)
//        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
//        
//        do {
//            try engine.start()
//            loadSoundFont()
//        } catch {
//            print("Audio engine failed to start: \(error)")
//        }
//    }
//    
//    private func loadSoundFont() {
//        guard let soundFontURL = Bundle.main.url(forResource: "GeneralUser GS", withExtension: "sf2") else {
//            // Use built-in sounds if no soundfont
//            try? sampler.loadSoundBankInstrument(at: URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"),
//                                                  program: 0,
//                                                  bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
//                                                  bankLSB: UInt8(kAUSampler_DefaultBankLSB))
//            return
//        }
//        
//        try? sampler.loadSoundBankInstrument(at: soundFontURL, program: 0, bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
//    }
//    
//    func loadMIDIFile(midiFile: MIDIFile) {
//        sequencer = AVAudioSequencer(audioEngine: engine)
//        
//        do {
//            try sequencer?.load(from: midiFile.url, options: [])
//            sequencer?.prepareToPlay()
//            
//            for track in sequencer?.tracks ?? [] {
//                track.destinationAudioUnit = sampler
//            }
//        } catch {
//            print("Failed to load MIDI file: \(error)")
//        }
//    }
//    
//    func play() {
//        guard let sequencer = sequencer else { return }
//        
//        do {
//            try sequencer.start()
//            isPlaying = true
//            startDisplayLink()
//        } catch {
//            print("Failed to start playback: \(error)")
//        }
//    }
//    
//    func pause() {
//        sequencer?.stop()
//        isPlaying = false
//        stopDisplayLink()
//    }
//    
//    func stop() {
//        sequencer?.stop()
//        sequencer?.currentPositionInSeconds = 0
//        currentTime = 0
//        isPlaying = false
//        stopDisplayLink()
//    }
//    
//    func seek(to time: TimeInterval) {
//        sequencer?.currentPositionInSeconds = time
//        currentTime = time
//    }
//    
//    func setTrackMute(trackIndex: Int, muted: Bool) {
//        guard let track = sequencer?.tracks[safe: trackIndex] else { return }
//        track.isMuted = muted
//    }
//    
//    func setTrackSolo(trackIndex: Int, solo: Bool) {
//        guard let tracks = sequencer?.tracks else { return }
//        
//        if solo {
//            for (index, track) in tracks.enumerated() {
//                track.isMuted = index != trackIndex
//            }
//        } else {
//            for track in tracks {
//                track.isMuted = false
//            }
//        }
//    }
//    
//    func playNote(note: UInt8, velocity: UInt8, channel: UInt8) {
//        sampler.startNote(note, withVelocity: velocity, onChannel: channel)
//    }
//    
//    func stopNote(note: UInt8, channel: UInt8) {
//        sampler.stopNote(note, onChannel: channel)
//    }
//    
//    private func startDisplayLink() {
//        displayLink = CADisplayLink(target: self, selector: #selector(updatePlaybackPosition))
//        displayLink?.add(to: .main, forMode: .common)
//    }
//    
//    private func stopDisplayLink() {
//        displayLink?.invalidate()
//        displayLink = nil
//    }
//    
//    @objc private func updatePlaybackPosition() {
//        currentTime = sequencer?.currentPositionInSeconds ?? 0
//    }
//    
//    deinit {
//        stopDisplayLink()
//        engine.stop()
//    }
//}
//
//extension Array {
//    subscript(safe index: Int) -> Element? {
//        return indices.contains(index) ? self[index] : nil
//    }
//}
//
//// MARK: - ViewModel
//class MIDIPlayerViewModel: ObservableObject {
//    @Published var midiFile: MIDIFile?
//    @Published var tracks: [MIDITrackData] = []
//    @Published var currentTime: TimeInterval = 0
//    @Published var duration: TimeInterval = 0
//    @Published var isPlaying = false
//    @Published var activeNotes: [ActiveNote] = []
//    
//    private let parserService = MIDIParserService()
//    private let audioService = AudioEngineService()
//    private var cancellables = Set<AnyCancellable>()
//    private var eventTimer: Timer?
//    
//    init() {
//        audioService.$isPlaying
//            .assign(to: &$isPlaying)
//        
//        audioService.$currentTime
//            .sink { [weak self] time in
//                self?.currentTime = time
//                self?.updateActiveNotes(at: time)
//            }
//            .store(in: &cancellables)
//    }
//    
//    func loadMIDIFile(url: URL) {
//        do {
//            let parsed = try parserService.parseMIDIFile(url: url)
//            self.midiFile = parsed
//            self.tracks = parsed.tracks
//            self.duration = parsed.duration
//            
//            audioService.loadMIDIFile(midiFile: parsed)
//        } catch {
//            print("Failed to parse MIDI file: \(error)")
//        }
//    }
//    
//    func play() {
//        audioService.play()
//    }
//    
//    func pause() {
//        audioService.pause()
//    }
//    
//    func stop() {
//        audioService.stop()
//        activeNotes.removeAll()
//    }
//    
//    func seek(to time: TimeInterval) {
//        audioService.seek(to: time)
//    }
//    
//    func toggleMute(trackIndex: Int) {
//        tracks[trackIndex].isMuted.toggle()
//        audioService.setTrackMute(trackIndex: trackIndex, muted: tracks[trackIndex].isMuted)
//    }
//    
//    func toggleSolo(trackIndex: Int) {
//        let wasSolo = tracks[trackIndex].isSolo
//        
//        for i in 0..<tracks.count {
//            tracks[i].isSolo = false
//            tracks[i].isMuted = false
//        }
//        
//        if !wasSolo {
//            tracks[trackIndex].isSolo = true
//            audioService.setTrackSolo(trackIndex: trackIndex, solo: true)
//        } else {
//            audioService.setTrackSolo(trackIndex: trackIndex, solo: false)
//        }
//    }
//    
//    func setTrackVolume(trackIndex: Int, volume: Float) {
//        tracks[trackIndex].volume = volume
//    }
//    
//    private func updateActiveNotes(at time: TimeInterval) {
//        guard let file = midiFile else { return }
//        
//        var newActiveNotes: [ActiveNote] = []
//        
//        for track in file.tracks where !track.isMuted {
//            var noteStates: [UInt8: (velocity: UInt8, channel: UInt8, startTime: TimeInterval)] = [:]
//            
//            for event in track.events where event.timestamp <= time {
//                switch event.type {
//                case .noteOn(let note, let velocity, let channel):
//                    noteStates[note] = (velocity, channel, event.timestamp)
//                case .noteOff(let note, _):
//                    noteStates.removeValue(forKey: note)
//                default:
//                    break
//                }
//            }
//            
//            for (note, state) in noteStates {
//                newActiveNotes.append(ActiveNote(note: note, velocity: state.velocity, channel: state.channel, startTime: state.startTime))
//            }
//        }
//        
//        activeNotes = newActiveNotes
//    }
//}
//
//// MARK: - Views
//
//// Main Content View
//struct ContentView: View {
//    @StateObject private var viewModel = MIDIPlayerViewModel()
//    @State private var showFilePicker = false
//    
//    var body: some View {
//        NavigationView {
//            GeometryReader { geometry in
//                if geometry.size.width > 600 {
//                    // iPad Layout
//                    HStack(spacing: 0) {
//                        // Left panel
//                        VStack {
//                            PlayerControlsView(viewModel: viewModel)
//                            TrackListView(viewModel: viewModel)
//                        }
//                        .frame(width: 350)
//                        
//                        Divider()
//                        
//                        // Right panel
//                        VStack {
//                            PianoRollView(viewModel: viewModel)
//                            KeyboardVisualizationView(viewModel: viewModel)
//                        }
//                    }
//                } else {
//                    // iPhone Layout
//                    VStack(spacing: 0) {
//                        PlayerControlsView(viewModel: viewModel)
//                        
//                        TabView {
//                            TrackListView(viewModel: viewModel)
//                                .tabItem {
//                                    Label("Tracks", systemImage: "music.note.list")
//                                }
//                            
//                            PianoRollView(viewModel: viewModel)
//                                .tabItem {
//                                    Label("Piano Roll", systemImage: "piano")
//                                }
//                            
//                            KeyboardVisualizationView(viewModel: viewModel)
//                                .tabItem {
//                                    Label("Keyboard", systemImage: "pianokeys")
//                                }
//                        }
//                    }
//                }
//            }
//            .navigationTitle(viewModel.midiFile?.name ?? "MIDI Player")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button(action: { showFilePicker = true }) {
//                        Image(systemName: "folder.badge.plus")
//                    }
//                }
//            }
//            .sheet(isPresented: $showFilePicker) {
//                DocumentPicker { url in
//                    viewModel.loadMIDIFile(url: url)
//                }
//            }
//        }
//        .navigationViewStyle(StackNavigationViewStyle())
//    }
//}
//
//// Player Controls
//struct PlayerControlsView: View {
//    @ObservedObject var viewModel: MIDIPlayerViewModel
//    
//    var body: some View {
//        VStack(spacing: 16) {
//            // Progress Bar
//            VStack(spacing: 8) {
//                Slider(value: Binding(
//                    get: { viewModel.currentTime },
//                    set: { viewModel.seek(to: $0) }
//                ), in: 0...max(viewModel.duration, 1))
//                
//                HStack {
//                    Text(formatTime(viewModel.currentTime))
//                    Spacer()
//                    Text(formatTime(viewModel.duration))
//                }
//                .font(.caption)
//                .foregroundColor(.secondary)
//            }
//            .padding(.horizontal)
//            
//            // Transport Controls
//            HStack(spacing: 40) {
//                Button(action: viewModel.stop) {
//                    Image(systemName: "stop.fill")
//                        .font(.title2)
//                        .foregroundColor(.red)
//                        .frame(width: 44, height: 44)
//                }
//                
//                Button(action: {
//                    if viewModel.isPlaying {
//                        viewModel.pause()
//                    } else {
//                        viewModel.play()
//                    }
//                }) {
//                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
//                        .font(.title)
//                        .foregroundColor(.blue)
//                        .frame(width: 44, height: 44)
//                }
//            }
//            .padding(.vertical)
//        }
//        .padding()
//        .background(Color(.systemBackground))
//    }
//    
//    private func formatTime(_ time: TimeInterval) -> String {
//        let minutes = Int(time) / 60
//        let seconds = Int(time) % 60
//        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
//        return String(format: "%d:%02d.%02d", minutes, seconds, milliseconds)
//    }
//}
//
//// Track List
//struct TrackListView: View {
//    @ObservedObject var viewModel: MIDIPlayerViewModel
//    
//    var body: some View {
//        ScrollView {
//            LazyVStack(spacing: 8) {
//                ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in
//                    TrackRowView(track: track, trackIndex: index, viewModel: viewModel)
//                }
//            }
//            .padding()
//        }
//    }
//}
//
//struct TrackRowView: View {
//    let track: MIDITrackData
//    let trackIndex: Int
//    @ObservedObject var viewModel: MIDIPlayerViewModel
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 8) {
//            HStack {
//                Text(track.name)
//                    .font(.headline)
//                    .lineLimit(1)
//                
//                Spacer()
//                
//                // Mute Button
//                Button(action: {
//                    viewModel.toggleMute(trackIndex: trackIndex)
//                }) {
//                    Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
//                        .foregroundColor(track.isMuted ? .red : .green)
//                        .frame(width: 32, height: 32)
//                }
//                .buttonStyle(BorderlessButtonStyle())
//                
//                // Solo Button
//                Button(action: {
//                    viewModel.toggleSolo(trackIndex: trackIndex)
//                }) {
//                    Text("S")
//                        .font(.system(size: 14, weight: .bold))
//                        .frame(width: 32, height: 32)
//                        .background(track.isSolo ? Color.yellow : Color.gray.opacity(0.3))
//                        .foregroundColor(track.isSolo ? .black : .white)
//                        .cornerRadius(6)
//                }
//                .buttonStyle(BorderlessButtonStyle())
//            }
//            
//            // Volume Slider
//            HStack {
//                Image(systemName: "speaker.fill")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                
//                Slider(value: Binding(
//                    get: { track.volume },
//                    set: { viewModel.setTrackVolume(trackIndex: trackIndex, volume: $0) }
//                ), in: 0...1)
//                
//                Text("\(Int(track.volume * 100))%")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                    .frame(width: 40)
//            }
//        }
//        .padding()
//        .background(Color(.secondarySystemBackground))
//        .cornerRadius(10)
//    }
//}
//
//// Piano Roll Visualization
//struct PianoRollView: View {
//    @ObservedObject var viewModel: MIDIPlayerViewModel
//    
//    var body: some View {
//        GeometryReader { geometry in
//            ScrollView([.horizontal, .vertical]) {
//                ZStack(alignment: .topLeading) {
//                    // Grid background
//                    PianoRollGridView(duration: viewModel.duration, size: geometry.size)
//                    
//                    // Notes
//                    ForEach(viewModel.tracks.indices, id: \.self) { trackIndex in
//                        PianoRollNotesView(
//                            track: viewModel.tracks[trackIndex],
//                            trackIndex: trackIndex,
//                            duration: viewModel.duration
//                        )
//                    }
//                    
//                    // Playhead
//                    PlayheadView(currentTime: viewModel.currentTime, duration: viewModel.duration, height: geometry.size.height)
//                }
//                .frame(width: max(geometry.size.width, viewModel.duration * 100), height: 128 * 12)
//            }
//        }
//    }
//}
//
//struct PianoRollGridView: View {
//    let duration: TimeInterval
//    let size: CGSize
//    
//    var body: some View {
//        Canvas { context, size in
//            let noteHeight: CGFloat = 12
//            let pixelsPerSecond: CGFloat = 100
//            
//            // Draw horizontal lines (notes)
//            for i in 0...127 {
//                let y = CGFloat(127 - i) * noteHeight
//                context.stroke(
//                    Path { path in
//                        path.move(to: CGPoint(x: 0, y: y))
//                        path.addLine(to: CGPoint(x: duration * pixelsPerSecond, y: y))
//                    },
//                    with: .color(i % 12 == 0 ? .gray.opacity(0.3) : .gray.opacity(0.1)),
//                    lineWidth: i % 12 == 0 ? 2 : 1
//                )
//            }
//            
//            // Draw vertical lines (time)
//            let beatInterval: TimeInterval = 0.5
//            var time: TimeInterval = 0
//            while time <= duration {
//                let x = time * pixelsPerSecond
//                context.stroke(
//                    Path { path in
//                        path.move(to: CGPoint(x: x, y: 0))
//                        path.addLine(to: CGPoint(x: x, y: 128 * noteHeight))
//                    },
//                    with: .color(.gray.opacity(0.2)),
//                    lineWidth: 1
//                )
//                time += beatInterval
//            }
//        }
//    }
//}
//
//struct PianoRollNotesView: View {
//    let track: MIDITrackData
//    let trackIndex: Int
//    let duration: TimeInterval
//    
//    var body: some View {
//        Canvas { context, size in
//            let noteHeight: CGFloat = 12
//            let pixelsPerSecond: CGFloat = 100
//            
//            var activeNotes: [UInt8: (startTime: TimeInterval, velocity: UInt8)] = [:]
//            
//            for event in track.events {
//                switch event.type {
//                case .noteOn(let note, let velocity, _):
//                    activeNotes[note] = (event.timestamp, velocity)
//                    
//                case .noteOff(let note, _):
//                    if let (startTime, velocity) = activeNotes[note] {
//                        let x = startTime * pixelsPerSecond
//                        let width = (event.timestamp - startTime) * pixelsPerSecond
//                        let y = CGFloat(127 - Int(note)) * noteHeight
//                        
//                        let opacity = Double(velocity) / 127.0
//                        let hue = Double(trackIndex) / 16.0
//                        
//                        context.fill(
//                            Path(CGRect(x: x, y: y, width: max(width, 2), height: noteHeight - 1)),
//                            with: .color(Color(hue: hue, saturation: 0.8, brightness: 0.9, opacity: opacity))
//                        )
//                        
//                        activeNotes.removeValue(forKey: note)
//                    }
//                    
//                default:
//                    break
//                }
//            }
//        }
//    }
//}
//
//struct PlayheadView: View {
//    let currentTime: TimeInterval
//    let duration: TimeInterval
//    let height: CGFloat
//    
//    var body: some View {
//        let pixelsPerSecond: CGFloat = 100
//        let x = currentTime * pixelsPerSecond
//        
//        Rectangle()
//            .fill(Color.red)
//            .frame(width: 2, height: height)
//            .offset(x: x)
//    }
//}
//
//// Keyboard Visualization
//struct KeyboardVisualizationView: View {
//    @ObservedObject var viewModel: MIDIPlayerViewModel
//    
//    private let whiteKeyWidth: CGFloat = 40
//    private let blackKeyWidth: CGFloat = 24
//    private let whiteKeyHeight: CGFloat = 120
//    private let blackKeyHeight: CGFloat = 80
//    
//    var body: some View {
//        GeometryReader { geometry in
//            ScrollView(.horizontal, showsIndicators: false) {
//                ZStack(alignment: .topLeading) {
//                    // White keys
//                    HStack(spacing: 0) {
//                        ForEach(21...108, id: \.self) { noteNumber in
//                            if isWhiteKey(noteNumber) {
//                                WhiteKeyView(
//                                    noteNumber: UInt8(noteNumber),
//                                    isActive: isNoteActive(UInt8(noteNumber))
//                                )
//                                .frame(width: whiteKeyWidth, height: whiteKeyHeight)
//                            }
//                        }
//                    }
//                    
//                    // Black keys
//                    HStack(spacing: 0) {
//                        ForEach(21...108, id: \.self) { noteNumber in
//                            if isBlackKey(noteNumber) {
//                                BlackKeyView(
//                                    noteNumber: UInt8(noteNumber),
//                                    isActive: isNoteActive(UInt8(noteNumber))
//                                )
//                                .frame(width: blackKeyWidth, height: blackKeyHeight)
//                                .offset(x: getBlackKeyOffset(noteNumber))
//                            }
//                        }
//                    }
//                }
//                .padding()
//            }
//        }
//        .background(Color(.systemGray6))
//    }
//    
//    private func isWhiteKey(_ note: Int) -> Bool {
//        let pitchClass = note % 12
//        return [0, 2, 4, 5, 7, 9, 11].contains(pitchClass)
//    }
//    
//    private func isBlackKey(_ note: Int) -> Bool {
//        let pitchClass = note % 12
//        return [1, 3, 6, 8, 10].contains(pitchClass)
//    }
//    
//    private func isNoteActive(_ note: UInt8) -> Bool {
//        return viewModel.activeNotes.contains { $0.note == note }
//    }
//    
//    private func getBlackKeyOffset(_ note: Int) -> CGFloat {
//        let octaveStart = (note / 12) * 12
//        let position = note - octaveStart
//        let octaveNumber = note / 12 - 1
//        
//        let whiteKeysPerOctave: CGFloat = 7
//        let octaveWidth = whiteKeysPerOctave * whiteKeyWidth
//        
//        let baseOffset = CGFloat(octaveNumber) * octaveWidth
//        
//        switch position {
//        case 1: return baseOffset + whiteKeyWidth - blackKeyWidth / 2
//        case 3: return baseOffset + whiteKeyWidth * 2 - blackKeyWidth / 2
//        case 6: return baseOffset + whiteKeyWidth * 4 - blackKeyWidth / 2
//        case 8: return baseOffset + whiteKeyWidth * 5 - blackKeyWidth / 2
//        case 10: return baseOffset + whiteKeyWidth * 6 - blackKeyWidth / 2
//        default: return 0
//        }
//    }
//}
//
//struct WhiteKeyView: View {
//    let noteNumber: UInt8
//    let isActive: Bool
//    
//    var body: some View {
//        Rectangle()
//            .fill(isActive ? Color.blue : Color.white)
//            .overlay(
//                Rectangle()
//                    .stroke(Color.black, lineWidth: 1)
//            )
//            .animation(.easeInOut(duration: 0.1), value: isActive)
//    }
//}
//
//struct BlackKeyView: View {
//    let noteNumber: UInt8
//    let isActive: Bool
//    
//    var body: some View {
//        Rectangle()
//            .fill(isActive ? Color.blue : Color.black)
//            .cornerRadius(4)
//            .animation(.easeInOut(duration: 0.1), value: isActive)
//    }
//}
//
//// MARK: - Document Picker
//struct DocumentPicker: UIViewControllerRepresentable {
//    let onPick: (URL) -> Void
//    
//    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
//        let types = ["public.midi-audio", "public.audio"]
//        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types.compactMap { UTType($0) })
//        picker.allowsMultipleSelection = false
//        picker.delegate = context.coordinator
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
//            _ = url.startAccessingSecurityScopedResource()
//            onPick(url)
//            url.stopAccessingSecurityScopedResource()
//        }
//    }
//}
//
