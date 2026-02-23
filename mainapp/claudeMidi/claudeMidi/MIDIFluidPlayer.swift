import Foundation
import AVFAudio


enum MIDIOutputMode: String, CaseIterable {
    case internalSynth = "Internal Synth"
    case bluetooth = "Bluetooth MIDI"
    case both = "Both"
}

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
import CoreMIDI
import AudioToolbox
import MidiParser

@available(iOS 16.0, *)
final class MIDIFluidPlayer: ObservableObject {
    @Published var vocalEntryTime: TimeInterval = 0
    @Published var queue: [MIDIQueueItem] = []
    @Published var currentQueueIndex: Int = 0
    @Published var isQueueMode: Bool = false
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
    @Published var karaokeLines: [KaraokeLine] = []
    @Published var karaokeWords: [KaraokeWord] = []
    @Published var totalDuration: TimeInterval = 0
    @Published var isPlaying = false
    @Published var canShowProgressBar = false
    @Published var isAnySongLoaded = false
    @Published var playbackSpeed: Double = 1.0
    @Published var midiFileName: String = "No MIDI file loaded"
    @Published var soundFontFileName: String = "No SoundFont loaded"
    @Published var transpose: Int = 0   // range: -24 ... +24
    private var wasPlayingBeforeSeek = false
    @Published var outputMode: MIDIOutputMode = .internalSynth
    @Published var connectedDestination: MIDIEndpointRef? = nil
    private var midiOutPort = MIDIPortRef()
    @Published var connectedDeviceName: String? = nil
    
    
    private var trackMap: [MusicTrack: Int] = [:]
    var isSeeking = false
    
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        // ✅ MIDI client (already correct)
        MIDIClientCreate("FluidClient" as CFString, nil, nil, &midiClient)
        
        // 🆕 MIDI OUTPUT PORT (REQUIRED for Bluetooth MIDI)
        MIDIOutputPortCreate(
            midiClient,
            "MIDIOutPort" as CFString,
            &midiOutPort
        )
        
