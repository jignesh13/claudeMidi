import Foundation

final class MIDITrackState: ObservableObject {
    let trackIndex: Int
    let trackName: String
    @Published var muted = false
    @Published var solo = false

    init(trackIndex: Int, trackName: String) {
        self.trackIndex = trackIndex
        self.trackName = trackName
    }
}

import Foundation

final class FluidSynthEngine {
    private var settings: OpaquePointer!
    private var synth: OpaquePointer!
    private var audioDriver: OpaquePointer!

    private var bankMSB = Array(repeating: 0, count: 16)
    private var bankLSB = Array(repeating: 0, count: 16)

    init(sampleRate: Double = 44100) {
        settings = new_fluid_settings()

        fluid_settings_setint(settings, "synth.threadsafe-api", 0)
        fluid_settings_setint(settings, "synth.midi-channels", 16)
        fluid_settings_setint(settings, "synth.drums-channel", 1)
        fluid_settings_setnum(settings, "synth.sample-rate", sampleRate)
        fluid_settings_setnum(settings, "synth.gain", 2.0)
        fluid_settings_setint(settings, "synth.polyphony", 256)
        fluid_settings_setint(settings, "synth.reverb.active", 1)
        fluid_settings_setnum(settings, "synth.reverb.room-size", 0.7)
        fluid_settings_setnum(settings, "synth.reverb.damp", 0.5)
        fluid_settings_setint(settings, "synth.chorus.active", 1)
        fluid_settings_setnum(settings, "synth.chorus.nr", 3)
        fluid_settings_setnum(settings, "synth.chorus.level", 2)
        fluid_settings_setint(settings, "synth.interpolation", 3)

        synth = new_fluid_synth(settings)
        audioDriver = new_fluid_audio_driver(settings, synth)
    }

    deinit {
        delete_fluid_audio_driver(audioDriver)
        delete_fluid_synth(synth)
        delete_fluid_settings(settings)
    }

    func loadSoundFont(_ url: URL) {
        let id = fluid_synth_sfload(synth, url.path, 1)
        print("SoundFont load result:", id)
        fluid_synth_bank_select(synth, 9, 128)
        fluid_synth_program_change(synth, 9, 0)
    }

    func send(status: UInt8, d1: UInt8, d2: UInt8) {
        let cmd = status & 0xF0
        let ch = Int32(status & 0x0F)

        switch cmd {
        case 0xB0:
            if d1 == 0 { bankMSB[Int(ch)] = Int(d2) }
            if d1 == 32 { bankLSB[Int(ch)] = Int(d2) }
            fluid_synth_cc(synth, ch, Int32(d1), Int32(d2))
        case 0xC0:
            let bank = (bankMSB[Int(ch)] << 7) | bankLSB[Int(ch)]
            fluid_synth_bank_select(synth, ch, Int32(bank))
            fluid_synth_program_change(synth, ch, Int32(d1))
        case 0x90:
            d2 == 0
                ? fluid_synth_noteoff(synth, ch, Int32(d1))
                : fluid_synth_noteon(synth, ch, Int32(d1), Int32(d2))
        case 0x80:
            fluid_synth_noteoff(synth, ch, Int32(d1))
        case 0xE0:
            let bend = Int32(d1) | (Int32(d2) << 7)
            fluid_synth_pitch_bend(synth, ch, bend)
        default:
            break
        }
    }

    func allNotesOff() {
        for ch in 0..<16 {
            fluid_synth_all_notes_off(synth, Int32(ch))
        }
    }

    func systemReset() {
        fluid_synth_system_reset(synth)
    }
}

import Foundation
import CoreMIDI
import AudioToolbox

@available(iOS 16.0, *)
final class MIDIFluidPlayer: ObservableObject {

    private var midiClient = MIDIClientRef()
    private var endpoint = MIDIEndpointRef()

    private var sequence: MusicSequence?
    private var player: MusicPlayer?
    private var timer: Timer?

    let synth = FluidSynthEngine()
    @Published var tracks: [MIDITrackState] = []
    @Published var currentTime: TimeInterval = 0
    @Published var totalDuration: TimeInterval = 0
    @Published var isPlaying = false
    @Published var tempo: Double = 120.0 // BPM
    @Published var midiFileName: String = "No MIDI file loaded"
    @Published var soundFontFileName: String = "No SoundFont loaded"

    private var trackMap: [MusicTrack: Int] = [:]
     var isSeeking = false

    init() {
        MIDIClientCreate("FluidClient" as CFString, nil, nil, &midiClient)

        MIDIDestinationCreateWithProtocol(midiClient, "FluidDest" as CFString, MIDIProtocolID._1_0, &endpoint) { [weak self] eventList, _ in
            self?.handle(eventList)
        }
    }

