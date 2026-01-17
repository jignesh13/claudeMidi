import Foundation
import AVFAudio

final class MIDIChannelState: ObservableObject, Identifiable {
    let id = UUID()
    let channel: Int            // 0–15
    let name: String            // "Ch 10 – Drums"
    
    @Published var muted = false
    @Published var solo = false
    
    init(channel: Int, name: String) {
        self.channel = channel
        self.name = name
    }
}


import Foundation

final class FluidSynthEngine {
    
    private var settings: OpaquePointer!
    private var synth: OpaquePointer!
    private var audioDriver: OpaquePointer!
    
    // Bank + program state
    private var bankMSB = Array(repeating: 0, count: 16)
    private var bankLSB = Array(repeating: 0, count: 16)
    private var program = Array(repeating: 0, count: 16)
    
    // Controller state
    private var expression = Array(repeating: 127, count: 16)
    private var sustain = Array(repeating: false, count: 16)
    
    // RPN state (for pitch bend range)
    private var rpnMSB = Array(repeating: 127, count: 16)
    private var rpnLSB = Array(repeating: 127, count: 16)
    private var pitchBendRange = Array(repeating: 2, count: 16) // semitones
    
    init(sampleRate: Double = 44100) {
        settings = new_fluid_settings()
        
        fluid_settings_setstr(settings, "audio.driver", "coreaudio")
        fluid_settings_setint(settings, "synth.threadsafe-api", 0)
        fluid_settings_setint(settings, "synth.midi-channels", 16)
        fluid_settings_setnum(settings, "synth.sample-rate", sampleRate)
        fluid_settings_setnum(settings, "synth.gain", 1.0)
        fluid_settings_setint(settings, "synth.polyphony", 256)
        
        fluid_settings_setint(settings, "synth.reverb.active", 1)
        fluid_settings_setnum(settings, "synth.reverb.room-size", 0.7)
        fluid_settings_setnum(settings, "synth.reverb.damp", 0.5)
        fluid_settings_setnum(settings, "synth.reverb.level", 0.3)
        
        fluid_settings_setint(settings, "synth.chorus.active", 1)
        fluid_settings_setnum(settings, "synth.chorus.level", 2.0)
        fluid_settings_setnum(settings, "synth.chorus.depth", 6.0)
        
        synth = new_fluid_synth(settings)
        audioDriver = new_fluid_audio_driver(settings, synth)
    }
    
    deinit {
        delete_fluid_audio_driver(audioDriver)
        delete_fluid_synth(synth)
        delete_fluid_settings(settings)
    }
    
    func loadSoundFont(_ url: URL) {
        fluid_synth_sfload(synth, url.path, 1)
        
        for ch in 0..<16 {
            bankMSB[ch] = 0
            bankLSB[ch] = 0
            program[ch] = 0
            expression[ch] = 127
            sustain[ch] = false
            pitchBendRange[ch] = 2
        }
        
        // GM drum channel
        fluid_synth_bank_select(synth, 9, 128)
        fluid_synth_program_change(synth, 9, 0)
    }
    
    // ===============================
    // MARK: MIDI EVENT HANDLER
    // ===============================
    func send(status: UInt8, d1: UInt8, d2: UInt8) {
        
        let cmd = status & 0xF0
        let ch = Int(status & 0x0F)
        
        switch cmd {
            
        case 0x80: // Note Off
            fluid_synth_noteoff(synth, Int32(ch), Int32(d1))
            
        case 0x90: // Note On
            d2 == 0
            ? fluid_synth_noteoff(synth, Int32(ch), Int32(d1))
            : fluid_synth_noteon(synth, Int32(ch), Int32(d1), Int32(d2))
            
        case 0xB0: // Control Change
            handleCC(ch: ch, cc: Int(d1), value: Int(d2))
            
        case 0xC0: // Program Change
            program[ch] = Int(d1)
            applyBankAndProgram(ch)
            
        case 0xE0: // Pitch Bend
            let bend = (Int32(d2) << 7 | Int32(d1)) - 8192
            fluid_synth_pitch_bend(synth, Int32(ch), bend)
            
        default:
            break
        }
    }
    