        // ✅ Virtual MIDI destination (already correct)
        MIDIDestinationCreateWithProtocol(
            midiClient,
            "FluidDest" as CFString,
            MIDIProtocolID._1_0,
            &endpoint
        ) { [weak self] eventList, _ in
            self?.handle(eventList)
        }
    }
    
    func panicAllNotesOff() {
        // Internal synth
        synth.allNotesOff()
        
        // External MIDI
        if let dest = connectedDestination {
            for channel in 0..<16 {
                let status = UInt8(0xB0 | channel)
                sendToMIDIDestination(dest, status: status, d1: 123, d2: 0) // CC123 = All Notes Off
                sendToMIDIDestination(dest, status: status, d1: 120, d2: 0) // CC120 = All Sound Off
            }
        }
    }
    
    func connectToDevice(_ endpoint: MIDIEndpointRef, name: String) {
        connectedDestination = endpoint
        connectedDeviceName = name
    }
    
    func refreshMIDIDestinations() {
        // Only clear if the device is no longer available
        if let currentDest = connectedDestination {
            var stillExists = false
            let count = MIDIGetNumberOfDestinations()
            
            for i in 0..<count {
                let dest = MIDIGetDestination(i)
                if dest == currentDest {
                    stillExists = true
                    break
                }
            }
            
            if !stillExists {
                connectedDestination = nil
                connectedDeviceName = nil
            }
        }
    }
    
    private func sendToMIDIDestination(
        _ destination: MIDIEndpointRef,
        status: UInt8,
        d1: UInt8,
        d2: UInt8
    ) {
        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length = 3
        packet.data.0 = status
        packet.data.1 = d1
        packet.data.2 = d2
        
        var packetList = MIDIPacketList(numPackets: 1, packet: packet)
        MIDISend(midiOutPort, destination, &packetList)
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
        soundFontFileName = url.lastPathComponent
        for ch in 0..<16 {
            synth.gmResetChannel(ch)
        }
    }
    
    func loadMIDI(_ url: URL) {
        isAnySongLoaded = true
        karaokeLines = []
        karaokeWords = []
        let events = extractLyricsFromMIDI(url: url)
        
        switch classifyMidiText(events) {
            
        case .karaoke:
            karaokeLines = buildKaraokeLines(from: events)
            
        case .chords:
            karaokeWords = events.map {
                KaraokeWord(
                    time: $0.0,
                    text: $0.1.replacingOccurrences(of: "%", with: "") + "   "
                )
            }
            
        case .none:
            break
        }
        
        synth.allNotesOff()
        NewMusicSequence(&sequence)
        MusicSequenceFileLoad(sequence!, url as CFURL, .midiType, MusicSequenceLoadFlags())
        MusicSequenceSetMIDIEndpoint(sequence!, endpoint)
        
        midiFileName = url.lastPathComponent
        
        detectUsedChannels()
        buildChannelStates()
        calculateDuration()
        
        
        NewMusicPlayer(&player)
        MusicPlayerSetSequence(player!, sequence!)
        
        for ch in usedChannels {
            synth.gmResetChannel(ch)
        }

        MusicPlayerPreroll(player!)
        
        
        
    }
    func beatsToSeconds(beats: Double, bpm: Double) -> Double {
        return beats * 60.0 / bpm
    }
    
    /// Extract lyrics from MIDI file using MidiParse library
    private func extractLyricsFromMIDI(url: URL) -> [(time: TimeInterval, text: String)] {
        guard let midiData = try? Data(contentsOf: url) else {
            print("❌ Failed to load MIDI data")
            return []
        }
        
        let sut = MidiData()
        sut.load(data: midiData)
        let beatPerMinute: Double = Double(sut.beatsPerMinute.value)
        
        var allLyrics: [(time: TimeInterval, text: String)] = []
        
        // Extract all lyrics with timestamps
        for track in sut.noteTracks {
            for event in track.lyrics {
                let seconds = beatsToSeconds(beats: event.timeStamp, bpm: beatPerMinute)
                allLyrics.append((seconds, event.str))
            }
        }
        
        // Sort by time
        allLyrics.sort { $0.time < $1.time }
        
        // Build karaoke lines
        return allLyrics
    }
    
    
    
    /// Build karaoke lines from lyrics data
    private func buildKaraokeLines(from lyrics: [(time: TimeInterval, text: String)]) -> [KaraokeLine] {
        var lines: [KaraokeLine] = []
        var currentWords: [KaraokeWord] = []
        var wordBuffer = ""
        var wordStartTime: TimeInterval = 0
        
        for (time, text) in lyrics {
            // Detect line breaks (empty text or just whitespace)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Flush any buffered word
                if !wordBuffer.isEmpty {
                    currentWords.append(KaraokeWord(time: wordStartTime, text: wordBuffer))
                    wordBuffer = ""
                }
                
                // Create line if we have words
                if !currentWords.isEmpty {
                    lines.append(KaraokeLine(words: currentWords))
                    currentWords = []
                }
                continue
            }
            
            // Start new word if buffer is empty
            if wordBuffer.isEmpty {
                wordStartTime = time
            }
            
            // Accumulate syllables/text
            wordBuffer += text
            
            // Detect word boundary (ends with space)
            if text.hasSuffix(" ") {
                currentWords.append(KaraokeWord(time: wordStartTime, text: wordBuffer))
                wordBuffer = ""
            }
        }
        
        // Flush remaining content
        if !wordBuffer.isEmpty {
            currentWords.append(KaraokeWord(time: wordStartTime, text: wordBuffer))
        }
        if !currentWords.isEmpty {
            lines.append(KaraokeLine(words: currentWords))
        }
        
        return lines
    }
    
    private func classifyMidiText(_ events: [(TimeInterval, String)]) -> MidiTextType {
        
        guard !events.isEmpty else { return .none }
        
        var chordScore = 0
        var lyricScore = 0
        
        for (_, text) in events.prefix(40) { // only scan early events
            
            // Strong chord indicators
            if text.hasPrefix("%") { chordScore += 3 }
            if text.contains("/") { chordScore += 2 }
            if text.range(of: "[0-9]", options: .regularExpression) != nil {
                chordScore += 1
            }
            
            // Language indicators
            if text.range(of: "[aeiouAEIOU]", options: .regularExpression) != nil {
                lyricScore += 1
            }
            
            if text.count > 2 && text.range(of: "[A-Za-z]{3}", options: .regularExpression) != nil {
                lyricScore += 2
            }
        }
        
        if chordScore > lyricScore {
            return .chords
        }
        
        return .karaoke
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
        
        // 🔒 RESTORE CHANNEL STATE HERE
        for ch in usedChannels {
            synth.gmResetChannel(ch)
        }
        
        currentTime = time
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.isSeeking = false
            
            // ✅ Resume only if it was playing
            if self.wasPlayingBeforeSeek {
                print("wasPlayingBeforeSeek")

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
            if isQueueMode {
                stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                    self?.skipToNext()
                }
                
            }
            else { stop() }

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
            
            // 🔒 IMMEDIATELY SILENCE NON-SOLO CHANNELS
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
                        
                        let command = status & 0xF0
                        var note = data1
                        
                        // 🎵 APPLY TRANSPOSE
                        if command == 0x90 || command == 0x80 {
                            // ❌ Do NOT transpose drums (Channel 10 → index 9)
                            if channel != 9 && transpose != 0 {
                                let transposed = Int(note) + transpose
                                note = UInt8(max(0, min(127, transposed)))
                            }
                        }
                        
                        switch outputMode {
                        case .internalSynth:
                            synth.send(status: status, d1: note, d2: data2)
                            
                        case .bluetooth:
                            if let dest = connectedDestination {
                                sendToMIDIDestination(dest, status: status, d1: note, d2: data2)
                            }
                            
                        case .both:
                            synth.send(status: status, d1: note, d2: data2)
                            if let dest = connectedDestination {
                                sendToMIDIDestination(dest, status: status, d1: note, d2: data2)
                            }
                        }
                        
                    }
                }
            }
            
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }
    
    
    
    
}
struct MIDIQueueItem: Identifiable {
    let id = UUID()
    let fileName: String
    private let bookmark: Data