    func loadSoundFont(_ url: URL) {
        synth.loadSoundFont(url)
        synth.systemReset()
        soundFontFileName = url.lastPathComponent
    }

    func loadMIDI(_ url: URL) {
        NewMusicSequence(&sequence)
        MusicSequenceFileLoad(sequence!, url as CFURL, .midiType, MusicSequenceLoadFlags())
        MusicSequenceSetMIDIEndpoint(sequence!, endpoint)
        
        midiFileName = url.lastPathComponent
        
        // Extract track information
        extractTracks()
        
        // Calculate total duration
        calculateDuration()
        
        NewMusicPlayer(&player)
        MusicPlayerSetSequence(player!, sequence!)
        MusicPlayerPreroll(player!)
    }

    private func extractTracks() {
        guard let seq = sequence else { return }
        
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(seq, &trackCount)
        
        tracks.removeAll()
        trackMap.removeAll()
        
        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(seq, UInt32(i), &track)
            
            guard let track = track else { continue }
            
            let trackName = getTrackName(track: track, index: Int(i))
            let trackState = MIDITrackState(trackIndex: Int(i), trackName: trackName)
            tracks.append(trackState)
            trackMap[track] = Int(i)
        }
    }

    private func getTrackName(track: MusicTrack, index: Int) -> String {
        var iterator: MusicEventIterator?
        NewMusicEventIterator(track, &iterator)
        
        guard let iterator = iterator else { return "Track \(index + 1)" }
        defer { DisposeMusicEventIterator(iterator) }
        
        var hasEvent = DarwinBoolean(false)
        var timestamp = MusicTimeStamp()
        var eventType = MusicEventType()
        var eventData: UnsafeRawPointer?
        var eventDataSize: UInt32 = 0
        
        MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
        
        while hasEvent.boolValue {
            MusicEventIteratorGetEventInfo(iterator, &timestamp, &eventType, &eventData, &eventDataSize)
            
            if eventType == kMusicEventType_Meta {
                var metaEvent = eventData!.assumingMemoryBound(to: MIDIMetaEvent.self).pointee
                if metaEvent.metaEventType == 0x03 { // Track name
                    let nameData = Data(bytes: &metaEvent.data, count: Int(metaEvent.dataLength))
                    if let name = String(data: nameData, encoding: .utf8), !name.isEmpty {
                        return name
                    }
                }
            }
            
            MusicEventIteratorNextEvent(iterator)
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
        }
        
        return "Track \(index + 1)"
    }

    private func calculateDuration() {
        guard let seq = sequence else { return }
        
        var length: MusicTimeStamp = 0
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(seq, &trackCount)
        
        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(seq, UInt32(i), &track)
            
            if let track = track {
                var trackLength: MusicTimeStamp = 0
                var propSize: UInt32 = UInt32(MemoryLayout<MusicTimeStamp>.size)
                MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &trackLength, &propSize)
                length = max(length, trackLength)
            }
        }
        
        // Convert music time (beats) to seconds using tempo
        MusicSequenceGetSecondsForBeats(seq, length, &totalDuration)
    }

    func play() {
        guard let player = player else { return }
        MusicPlayerStart(player)
        isPlaying = true
        startTimer()
    }

    func pause() {
        guard let player = player else { return }
        MusicPlayerStop(player)
        isPlaying = false
        stopTimer()
    }

    func stop() {
        guard let player = player else { return }
        MusicPlayerStop(player)
        synth.allNotesOff()
        seek(to: 0)
        isPlaying = false
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        guard let player = player, let seq = sequence else { return }
        
        isSeeking = true
        
        // Convert seconds to beats
        var beats: MusicTimeStamp = 0
        MusicSequenceGetBeatsForSeconds(seq, time, &beats)
        MusicPlayerSetTime(player, beats)
        currentTime = time
        
        // Small delay to prevent flickering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isSeeking = false
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateCurrentTime() {
        guard let player = player, let seq = sequence, !isSeeking else { return }
        
        var time: MusicTimeStamp = 0
        MusicPlayerGetTime(player, &time)
        
        // Convert beats to seconds
        var seconds: TimeInterval = 0
        MusicSequenceGetSecondsForBeats(seq, time, &seconds)
        currentTime = seconds
        
        if time >= totalDuration {
            stop()
        }
    }

    func setTrackMute(_ trackIndex: Int, muted: Bool) {
        guard let seq = sequence, trackIndex < tracks.count else { return }
        
        var track: MusicTrack?
        MusicSequenceGetIndTrack(seq, UInt32(trackIndex), &track)
        
        if let track = track {
            var muteValue: UInt32 = muted ? 1 : 0
            MusicTrackSetProperty(track, kSequenceTrackProperty_MuteStatus, &muteValue, UInt32(MemoryLayout<UInt32>.size))
        }
    }

    func setTrackSolo(_ trackIndex: Int, solo: Bool) {
        guard let seq = sequence, trackIndex < tracks.count else { return }
        
        var track: MusicTrack?
        MusicSequenceGetIndTrack(seq, UInt32(trackIndex), &track)
        
        if let track = track {
            var soloValue: UInt32 = solo ? 1 : 0
            MusicTrackSetProperty(track, kSequenceTrackProperty_SoloStatus, &soloValue, UInt32(MemoryLayout<UInt32>.size))
        }
    }

    func setTempo(_ bpm: Double) {
        guard let player = player else { return }
        
        tempo = bpm
        let rate = bpm / 120.0 // 120 is the default tempo
        MusicPlayerSetPlayRateScalar(player, rate)
    }

    @available(iOS 16.0, *)
    private func handle(_ list: UnsafePointer<MIDIEventList>) {
        var packet = list.pointee.packet

        for _ in 0..<list.pointee.numPackets {
            let wordCount = Int(packet.wordCount)

            withUnsafePointer(to: &packet.words) {
                $0.withMemoryRebound(to: UInt32.self, capacity: wordCount) { wordsPtr in
                    for i in 0..<wordCount {
                        let word = wordsPtr[i]

                        let status = UInt8((word >> 16) & 0xFF)
                        let data1  = UInt8((word >> 8) & 0xFF)
                        let data2  = UInt8(word & 0xFF)

                        synth.send(status: status, d1: data1, d2: data2)
                    }
                }
            }

            packet = MIDIEventPacketNext(&packet).pointee
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

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @StateObject private var player = MIDIFluidPlayer()
    @State private var showSFPicker = false
    @State private var showMIDIPicker = false
    @State private var tempoValue: Double = 120.0

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {

                // File names display
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("SoundFont:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(player.soundFontFileName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    HStack {
                        Text("MIDI File:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(player.midiFileName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                Button("Load SoundFont") { showSFPicker = true }
                Button("Load MIDI File") { showMIDIPicker = true }

                HStack(spacing: 12) {
                    Button(player.isPlaying ? "Pause" : "Play") {
                        if player.isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                    }
                    .frame(width: 80)
                    
                    Button("Stop") {
                        player.stop()
                    }
                    .frame(width: 80)
                }

                // Playback controls
                VStack(spacing: 8) {
                    HStack {
                        Text(formatTime(player.currentTime))
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text(formatTime(player.totalDuration))
                            .font(.system(.caption, design: .monospaced))
                    }
                    
                    GeometryReader { geometry in
                        Slider(
                            value: Binding(
                                get: { player.currentTime },
                                set: { newValue in
                                    player.seek(to: newValue)
                                }
                            ),
                            in: 0...max(player.totalDuration, 0.1),
                            onEditingChanged: { editing in
                                if editing {
                                    player.isSeeking = true
                                } else {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        player.isSeeking = false
                                    }
                                }
                            }
                        )
                    }
                    .frame(height: 40)
                }
                .padding(.horizontal)

                // Tempo control
                VStack(spacing: 8) {
                    HStack {
                        Text("Tempo: \(Int(tempoValue)) BPM")
                            .font(.caption)
                        Spacer()
                        Button("Reset") {
                            tempoValue = 120.0
                            player.setTempo(tempoValue)
                        }
                        .font(.caption)
                    }
                    
                    Slider(value: $tempoValue, in: 40...240, step: 1) { _ in
                        player.setTempo(tempoValue)
                    }
                }
                .padding(.horizontal)

                // Track list with mute/solo
                List {
                    ForEach(player.tracks, id: \.trackIndex) { track in
                        HStack {
                            Text(track.trackName)
                                .lineLimit(1)
                            Spacer()
                            Toggle("Mute", isOn: Binding(
                                get: { track.muted },
                                set: { newValue in
                                    track.muted = newValue
                                    player.setTrackMute(track.trackIndex, muted: newValue)
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                            .tint(track.muted ? .red : .gray)
                            
                            Toggle("Solo", isOn: Binding(
                                get: { track.solo },
                                set: { newValue in
                                    track.solo = newValue
                                    player.setTrackSolo(track.trackIndex, solo: newValue)
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                            .tint(track.solo ? .green : .gray)
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Fluid MIDI Player")
        }
        .sheet(isPresented: $showSFPicker) {
            DocumentPicker(types: [.data]) { url in
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

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