    // ===============================
    // MARK: CC / RPN HANDLING
    // ===============================
    private func handleCC(ch: Int, cc: Int, value: Int) {
        
        switch cc {
            
        case 0: bankMSB[ch] = value; applyBankAndProgram(ch)
        case 32: bankLSB[ch] = value; applyBankAndProgram(ch)
            
        case 7, 10, 11:
            fluid_synth_cc(synth, Int32(ch), Int32(cc), Int32(value))
            if cc == 11 { expression[ch] = value }
            
        case 64: // Sustain
            sustain[ch] = value >= 64
            fluid_synth_cc(synth, Int32(ch), 64, Int32(value))
            
        case 101: rpnMSB[ch] = value
        case 100: rpnLSB[ch] = value
            
        case 6: // Data Entry MSB
            if rpnMSB[ch] == 0 && rpnLSB[ch] == 0 {
                pitchBendRange[ch] = value
                fluid_synth_pitch_wheel_sens(
                    synth,
                    Int32(ch),
                    Int32(value)
                )
            }
            
        case 121: // Reset All Controllers
            fluid_synth_cc(synth, Int32(ch), 121, 0)
            expression[ch] = 127
            sustain[ch] = false
            
        default:
            fluid_synth_cc(synth, Int32(ch), Int32(cc), Int32(value))
        }
    }
    
    // ===============================
    // MARK: BANK + PROGRAM APPLY
    // ===============================
    private func applyBankAndProgram(_ ch: Int) {
        let bank: Int32 = (ch == 9)
        ? 128
        : Int32((bankMSB[ch] << 7) | bankLSB[ch])
        fluid_synth_bank_select(synth, Int32(ch), bank)
        fluid_synth_program_change(synth, Int32(ch), Int32(program[ch]))
    }
    
    func allNotesOff() {
        for ch in 0..<16 {
            fluid_synth_all_notes_off(synth, Int32(ch))
        }
    }
    
    
    func allNotesOff(channel: Int) {
        fluid_synth_all_notes_off(synth, Int32(channel))
        fluid_synth_cc(synth, Int32(channel), 64, 0) // release sustain
    }
    
    func restoreChannelState(_ ch: Int) {
        let bank: Int32 = (ch == 9)
            ? 128
            : Int32((bankMSB[ch] << 7) | bankLSB[ch])

        fluid_synth_bank_select(synth, Int32(ch), bank)
        fluid_synth_program_change(synth, Int32(ch), Int32(program[ch]))

        // Restore controllers
        fluid_synth_cc(synth, Int32(ch), 11, Int32(expression[ch])) // Expression
        fluid_synth_cc(synth, Int32(ch), 64, sustain[ch] ? 127 : 0) // Sustain

        // Restore pitch bend range
        fluid_synth_pitch_wheel_sens(
            synth,
            Int32(ch),
            Int32(pitchBendRange[ch])
        )
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
    @Published var channels: [MIDIChannelState] = []
    private var usedChannels = Set<Int>()
    private var mutedChannels = Set<Int>()
    private var soloChannels = Set<Int>()
    
    let synth = FluidSynthEngine()
    @Published var currentTime: TimeInterval = 0
    @Published var totalDuration: TimeInterval = 0
    @Published var isPlaying = false
    @Published var playbackSpeed: Double = 1.0
    @Published var midiFileName: String = "No MIDI file loaded"
    @Published var soundFontFileName: String = "No SoundFont loaded"
    private var wasPlayingBeforeSeek = false

    private var trackMap: [MusicTrack: Int] = [:]
    var isSeeking = false
    
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        MIDIClientCreate("FluidClient" as CFString, nil, nil, &midiClient)
        
        MIDIDestinationCreateWithProtocol(midiClient, "FluidDest" as CFString, MIDIProtocolID._1_0, &endpoint) { [weak self] eventList, _ in
            self?.handle(eventList)
        }
    }
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        
        if type == .began {
            pause()
        } else {
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }
    
    func loadSoundFont(_ url: URL) {
        synth.loadSoundFont(url)
        synth.systemReset()
        soundFontFileName = url.lastPathComponent
    }
    
    func loadMIDI(_ url: URL) {
        synth.systemReset()
        synth.allNotesOff()
        NewMusicSequence(&sequence)
        MusicSequenceFileLoad(sequence!, url as CFURL, .midiType, MusicSequenceLoadFlags())
        MusicSequenceSetMIDIEndpoint(sequence!, endpoint)
        
        midiFileName = url.lastPathComponent
        
        detectUsedChannels()
        buildChannelStates()
        calculateDuration()
        
        // Calculate total duration
        calculateDuration()
        
        NewMusicPlayer(&player)
        MusicPlayerSetSequence(player!, sequence!)
        MusicPlayerPreroll(player!)
    }
    