    /// Create from a live security-scoped URL (call while access is still active)
    init?(url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            print("❌ Failed to create bookmark for \(url.lastPathComponent)")
            return nil
        }
        self.fileName = url.lastPathComponent
        self.bookmark = bookmark
    }

    /// Resolve the bookmark back to a usable URL, with security scope access
    /// - Returns: URL with active security scope, or nil on failure
    /// - Important: Caller must call `url.stopAccessingSecurityScopedResource()` when done
    func resolveURL() -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            print("❌ Failed to resolve bookmark for \(fileName)")
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            print("❌ Security scope access denied for \(fileName)")
            return nil
        }

        return url
    }
}

extension MIDIFluidPlayer {

    // ── Queue Management ────────────────────────────────────

    /// Enqueue a single MIDI file.
    /// Call this while the security-scoped resource is still accessible.
    func enqueue(_ url: URL) {
        guard let item = MIDIQueueItem(url: url) else { return }
        queue.append(item)
        if queue.count > 1 {
            isQueueMode = true
        }
    }

    /// Enqueue multiple MIDI files.
    /// Call this while security-scoped resources are still accessible.
    func enqueue(_ urls: [URL]) {
        let items = urls.compactMap { MIDIQueueItem(url: $0) }
        queue.append(contentsOf: items)
        if queue.count > 1 {
            isQueueMode = true
        }
    }

    /// Remove item at a specific index
    func removeFromQueue(at index: Int) {
        guard index < queue.count else { return }
        queue.remove(at: index)
        if index < currentQueueIndex {
            currentQueueIndex = max(0, currentQueueIndex - 1)
        }
        if queue.count > 1 {
            isQueueMode = true
        }
    }

    /// Reorder items (for drag-to-reorder in List)
    func moveInQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }

    /// Clear the entire queue and stop playback
    func clearQueue() {
        stop()
        queue.removeAll()
        currentQueueIndex = 0
        isQueueMode = false
    }

    // ── Playback ─────────────────────────────────────────────

    /// Start playing the queue from the first item
    func playQueue() {
        guard !queue.isEmpty else { return }
        isQueueMode = true
        currentQueueIndex = 0
        loadAndPlay(queue[currentQueueIndex])
    }
    
    func preloadFromQueue(at index: Int) {
        guard index < queue.count else { return }
        loadOnly(queue[index])
    }
    /// Start playing the queue from a specific index (e.g. user taps a song)
    func playQueue(from index: Int) {
        guard index < queue.count else { return }
        isQueueMode = true
        currentQueueIndex = index
        loadAndPlay(queue[currentQueueIndex])
    }

    /// Skip to the next song
    func skipToNext() {
        guard isQueueMode, currentQueueIndex + 1 < queue.count else {
            stop(); return
        }
        currentQueueIndex += 1
        loadAndPlay(queue[currentQueueIndex])
    }

    /// Skip to the previous song (or restart current if at beginning)
    func skipToPrevious() {
        guard isQueueMode, currentQueueIndex > 0 else {
            seek(to: 0)
            if !isPlaying { play() }
            return
        }
        currentQueueIndex -= 1
        loadAndPlay(queue[currentQueueIndex])
    }

    // ── Internal ─────────────────────────────────────────────

    /// Resolve bookmark → load → play, then release security scope
    internal func loadAndPlay(_ item: MIDIQueueItem) {
        stop()
        guard let url = item.resolveURL() else {
            print("❌ Skipping \(item.fileName) — could not resolve URL")
            skipToNext() // skip broken items gracefully
            return
        }
        canShowProgressBar = true
        loadMIDI(url)
        url.stopAccessingSecurityScopedResource() // safe to release after loadMIDI copies data
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
            self?.play()
            self?.canShowProgressBar = false


        }
    }

    internal func loadOnly(_ item: MIDIQueueItem) {
        stop()

        guard let url = item.resolveURL() else {
            print("❌ Could not resolve URL for \(item.fileName)")
            return
        }

        loadMIDI(url)
        url.stopAccessingSecurityScopedResource()
    }
    /// Called by updateCurrentTime() when a song finishes
    internal func playNextInQueue() {
        if currentQueueIndex + 1 < queue.count {
            currentQueueIndex += 1
            loadAndPlay(queue[currentQueueIndex])
        } else {
            isQueueMode = false
            stop()
        }
    }



    var currentQueueItem: MIDIQueueItem? {
        guard isQueueMode, currentQueueIndex < queue.count else { return nil }
        return queue[currentQueueIndex]
    }
}