    private func detectUsedChannels() {
        guard let seq = sequence else { return }
        
        usedChannels.removeAll()
        
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(seq, &trackCount)
        
        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(seq, i, &track)
            guard let track = track else { continue }
            
            var iterator: MusicEventIterator?
            NewMusicEventIterator(track, &iterator)
            guard let it = iterator else { continue }
            defer { DisposeMusicEventIterator(it) }
            
            var hasEvent = DarwinBoolean(false)
            MusicEventIteratorHasCurrentEvent(it, &hasEvent)
            
            while hasEvent.boolValue {
                var time = MusicTimeStamp()
                var type = MusicEventType()
                var data: UnsafeRawPointer?
                var size: UInt32 = 0
                
                MusicEventIteratorGetEventInfo(it, &time, &type, &data, &size)
                
                if type == kMusicEventType_MIDIChannelMessage {
                    let msg = data!.assumingMemoryBound(to: MIDIChannelMessage.self).pointee
                    let channel = Int(msg.status & 0x0F)
                    usedChannels.insert(channel)
                }
                
                MusicEventIteratorNextEvent(it)
                MusicEventIteratorHasCurrentEvent(it, &hasEvent)
            }
        }
    }
    private func buildChannelStates() {
        channels.removeAll()
        mutedChannels.removeAll()
        soloChannels.removeAll()
        
        let sorted = usedChannels.sorted()
        
        for ch in sorted {
            let name: String
            if ch == 9 {
                name = "Ch 10 – Drums"
            } else {
                name = "Ch \(ch + 1)"
            }
            channels.append(MIDIChannelState(channel: ch, name: name))
        }
    }
    
    
    //    private func extractTracks() {
    //        guard let seq = sequence else { return }
    //
    //        var trackCount: UInt32 = 0
    //        MusicSequenceGetTrackCount(seq, &trackCount)
    //
    //        tracks.removeAll()
    //        trackMap.removeAll()
    //
    //        for i in 0..<trackCount {
    //            var track: MusicTrack?
    //            MusicSequenceGetIndTrack(seq, UInt32(i), &track)
    //
    //            guard let track = track else { continue }
    //
    //            let trackName = getTrackName(track: track, index: Int(i))
    //            let trackState = MIDITrackState(trackIndex: Int(i), trackName: trackName)
    //            tracks.append(trackState)
    //            trackMap[track] = Int(i)
    //        }
    //    }
    
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
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Audio session activation failed:", error)
        }
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
        isPlaying = false
        MusicPlayerStop(player)
        synth.allNotesOff()
        seek(to: 0)
        stopTimer()
    }
    
    func seek(to time: TimeInterval) {
        guard let player = player, let seq = sequence else { return }

        // Remember state
        print("seek")
        wasPlayingBeforeSeek = isPlaying

        isSeeking = true

        // Stop current sound safely
        synth.allNotesOff()

        // Move time
        var beats: MusicTimeStamp = 0
        MusicSequenceGetBeatsForSeconds(seq, time, &beats)
        MusicPlayerSetTime(player, beats)
        
        // 🔑 RESTORE CHANNEL STATE HERE
          for ch in usedChannels {
              synth.restoreChannelState(ch)
          }

        currentTime = time

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.isSeeking = false
            print("seekend")

            // ✅ Resume only if it was playing
            if self.wasPlayingBeforeSeek {
                MusicPlayerStart(player)
            }
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
        guard let player = player, let seq = sequence else { return }
        
        var time: MusicTimeStamp = 0
        MusicPlayerGetTime(player, &time)
        
        // Convert beats to seconds
        var seconds: TimeInterval = 0
        MusicSequenceGetSecondsForBeats(seq, time, &seconds)
        currentTime = seconds
      

        if currentTime >= totalDuration {
            stop()
        }
    }
    private func areAllUsedChannelsMuted() -> Bool {
        return usedChannels.allSatisfy { mutedChannels.contains($0) }
    }
    
    func setChannelMute(_ channel: Int, muted: Bool) {
        if muted {
            // Mute the channel
            mutedChannels.insert(channel)

            // ⭐ Rule: mute cancels solo
            soloChannels.remove(channel)
            synth.allNotesOff(channel: channel)

            // UI sync
            if let ch = channels.first(where: { $0.channel == channel }) {
                ch.solo = false
            }
        } else {
            mutedChannels.remove(channel)
        }

        // ⭐ Safety: silence synth if everything is muted
        if areAllUsedChannelsMuted() {
            synth.allNotesOff()
        }
    }

    
    func setChannelSolo(_ channel: Int, solo: Bool) {
        if solo {
            // Solo the channel
            soloChannels.insert(channel)

            // ⭐ Rule: solo overrides mute
            mutedChannels.remove(channel)

            // UI sync
            if let ch = channels.first(where: { $0.channel == channel }) {
                ch.muted = false
            }
            
            // 🔑 IMMEDIATELY SILENCE NON-SOLO CHANNELS
            for ch in usedChannels where ch != channel {
                synth.allNotesOff(channel: ch)
            }


        } else {
            soloChannels.remove(channel)
        }
    }

    
    //    func setTrackMute(_ trackIndex: Int, muted: Bool) {
    //        guard let seq = sequence, trackIndex < tracks.count else { return }
    //
    //        var track: MusicTrack?
    //        MusicSequenceGetIndTrack(seq, UInt32(trackIndex), &track)
    //
    //        if let track = track {
    //            var muteValue: UInt32 = muted ? 1 : 0
    //            MusicTrackSetProperty(track, kSequenceTrackProperty_MuteStatus, &muteValue, UInt32(MemoryLayout<UInt32>.size))
    //        }
    //    }
    //
    //    func setTrackSolo(_ trackIndex: Int, solo: Bool) {
    //        guard let seq = sequence, trackIndex < tracks.count else { return }
    //
    //        var track: MusicTrack?
    //        MusicSequenceGetIndTrack(seq, UInt32(trackIndex), &track)
    //
    //        if let track = track {
    //            var soloValue: UInt32 = solo ? 1 : 0
    //            MusicTrackSetProperty(track, kSequenceTrackProperty_SoloStatus, &soloValue, UInt32(MemoryLayout<UInt32>.size))
    //        }
    //    }
    
    func setPlaybackSpeed(_ speed: Double) {
        guard let player = player else { return }
        playbackSpeed = speed
        MusicPlayerSetPlayRateScalar(player, speed)
    }

    
    @available(iOS 16.0, *)
    private func handle(_ list: UnsafePointer<MIDIEventList>) {
        
        // 🚫 Do NOT process MIDI while seeking
        if isSeeking { return }
        
        var packet = list.pointee.packet
        
        for _ in 0..<list.pointee.numPackets {
            
            let wordCount = Int(packet.wordCount)
            
            // 🛡 Safety guard
            if wordCount <= 0 || wordCount > 64 {
                packet = MIDIEventPacketNext(&packet).pointee
                continue
            }
            
            withUnsafePointer(to: &packet.words) {
                $0.withMemoryRebound(to: UInt32.self, capacity: wordCount) { wordsPtr in
                    for i in 0..<wordCount {
                        let word = wordsPtr[i]
                        
                        let status = UInt8((word >> 16) & 0xFF)
                        if status < 0x80 { continue }

                        let data1  = UInt8((word >> 8) & 0xFF)
                        let data2  = UInt8(word & 0xFF)
                        
                        let channel = Int(status & 0x0F)
                        
                        if !soloChannels.isEmpty {
                            if !soloChannels.contains(channel) { continue }
                        } else if mutedChannels.contains(channel) {
                            continue
                        }
                        
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
    @State private var sliderTime: Double = 0
    @State private var isDraggingSlider = false
    @State private var speedValue: Double = 1.0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                // Header Section with File Info
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
                .padding(16)
                .background(Color(uiColor: .systemBackground))
                
                Divider()
                
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
                .padding(16)
                .onChange(of: player.currentTime) { newTime in
                    if !isDraggingSlider {
                        sliderTime = newTime
                    }
                }
                
                Divider()
                
                // Playback Speed Control
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(.orange)

                        Text(String(format: "Speed: %.2fx", speedValue))
                            .font(.system(size: 15, weight: .semibold))

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
                    ) {_ in 
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

                
                Divider()
                
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
                        Text("Reset")
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
                List {
                    ForEach(player.channels) { ch in
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
                }
                .listStyle(PlainListStyle())
                
            }
            .navigationTitle("Fluid MIDI Player4.0")
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

    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
