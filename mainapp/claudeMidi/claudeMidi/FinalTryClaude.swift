//import SwiftUI
//import AVFoundation
//import CoreMIDI
//import UniformTypeIdentifiers
//
//// MARK: - MIDI Device Info
//struct MIDIDeviceInfo: Identifiable, Equatable {
//    let id: MIDIEndpointRef
//    let name: String
//    let isSource: Bool
//    
//    static func == (lhs: MIDIDeviceInfo, rhs: MIDIDeviceInfo) -> Bool {
//        lhs.id == rhs.id
//    }
//}
//
//// MARK: - MIDI Learn Action
//enum MIDILearnAction: String, CaseIterable {
//    case play = "Play/Pause"
//    case stop = "Stop"
//    case nextTrack = "Next Track"
//    case previousTrack = "Previous Track"
//    case tempoUp = "Tempo Up"
//    case tempoDown = "Tempo Down"
//    case transposeUp = "Transpose Up"
//    case transposeDown = "Transpose Down"
//    case toggleMetronome = "Toggle Metronome"
//}
//
//struct MIDIMapping: Codable {
//    let cc: UInt8
//    let channel: UInt8
//    let action: String
//}
//
//// MARK: - Track Info
//struct TrackInfo: Identifiable {
//    let id: Int
//    let trackNumber: Int
//    var name: String
//    var channels: Set<Int>
//    var isMuted: Bool = false
//    var isSolo: Bool = false
//    var eventCount: Int = 0
//}
//
//// MARK: - Audio Channel Class
//class AudioChannel: ObservableObject {
//    private var engine: AVAudioEngine
//    private var sampler: AVAudioUnitSampler
//    private var mixer: AVAudioMixerNode
//    let channelNumber: Int
//    
//    @Published var volume: Float = 100.0
//    @Published var currentInstrument: UInt8 = 0
//    @Published var isActive: Bool = false
//    
//    private let loadQueue = DispatchQueue(label: "com.midiplayer.soundfont", qos: .userInitiated)
//    private var isLoading: Bool = false
//    
//    init(channelNumber: Int) {
//        self.channelNumber = channelNumber
//        self.engine = AVAudioEngine()
//        self.sampler = AVAudioUnitSampler()
//        self.mixer = engine.mainMixerNode
//        
//        setupAudioEngine()
//    }
//    
//    private func setupAudioEngine() {
//        engine.attach(sampler)
//        engine.connect(sampler, to: mixer, format: nil)
//        
//        do {
//            try engine.start()
//        } catch {
//            print("Error starting audio engine: \(error)")
//        }
//    }
//    
//    func loadSoundFont(url: URL, preset: UInt8, isDrum: Bool = false) {
//        // Prevent concurrent loads
//        do {
//                   if isDrum {
//                       try sampler.loadSoundBankInstrument(
//                           at: url,
//                           program: preset,
//                           bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB),
//                           bankLSB: UInt8(kAUSampler_DefaultBankLSB)
//                       )
//                   } else {
//                       try sampler.loadSoundBankInstrument(
//                           at: url,
//                           program: preset,
//                           bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
//                           bankLSB: UInt8(kAUSampler_DefaultBankLSB)
//                       )
//                   }
//                  print("load soundfont for channel: \(channelNumber) done")
//               } catch {
//                   print("Error loading sound font: \(error)")
//                   print("  URL: \(url.path)")
//                   print("  Preset: \(preset)")
//                   print("  isDrum: \(isDrum)")
//               }
//    }
//    
//    func sendMIDIEvent(status: UInt8, data1: UInt8, data2: UInt8) {
//        sampler.sendMIDIEvent(status, data1: data1, data2: data2)
//        
//        if (status & 0xF0) == 0x90 && data2 > 0 {
//            DispatchQueue.main.async {
//                self.isActive = true
//            }
//        }
//    }
//    
//    func allNotesOff() {
//        sampler.sendMIDIEvent(0xB0 | UInt8(channelNumber), data1: 123, data2: 0)
//        DispatchQueue.main.async {
//            self.isActive = false
//        }
//    }
//    
//    func stop() {
//        engine.stop()
//    }
//}
//
//// MARK: - Metronome
//class Metronome: ObservableObject {
//    private var engine: AVAudioEngine
//    private var sampler: AVAudioUnitSampler
//    @Published var isEnabled: Bool = false
//    @Published var volume: Float = 80.0
//    @Published var beatsPerMeasure: Int = 4
//    
//    private var currentBeat: Int = 0
//    
//    init() {
//        self.engine = AVAudioEngine()
//        self.sampler = AVAudioUnitSampler()
//        
//        engine.attach(sampler)
//        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
//        
//        do {
//            try engine.start()
//        } catch {
//            print("Error starting metronome engine: \(error)")
//        }
//        
//        loadMetronomeSounds()
//    }
//    
//    private func loadMetronomeSounds() {
//        if let soundFontURL = Bundle.main.url(forResource: "GeneralUser GS", withExtension: "sf2") {
//            try? sampler.loadSoundBankInstrument(
//                at: soundFontURL,
//                program: 0,
//                bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB),
//                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
//            )
//        }
//    }
//    
//    func tick(beat: Int) {
//        guard isEnabled else { return }
//        
//        currentBeat = beat % beatsPerMeasure
//        let note: UInt8 = currentBeat == 0 ? 76 : 77
//        let velocity = UInt8(volume * 127.0 / 100.0)
//        
//        sampler.sendMIDIEvent(0x99, data1: note, data2: velocity)
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//            self.sampler.sendMIDIEvent(0x99, data1: note, data2: 0)
//        }
//    }
//}
//
//// MARK: - MIDI Manager
//class MIDIManager: ObservableObject {
//    private var midiClient = MIDIClientRef()
//    private var virtualDestination = MIDIEndpointRef()
//    private var inputPort = MIDIPortRef()
//    private var outputPort = MIDIPortRef()
//    private var musicPlayer: MusicPlayer?
//    private var musicSequence: MusicSequence?
//    
//    @Published var channels: [AudioChannel] = []
//    @Published var isPlaying: Bool = false
//    @Published var currentTime: Double = 0.0
//    @Published var totalTime: Double = 0.0
//    @Published var totalTimeInSeconds: Double = 0.0  // Real duration in seconds
//    @Published var currentFileName: String = "No file loaded"
//    @Published var tracks: [TrackInfo] = []
//    
//    @Published var availableInputDevices: [MIDIDeviceInfo] = []
//    @Published var availableOutputDevices: [MIDIDeviceInfo] = []
//    @Published var selectedInputDevice: MIDIDeviceInfo?
//    @Published var selectedOutputDevice: MIDIDeviceInfo?
//    @Published var midiThrough: Bool = true
//    @Published var isSearchingDevices: Bool = false
//    @Published var autoConnectBluetooth: Bool = true
//    
//    private var deviceScanTimer: Timer?
//    
//    @Published var tempo: Double = 1.0
//    @Published var transpose: Int = 0
//    @Published var loopEnabled: Bool = false
//    @Published var loopStart: Double = 0.0
//    @Published var loopEnd: Double = 0.0
//    
//    @Published var metronome = Metronome()
//    private var lastBeat: Int = -1
//    
//    @Published var isLearningMIDI: Bool = false
//    @Published var learningAction: MIDILearnAction?
//    @Published var midiMappings: [String: MIDIMapping] = [:]
//    
//    private var displayLink: CADisplayLink?
//    private var selectedOutputEndpoint: MIDIEndpointRef = 0
//    
//    init() {
//        setupChannels()
//        setupMIDI()
//        setupDisplayLink()
//        loadMIDIMappings()
//        scanMIDIDevices()
//        //startDeviceScanning() // Auto-scan for devices periodically
//    }
//    
//    private func setupChannels() {
//        for i in 0..<16 {
//            channels.append(AudioChannel(channelNumber: i))
//        }
//        
//        if let soundFontURL = Bundle.main.url(forResource: "GeneralUser GS", withExtension: "sf2") {
//            loadSoundFont(url: soundFontURL)
//        }
//    }
//    
//    func loadSoundFont(url: URL) {
//        for (index, channel) in channels.enumerated() {
//            if index == 9 {
//                channel.loadSoundFont(url: url, preset: 0, isDrum: true)
//            } else {
//                channel.loadSoundFont(url: url, preset: 0, isDrum: false)
//            }
//        }
//    }
//    
//    private func setupMIDI() {
//        var status = MIDIClientCreateWithBlock("MIDI Client" as CFString, &midiClient) { [weak self] notification in
//            self?.handleMIDINotification(notification)
//        }
//        
//        guard status == noErr else {
//            print("Error creating MIDI client")
//            return
//        }
//        
//        status = MIDIInputPortCreateWithProtocol(
//            midiClient,
//            "Input Port" as CFString,
//            ._1_0,
//            &inputPort
//        ) { [weak self] eventList, _ in
//            self?.handleExternalMIDIEvents(eventList: eventList)
//        }
//        
//        status = MIDIOutputPortCreate(midiClient, "Output Port" as CFString, &outputPort)
//        
//        if #available(iOS 14.0, *) {
//            status = MIDIDestinationCreateWithProtocol(
//                midiClient,
//                "Virtual Destination" as CFString,
//                ._1_0,
//                &virtualDestination
//            ) { [weak self] eventList, _ in
//                self?.handleMIDIEvents(eventList: eventList)
//            }
//        }
//        
//        guard status == noErr else {
//            print("Error creating MIDI ports")
//            return
//        }
//    }
//    
//    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
//        let notificationType = notification.pointee.messageID
//        
//        // Log device add/remove events
//        if notificationType == .msgObjectAdded {
//            print("✅ MIDI Device Added")
//        } else if notificationType == .msgObjectRemoved {
//            print("❌ MIDI Device Removed")
//        }
//        
//        DispatchQueue.main.async {
//            self.scanMIDIDevices()
//            
//            // Auto-connect to first Bluetooth output device if enabled
//            if self.autoConnectBluetooth && self.selectedOutputDevice == nil {
//                self.autoConnectFirstBluetoothOutput()
//            }
//        }
//    }
//    
//    func startDeviceScanning() {
//        stopDeviceScanning()
//        
//        isSearchingDevices = true
//        
//        // Scan every 3 seconds for new devices
//        deviceScanTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
//            self?.scanMIDIDevices()
//        }
//    }
//    
//    func stopDeviceScanning() {
//        deviceScanTimer?.invalidate()
//        deviceScanTimer = nil
//        isSearchingDevices = false
//    }
//    
//    func autoConnectFirstBluetoothOutput() {
//        // Look for Bluetooth MIDI devices in output list
//        for device in availableOutputDevices {
//            if isBluetoothDevice(device.name) && selectedOutputDevice == nil {
//                print("🔵 Auto-connecting to Bluetooth device: \(device.name)")
//                connectOutputDevice(device)
//                break
//            }
//        }
//    }
//    
//     func isBluetoothDevice(_ name: String) -> Bool {
//        // Common Bluetooth MIDI device name patterns
//        let bluetoothKeywords = ["bluetooth", "bt", "wireless", "ble", "midi"]
//        let lowercaseName = name.lowercased()
//        
//        return bluetoothKeywords.contains { lowercaseName.contains($0) }
//    }
//    
//    func scanMIDIDevices() {
//        var inputs: [MIDIDeviceInfo] = []
//        var outputs: [MIDIDeviceInfo] = []
//        
//        print("🔍 Scanning for MIDI devices...")
//        
//        let sourceCount = MIDIGetNumberOfSources()
//        print("   Found \(sourceCount) input sources")
//        for i in 0..<sourceCount {
//            let endpoint = MIDIGetSource(i)
//            if let name = getMIDIObjectName(endpoint) {
//                let isBluetooth = isBluetoothDevice(name)
//                print("   📥 Input: \(name) \(isBluetooth ? "🔵 (Bluetooth)" : "")")
//                inputs.append(MIDIDeviceInfo(id: endpoint, name: name, isSource: true))
//            }
//        }
//        
//        let destCount = MIDIGetNumberOfDestinations()
//        print("   Found \(destCount) output destinations")
//        for i in 0..<destCount {
//            let endpoint = MIDIGetDestination(i)
//            if let name = getMIDIObjectName(endpoint) {
//                if name != "Virtual Destination" {
//                    let isBluetooth = isBluetoothDevice(name)
//                    print("   📤 Output: \(name) \(isBluetooth ? "🔵 (Bluetooth)" : "")")
//                    outputs.append(MIDIDeviceInfo(id: endpoint, name: name, isSource: false))
//                }
//            }
//        }
//        
//        DispatchQueue.main.async {
//            self.availableInputDevices = inputs
//            self.availableOutputDevices = outputs
//        }
//    }
//    
//    private func getMIDIObjectName(_ obj: MIDIObjectRef) -> String? {
//        var name: Unmanaged<CFString>?
//        let status = MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &name)
//        if status == noErr, let name = name {
//            return name.takeRetainedValue() as String
//        }
//        return nil
//    }
//    
//    func connectInputDevice(_ device: MIDIDeviceInfo) {
//        if let previous = selectedInputDevice {
//            MIDIPortDisconnectSource(inputPort, previous.id)
//        }
//        
//        let status = MIDIPortConnectSource(inputPort, device.id, nil)
//        if status == noErr {
//            DispatchQueue.main.async {
//                self.selectedInputDevice = device
//            }
//        }
//    }
//    
//    func disconnectInputDevice() {
//        if let device = selectedInputDevice {
//            MIDIPortDisconnectSource(inputPort, device.id)
//            DispatchQueue.main.async {
//                self.selectedInputDevice = nil
//            }
//        }
//    }
//    
//    func connectOutputDevice(_ device: MIDIDeviceInfo) {
//        selectedOutputEndpoint = device.id
//        DispatchQueue.main.async {
//            self.selectedOutputDevice = device
//            print("✅ Connected to output device: \(device.name)")
//        }
//    }
//    
//    func disconnectOutputDevice() {
//        let deviceName = selectedOutputDevice?.name ?? "Unknown"
//        selectedOutputEndpoint = 0
//        DispatchQueue.main.async {
//            self.selectedOutputDevice = nil
//            print("❌ Disconnected from output device: \(deviceName)")
//        }
//    }
//    
//    func connectToAllBluetoothOutputs() {
//        for device in availableOutputDevices {
//            if isBluetoothDevice(device.name) {
//                connectOutputDevice(device)
//                return // Connect to first one found
//            }
//        }
//    }
//    
//    private func handleExternalMIDIEvents(eventList: UnsafePointer<MIDIEventList>) {
//        // Get the first packet
//        var packet = eventList.pointee.packet
//        
//        // Iterate through all packets in the event list
//        for _ in 0..<eventList.pointee.numPackets {
//            // Check if word count exceeds maximum (64 words per spec)
//            if packet.wordCount > 64 {
//                print("⚠️ WARNING: MIDIEventPacket wordCount > 64, ignoring packet")
//                packet = MIDIEventPacketNext(&packet).pointee
//                continue
//            }
//            
//            // Access words tuple using withUnsafeBytes
//            // The words field is a 64-element tuple, we need to convert it to an array-like structure
//            withUnsafeBytes(of: packet.words) { wordsPtr in
//                let wordsArray = wordsPtr.bindMemory(to: UInt32.self)
//                
//                // Process each word in the packet
//                for j in 0..<Int(packet.wordCount) {
//                    let word = wordsArray[j]
//                    
//                    /* Universal MIDI Packet (UMP) Format for MIDI 1.0:
//                     32-bit word structure:
//                     - Bits 31-28: Message Type (0x2 for MIDI 1.0 Channel Voice)
//                     - Bits 27-24: Group (ignored for MIDI 1.0)
//                     - Bits 23-16: Status byte (opcode + channel)
//                     - Bits 15-8:  Data byte 1
//                     - Bits 7-0:   Data byte 2
//                     
//                     Apple provides UMP in native endian format (little-endian on ARM64)
//                     Extract bytes using bit shifts:
//                    */
//                    
//                    let status = UInt8((word >> 16) & 0xFF)  // Status byte
//                    let data1 = UInt8((word >> 8) & 0xFF)    // Data byte 1
//                    let data2 = UInt8(word & 0xFF)           // Data byte 2
//                    
//                    let channel = Int(status & 0x0F)         // Extract channel (0-15)
//                    let command = status & 0xF0              // Extract command (0x80-0xF0)
//                    
//                    print("📥 External MIDI: Ch\(channel) [\(String(format: "%02X", status)) \(String(format: "%02X", data1)) \(String(format: "%02X", data2))]")
//                    
//                    // Handle MIDI Learn mode
//                    if isLearningMIDI && command == 0xB0 {  // Control Change
//                        handleMIDILearn(cc: data1, channel: UInt8(channel))
//                        continue
//                    }
//                    
//                    // Check for mapped MIDI controls
//                    if command == 0xB0 {  // Control Change
//                        let key = "\(data1)_\(channel)"
//                        if let mapping = midiMappings[key] {
//                            executeMIDIAction(mapping.action, value: data2)
//                        }
//                    }
//                    
//                    // Validate MIDI command types (Note On/Off, CC, Program Change, etc.)
//                    // Commands 0x80-0xE0 are valid channel voice messages
//                    if command >= 0x80 && command < 0xF0 {
//                        // Send to internal synthesizer
//                        if channel < channels.count {
//                            channels[channel].sendMIDIEvent(status: status, data1: data1, data2: data2)
//                        }
//                        
//                        // MIDI Through: Forward to output device
//                        if midiThrough && selectedOutputEndpoint != 0 {
//                            sendToOutputDevice(status: status, data1: data1, data2: data2)
//                        }
//                    }
//                    
//                    // Handle System Exclusive (SysEx) messages
//                    if status == 0xF0 || status == 0xF7 {
//                        print("📨 SysEx message received")
//                        // SysEx handling can be added here if needed
//                    }
//                }
//            }
//            
//            // Move to next packet
//            packet = MIDIEventPacketNext(&packet).pointee
//        }
//    }
//    
//    private func sendToOutputDevice(status: UInt8, data1: UInt8, data2: UInt8) {
//        guard selectedOutputEndpoint != 0 else { return }
//        
//        var packetList = MIDIPacketList()
//        var packet = MIDIPacketListInit(&packetList)
//        
//        var midiData: [UInt8] = [status, data1, data2]
//        packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, 3, &midiData)
//        
//        MIDISend(outputPort, selectedOutputEndpoint, &packetList)
//    }
//    
//    func startMIDILearn(for action: MIDILearnAction) {
//        isLearningMIDI = true
//        learningAction = action
//    }
//    
//    func cancelMIDILearn() {
//        isLearningMIDI = false
//        learningAction = nil
//    }
//    
//    private func handleMIDILearn(cc: UInt8, channel: UInt8) {
//        guard let action = learningAction else { return }
//        
//        let key = "\(cc)_\(channel)"
//        let mapping = MIDIMapping(cc: cc, channel: channel, action: action.rawValue)
//        
//        DispatchQueue.main.async {
//            self.midiMappings[key] = mapping
//            self.isLearningMIDI = false
//            self.learningAction = nil
//            self.saveMIDIMappings()
//        }
//    }
//    
//    private func executeMIDIAction(_ actionString: String, value: UInt8) {
//        guard let action = MIDILearnAction(rawValue: actionString) else { return }
//        
//        DispatchQueue.main.async {
//            switch action {
//            case .play:
//                if value > 63 {
//                    if self.isPlaying {
//                        self.pause()
//                    } else {
//                        self.play()
//                    }
//                }
//            case .stop:
//                if value > 63 {
//                    self.stop()
//                }
//            case .tempoUp:
//                if value > 63 {
//                    self.tempo = min(2.0, self.tempo + 0.1)
//                }
//            case .tempoDown:
//                if value > 63 {
//                    self.tempo = max(0.5, self.tempo - 0.1)
//                }
//            case .transposeUp:
//                if value > 63 {
//                    self.transpose = min(12, self.transpose + 1)
//                }
//            case .transposeDown:
//                if value > 63 {
//                    self.transpose = max(-12, self.transpose - 1)
//                }
//            case .toggleMetronome:
//                if value > 63 {
//                    self.metronome.isEnabled.toggle()
//                }
//            default:
//                break
//            }
//        }
//    }
//    
//    private func saveMIDIMappings() {
//        if let encoded = try? JSONEncoder().encode(Array(midiMappings.values)) {
//            UserDefaults.standard.set(encoded, forKey: "MIDIMappings")
//        }
//    }
//    
//    private func loadMIDIMappings() {
//        if let data = UserDefaults.standard.data(forKey: "MIDIMappings"),
//           let mappings = try? JSONDecoder().decode([MIDIMapping].self, from: data) {
//            for mapping in mappings {
//                let key = "\(mapping.cc)_\(mapping.channel)"
//                midiMappings[key] = mapping
//            }
//        }
//    }
//    
//    func clearMIDIMapping(_ mapping: MIDIMapping) {
//        let key = "\(mapping.cc)_\(mapping.channel)"
//        midiMappings.removeValue(forKey: key)
//        saveMIDIMappings()
//    }
//    
//    @available(iOS 14.0, *)
//    private func handleMIDIEvents(eventList: UnsafePointer<MIDIEventList>) {
//        var packet = eventList.pointee.packet
//        
//        for _ in 0..<eventList.pointee.numPackets {
//            if packet.wordCount > 64 {
//                packet = MIDIEventPacketNext(&packet).pointee
//                continue
//            }
//            
//            // FIX #3: Process ALL words in packet for complete MIDI data
//            withUnsafeBytes(of: packet.words) { wordsPtr in
//                let wordsArray = wordsPtr.bindMemory(to: UInt32.self)
//                
//                for j in 0..<Int(packet.wordCount) {
//                    let word = wordsArray[j]
//                    
//                    // Extract MIDI bytes from UMP format
//                    var status = UInt8((word >> 16) & 0xFF)
//                    var data1 = UInt8((word >> 8) & 0xFF)
//                    var data2 = UInt8(word & 0xFF)
//                    
//                    let channel = Int(status & 0x0F)
//                    let command = status & 0xF0
//                    
//                    // Apply transpose (only to note messages, not drums)
//                    if (command == 0x90 || command == 0x80) && channel != 9 && transpose != 0 {
//                        let newNote = Int(data1) + transpose
//                        if newNote >= 0 && newNote <= 127 {
//                            data1 = UInt8(newNote)
//                            // Rebuild status byte with potentially new values
//                            status = command | UInt8(channel)
//                        }
//                    }
//                    
//                    // Check track mute/solo state
//                    if !shouldPlayChannel(channel) {
//                        continue
//                    }
//                    
//                    // Validate MIDI command (0x80-0xEF are valid channel voice messages)
//                    if command >= 0x80 && command < 0xF0 {
//                        // Send to internal synthesizer
//                        if channel < channels.count {
//                            channels[channel].sendMIDIEvent(status: status, data1: data1, data2: data2)
//                            
//                            // Handle program changes
//                            if command == 0xC0 {
//                                // Load sound font - already thread-safe in AudioChannel
//                                if let url = self.getSoundFontURL() {
//                                    // Validate file exists before attempting to load
//                                    if FileManager.default.fileExists(atPath: url.path) {
//                                        self.channels[channel].loadSoundFont(
//                                            url: url,
//                                            preset: data1,
//                                            isDrum: channel == 9
//                                        )
//                                    } else {
//                                        print("⚠️ SoundFont not found: \(url.path)")
//                                    }
//                                }
//                            }
//                        }
//                        
//                        // Send to external output device
//                        if selectedOutputEndpoint != 0 {
//                            sendToOutputDevice(status: status, data1: data1, data2: data2)
//                        }
//                    }
//                    
//                    // Handle System Messages (0xF0-0xFF)
//                    if status >= 0xF0 {
//                        if status == 0xF0 || status == 0xF7 {
//                            // SysEx messages - could be ignored or logged
//                            print("📨 SysEx message: \(String(format: "%02X", status))")
//                        }
//                        // System Real-Time messages (0xF8-0xFF) are typically ignored in playback
//                    }
//                }
//            }
//            
//            packet = MIDIEventPacketNext(&packet).pointee
//        }
//    }
//    
//    private func shouldPlayChannel(_ channel: Int) -> Bool {
//        let hasSolo = tracks.contains { $0.isSolo }
//        
//        for track in tracks {
//            if track.channels.contains(channel) {
//                if hasSolo {
//                    return track.isSolo
//                } else {
//                    return !track.isMuted
//                }
//            }
//        }
//        
//        return true
//    }
//    
//    private func getSoundFontURL() -> URL? {
//        if let url = Bundle.main.url(forResource: "GeneralUser GS", withExtension: "sf2") {
//            return url
//        }
//        return nil
//    }
//    
//    func loadMIDIFile(url: URL) {
//        stop()
//        
//        // Show loading state
//        DispatchQueue.main.async {
//            self.currentFileName = "Loading..."
//        }
//        
//        // Load MIDI file in background to prevent UI hang
//        DispatchQueue.global(qos: .userInitiated).async {
//            var sequence: MusicSequence?
//            var player: MusicPlayer?
//            
//            NewMusicSequence(&sequence)
//            NewMusicPlayer(&player)
//            
//            guard let sequence = sequence, let player = player else {
//                print("Failed to create music sequence/player")
//                return
//            }
//            
//            let status = MusicSequenceFileLoad(
//                sequence,
//                url as CFURL,
//                .midiType,
//                .smf_ChannelsToTracks
//            )
//            
//            guard status == noErr else {
//                print("Error loading MIDI file: \(status)")
//                return
//            }
//            
//            // Configure on background thread
//            MusicSequenceSetMIDIEndpoint(sequence, self.virtualDestination)
//            MusicPlayerSetSequence(player, sequence)
//            MusicPlayerPreroll(player)
//            
//            self.musicSequence = sequence
//            self.musicPlayer = player
//            
//            var trackCount: UInt32 = 0
//            MusicSequenceGetTrackCount(sequence, &trackCount)
//            
//            // Get max length quickly without tempo calculation first
//            var maxLength: MusicTimeStamp = 0
//            var trackInfos: [TrackInfo] = []
//            
//            // Check tempo track
//            var tempoTrack: MusicTrack?
//            MusicSequenceGetTempoTrack(sequence, &tempoTrack)
//            if let tempoTrack = tempoTrack {
//                var tempoLength: MusicTimeStamp = 0
//                var size: UInt32 = UInt32(MemoryLayout<MusicTimeStamp>.size)
//                MusicTrackGetProperty(tempoTrack, kSequenceTrackProperty_TrackLength, &tempoLength, &size)
//                if tempoLength > maxLength {
//                    maxLength = tempoLength
//                }
//            }
//            
//            // Get track info
//            for i in 0..<trackCount {
//                var track: MusicTrack?
//                var length: MusicTimeStamp = 0
//                var size: UInt32 = UInt32(MemoryLayout<MusicTimeStamp>.size)
//                
//                MusicSequenceGetIndTrack(sequence, i, &track)
//                if let track = track {
//                    MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &length, &size)
//                    if length > maxLength {
//                        maxLength = length
//                    }
//                    
//                    let channelsUsed = self.getChannelsInTrack(track)
//                    let eventCount = self.getEventCount(track)
//                    
//                    var trackName = "Track \(i + 1)"
//                    if channelsUsed.contains(9) {
//                        trackName += " - Drums"
//                    } else if let firstChannel = channelsUsed.first {
//                        trackName += " - Ch \(firstChannel + 1)"
//                    }
//                    
//                    let trackInfo = TrackInfo(
//                        id: Int(i),
//                        trackNumber: Int(i),
//                        name: trackName,
//                        channels: channelsUsed,
//                        isMuted: false,
//                        isSolo: false,
//                        eventCount: eventCount
//                    )
//                    
//                    trackInfos.append(trackInfo)
//                }
//            }
//            
//            // Calculate real duration with optimized algorithm
//            let realDuration = self.calculateRealDurationOptimized(sequence: sequence, beats: maxLength)
//            
//            // Update UI on main thread
//            DispatchQueue.main.async {
//                self.totalTime = maxLength
//                self.totalTimeInSeconds = realDuration
//                self.currentFileName = url.lastPathComponent
//                self.tracks = trackInfos
//                self.loopStart = 0
//                self.loopEnd = maxLength
//                
//                print("📊 MIDI File Loaded:")
//                print("   File: \(url.lastPathComponent)")
//                print("   Beats: \(maxLength)")
//                print("   Duration: \(self.formatDuration(realDuration))")
//                print("   Tracks: \(trackInfos.count)")
//            }
//        }
//    }
//    
//    // Optimized duration calculation - much faster!
//    private func calculateRealDurationOptimized(sequence: MusicSequence, beats: MusicTimeStamp) -> TimeInterval {
//        var tempoTrack: MusicTrack?
//        MusicSequenceGetTempoTrack(sequence, &tempoTrack)
//        
//        guard let tempoTrack = tempoTrack else {
//            // No tempo track, use default 120 BPM
//            return beats / 2.0
//        }
//        
//        var iterator: MusicEventIterator?
//        NewMusicEventIterator(tempoTrack, &iterator)
//        guard let iterator = iterator else {
//            return beats / 2.0
//        }
//        
//        // Collect all tempo events first (faster than iterating multiple times)
//        var tempoEvents: [(timestamp: MusicTimeStamp, bpm: Float64)] = []
//        
//        var hasEvent: DarwinBoolean = false
//        MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
//        
//        while hasEvent.boolValue {
//            var timestamp: MusicTimeStamp = 0
//            var eventType: MusicEventType = 0
//            var eventData: UnsafeRawPointer?
//            var eventDataSize: UInt32 = 0
//            
//            MusicEventIteratorGetEventInfo(iterator, &timestamp, &eventType, &eventData, &eventDataSize)
//            
//            if eventType == kMusicEventType_ExtendedTempo, let data = eventData {
//                let tempoValue = data.load(as: ExtendedTempoEvent.self)
//                tempoEvents.append((timestamp: timestamp, bpm: tempoValue.bpm))
//            }
//            
//            MusicEventIteratorNextEvent(iterator)
//            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
//        }
//        
//        DisposeMusicEventIterator(iterator)
//        
//        // If no tempo events, use default
//        guard !tempoEvents.isEmpty else {
//            return beats / 2.0
//        }
//        
//        // Calculate duration from tempo events
//        var totalSeconds: TimeInterval = 0
//        var currentBPM: Float64 = tempoEvents[0].bpm
//        var lastTimestamp: MusicTimeStamp = 0
//        
//        for event in tempoEvents {
//            // Calculate time for segment
//            let beatsInSegment = event.timestamp - lastTimestamp
//            let secondsInSegment = (beatsInSegment * 60.0) / currentBPM
//            totalSeconds += secondsInSegment
//            
//            // Update for next segment
//            currentBPM = event.bpm
//            lastTimestamp = event.timestamp
//        }
//        
//        // Add remaining time after last tempo change
//        let remainingBeats = beats - lastTimestamp
//        let remainingSeconds = (remainingBeats * 60.0) / currentBPM
//        totalSeconds += remainingSeconds
//        
//        return totalSeconds
//    }
//    
//    private func calculateRealDuration(sequence: MusicSequence, beats: MusicTimeStamp) -> TimeInterval {
//        // Get tempo track
//        var tempoTrack: MusicTrack?
//        MusicSequenceGetTempoTrack(sequence, &tempoTrack)
//        
//        guard let tempoTrack = tempoTrack else {
//            // Default: 120 BPM = 2 beats per second
//            return beats / 2.0
//        }
//        
//        // Iterate through tempo events to calculate actual duration
//        var iterator: MusicEventIterator?
//        NewMusicEventIterator(tempoTrack, &iterator)
//        guard let iterator = iterator else {
//            return beats / 2.0
//        }
//        
//        var currentTime: MusicTimeStamp = 0
//        var currentTempo: Float64 = 120.0 // Default BPM
//        var totalSeconds: TimeInterval = 0
//        
//        var hasEvent: DarwinBoolean = false
//        MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
//        
//        while hasEvent.boolValue {
//            var timestamp: MusicTimeStamp = 0
//            var eventType: MusicEventType = 0
//            var eventData: UnsafeRawPointer?
//            var eventDataSize: UInt32 = 0
//            
//            MusicEventIteratorGetEventInfo(iterator, &timestamp, &eventType, &eventData, &eventDataSize)
//            
//            if eventType == kMusicEventType_ExtendedTempo {
//                // Calculate time elapsed since last tempo change
//                let beatsSinceLastChange = timestamp - currentTime
//                let beatsPerSecond = currentTempo / 60.0
//                totalSeconds += beatsSinceLastChange / beatsPerSecond
//                
//                // Update tempo
//                if let data = eventData {
//                    let tempoValue = data.load(as: ExtendedTempoEvent.self)
//                    currentTempo = tempoValue.bpm
//                }
//                
//                currentTime = timestamp
//            }
//            
//            MusicEventIteratorNextEvent(iterator)
//            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
//        }
//        
//        // Add remaining time after last tempo change
//        let remainingBeats = beats - currentTime
//        let beatsPerSecond = currentTempo / 60.0
//        totalSeconds += remainingBeats / beatsPerSecond
//        
//        DisposeMusicEventIterator(iterator)
//        
//        return totalSeconds
//    }
//    
//    private func formatDuration(_ seconds: TimeInterval) -> String {
//        let minutes = Int(seconds) / 60
//        let secs = Int(seconds) % 60
//        return String(format: "%d:%02d", minutes, secs)
//    }
//    
//    private func getChannelsInTrack(_ track: MusicTrack) -> Set<Int> {
//        var channels = Set<Int>()
//        var iterator: MusicEventIterator?
//        
//        NewMusicEventIterator(track, &iterator)
//        guard let iterator = iterator else { return channels }
//        
//        var hasEvent: DarwinBoolean = false
//        MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
//        
//        while hasEvent.boolValue {
//            var timestamp: MusicTimeStamp = 0
//            var eventType: MusicEventType = 0
//            var eventData: UnsafeRawPointer?
//            var eventDataSize: UInt32 = 0
//            
//            MusicEventIteratorGetEventInfo(iterator, &timestamp, &eventType, &eventData, &eventDataSize)
//            
//            if eventType == kMusicEventType_MIDIChannelMessage {
//                if let data = eventData {
//                    let message = data.load(as: MIDIChannelMessage.self)
//                    let channel = Int(message.status & 0x0F)
//                    channels.insert(channel)
//                }
//            }
//            
//            MusicEventIteratorNextEvent(iterator)
//            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
//        }
//        
//        DisposeMusicEventIterator(iterator)
//        return channels
//    }
//    
//    private func getEventCount(_ track: MusicTrack) -> Int {
//        var count = 0
//        var iterator: MusicEventIterator?
//        
//        NewMusicEventIterator(track, &iterator)
//        guard let iterator = iterator else { return 0 }
//        
//        var hasEvent: DarwinBoolean = false
//        MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
//        
//        while hasEvent.boolValue {
//            count += 1
//            MusicEventIteratorNextEvent(iterator)
//            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
//        }
//        
//        DisposeMusicEventIterator(iterator)
//        return count
//    }
//    
//    func toggleMute(trackIndex: Int) {
//        guard trackIndex < tracks.count else { return }
//        tracks[trackIndex].isMuted.toggle()
//        
//        if tracks[trackIndex].isMuted {
//            for channel in tracks[trackIndex].channels {
//                if channel < channels.count {
//                    channels[channel].allNotesOff()
//                }
//            }
//        }
//    }
//    
//    func toggleSolo(trackIndex: Int) {
//        guard trackIndex < tracks.count else { return }
//        tracks[trackIndex].isSolo.toggle()
//        
//        if tracks[trackIndex].isSolo {
//            for (index, track) in tracks.enumerated() {
//                if index != trackIndex && !track.isSolo {
//                    for channel in track.channels {
//                        if channel < channels.count {
//                            channels[channel].allNotesOff()
//                        }
//                    }
//                }
//            }
//        }
//    }
//    
//    func unsoloAll() {
//        for i in 0..<tracks.count {
//            tracks[i].isSolo = false
//        }
//    }
//    
//    func play() {
//        guard let player = musicPlayer else { return }
//        
//        MusicPlayerStart(player)
//        MusicPlayerSetPlayRateScalar(player, tempo)
//        
//        DispatchQueue.main.async {
//            self.isPlaying = true
//        }
//    }
//    
//    func pause() {
//        guard let player = musicPlayer else { return }
//        
//        MusicPlayerStop(player)
//        DispatchQueue.main.async {
//            self.isPlaying = false
//        }
//    }
//    
//    func stop() {
//        guard let player = musicPlayer else { return }
//        
//        MusicPlayerStop(player)
//        MusicPlayerSetTime(player, 0)
//        
//        for channel in channels {
//            channel.allNotesOff()
//        }
//        
//        DispatchQueue.main.async {
//            self.isPlaying = false
//            self.currentTime = 0
//        }
//    }
//    
//    func seek(to time: Double) {
//        guard let player = musicPlayer else { return }
//        
//        MusicPlayerSetTime(player, time)
//        
//        let currentSeconds = convertBeatsToSeconds(beats: time)
//        DispatchQueue.main.async {
//            self.currentTime = currentSeconds
//        }
//    }
//    
//    func convertSecondToBeats(seconds: TimeInterval) -> MusicTimeStamp {
//        // Simplified conversion - for seeking we use approximate conversion
//        // This could be improved by doing reverse tempo calculation
//        guard totalTimeInSeconds > 0 else { return seconds * 2.0 }
//        
//        let ratio = seconds / totalTimeInSeconds
//        return ratio * totalTime
//    }
//    
//    func setTempo(_ newTempo: Double) {
//        tempo = max(0.5, min(2.0, newTempo))
//        if let player = musicPlayer, isPlaying {
//            MusicPlayerSetPlayRateScalar(player, tempo)
//        }
//    }
//    
//    func setLoopPoints(start: Double, end: Double) {
//        loopStart = start
//        loopEnd = end
//        loopEnabled = true
//    }
//    
//    private func setupDisplayLink() {
//        displayLink = CADisplayLink(target: self, selector: #selector(updatePlaybackPosition))
//        displayLink?.add(to: .main, forMode: .common)
//    }
//    
//    @objc private func updatePlaybackPosition() {
//        guard let player = musicPlayer, isPlaying else { return }
//        
//        var time: MusicTimeStamp = 0
//        MusicPlayerGetTime(player, &time)
//        
//        let beatsPerSecond = 2.0 * tempo
//        let currentBeat = Int(time * beatsPerSecond)
//        if currentBeat != lastBeat {
//            lastBeat = currentBeat
//            metronome.tick(beat: currentBeat)
//        }
//        
//        // Convert beats to seconds for display
//        let currentSeconds = convertBeatsToSeconds(beats: time)
//        
//        DispatchQueue.main.async {
//            self.currentTime = currentSeconds  // Display time in seconds
//            
//            if self.loopEnabled && time >= self.loopEnd {
//                self.seek(to: self.loopStart)
//            } else if time >= self.totalTime {
//                self.stop()
//            }
//        }
//    }
//    
//    private func convertBeatsToSeconds(beats: MusicTimeStamp) -> TimeInterval {
//        guard let sequence = musicSequence else { return beats / 2.0 }
//        
//        // Use cached calculation if available
//        if totalTimeInSeconds > 0 && totalTime > 0 {
//            // Simple ratio calculation for performance
//            let ratio = beats / totalTime
//            return ratio * totalTimeInSeconds
//        }
//        
//        // Fallback to default tempo
//        return beats / 2.0
//    }
//    
//    deinit {
//        displayLink?.invalidate()
//        stopDeviceScanning()
//        stop()
//        
//        if let player = musicPlayer {
//            DisposeMusicPlayer(player)
//        }
//        if let sequence = musicSequence {
//            DisposeMusicSequence(sequence)
//        }
//        
//        for channel in channels {
//            channel.stop()
//        }
//    }
//}
//
//// MARK: - SwiftUI Views
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
//                        Text(formatTime(midiManager.totalTimeInSeconds))
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
//
//struct MIDIDeviceView: View {
//    @ObservedObject var midiManager: MIDIManager
//    @Environment(\.dismiss) private var dismiss
//    
//    var body: some View {
//        NavigationView {
//            List {
//                scanningSection
//                bluetoothOptionsSection
//                inputDevicesSection
//                outputDevicesSection
//                optionsSection
//                refreshSection
//            }
//            .navigationTitle("MIDI Devices")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button("Done") {
//                        dismiss()
//                    }
//                }
//            }
//        }
//    }
//    
//    private var scanningSection: some View {
//        Section {
//            HStack {
//                if midiManager.isSearchingDevices {
//                    ProgressView()
//                        .padding(.trailing, 8)
//                    Text("Searching for devices...")
//                } else {
//                    Text("Device scanning stopped")
//                }
//                
//                Spacer()
//                
//                Button(midiManager.isSearchingDevices ? "Stop" : "Start Scan") {
//                    if midiManager.isSearchingDevices {
//                        midiManager.stopDeviceScanning()
//                    } else {
//                        midiManager.startDeviceScanning()
//                    }
//                }
//                .buttonStyle(.bordered)
//            }
//        }
//    }
//    
//    private var bluetoothOptionsSection: some View {
//        Section {
//            Toggle("Auto-connect Bluetooth Output", isOn: $midiManager.autoConnectBluetooth)
//                .onChange(of: midiManager.autoConnectBluetooth) { newValue in
//                    if newValue {
//                        midiManager.autoConnectFirstBluetoothOutput()
//                    }
//                }
//            
//            if !midiManager.availableOutputDevices.filter({ midiManager.isBluetoothDevice($0.name) }).isEmpty {
//                Button("Connect All Bluetooth Outputs") {
//                    midiManager.connectToAllBluetoothOutputs()
//                }
//            }
//        } header: {
//            Text("Bluetooth Options")
//        }
//    }
//    
//    private var inputDevicesSection: some View {
//        Section("Input Devices (MIDI IN)") {
//            if midiManager.availableInputDevices.isEmpty {
//                emptyDeviceRow
//            } else {
//                ForEach(midiManager.availableInputDevices) { device in
//                    inputDeviceRow(device)
//                }
//            }
//        }
//    }
//    
//    private var outputDevicesSection: some View {
//        Section("Output Devices (MIDI OUT)") {
//            if midiManager.availableOutputDevices.isEmpty {
//                emptyDeviceRow
//            } else {
//                ForEach(midiManager.availableOutputDevices) { device in
//                    outputDeviceRow(device)
//                }
//            }
//        }
//    }
//    
//    private var emptyDeviceRow: some View {
//        HStack {
//            Text("No devices found")
//                .foregroundColor(.secondary)
//            Spacer()
//            if midiManager.isSearchingDevices {
//                ProgressView()
//            }
//        }
//    }
//    
//    private func inputDeviceRow(_ device: MIDIDeviceInfo) -> some View {
//        HStack {
//            deviceIcon(device)
//            deviceInfo(device)
//            Spacer()
//            connectionIndicator(isConnected: midiManager.selectedInputDevice?.id == device.id)
//        }
//        .contentShape(Rectangle())
//        .onTapGesture {
//            toggleInputConnection(device)
//        }
//    }
//    
//    private func outputDeviceRow(_ device: MIDIDeviceInfo) -> some View {
//        HStack {
//            deviceIcon(device)
//            deviceInfo(device)
//            Spacer()
//            connectionIndicator(isConnected: midiManager.selectedOutputDevice?.id == device.id)
//        }
//        .contentShape(Rectangle())
//        .onTapGesture {
//            toggleOutputConnection(device)
//        }
//    }
//    
//    private func deviceIcon(_ device: MIDIDeviceInfo) -> some View {
//        Group {
//            if midiManager.isBluetoothDevice(device.name) {
//                Image(systemName: "wifi")
//                    .foregroundColor(.blue)
//            } else {
//                Image(systemName: "cable.connector")
//            }
//        }
//    }
//    
//    private func deviceInfo(_ device: MIDIDeviceInfo) -> some View {
//        VStack(alignment: .leading) {
//            Text(device.name)
//            if midiManager.isBluetoothDevice(device.name) {
//                Text("Bluetooth")
//                    .font(.caption)
//                    .foregroundColor(.blue)
//            }
//        }
//    }
//    
//    private func connectionIndicator(isConnected: Bool) -> some View {
//        Group {
//            if isConnected {
//                Image(systemName: "checkmark.circle.fill")
//                    .foregroundColor(.green)
//            }
//        }
//    }
//    
//    private func toggleInputConnection(_ device: MIDIDeviceInfo) {
//        if midiManager.selectedInputDevice?.id == device.id {
//            midiManager.disconnectInputDevice()
//        } else {
//            midiManager.connectInputDevice(device)
//        }
//    }
//    
//    private func toggleOutputConnection(_ device: MIDIDeviceInfo) {
//        if midiManager.selectedOutputDevice?.id == device.id {
//            midiManager.disconnectOutputDevice()
//        } else {
//            midiManager.connectOutputDevice(device)
//        }
//    }
//    
//    private var optionsSection: some View {
//        Section("Options") {
//            Toggle("MIDI Through", isOn: $midiManager.midiThrough)
//        }
//    }
//    
//    private var refreshSection: some View {
//        Section {
//            Button("Refresh Devices Now") {
//                midiManager.scanMIDIDevices()
//            }
//        }
//    }
//}
//
//struct MIDILearnView: View {
//    @ObservedObject var midiManager: MIDIManager
//    @Environment(\.dismiss) private var dismiss
//    
//    var body: some View {
//        NavigationView {
//            List {
//                Section("Learn MIDI Controls") {
//                    ForEach(MIDILearnAction.allCases, id: \.self) { action in
//                        HStack {
//                            Text(action.rawValue)
//                            
//                            Spacer()
//                            
//                            if let mapping = getMappingFor(action) {
//                                Text("CC\(mapping.cc) Ch\(mapping.channel + 1)")
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                                
//                                Button(action: {
//                                    midiManager.clearMIDIMapping(mapping)
//                                }) {
//                                    Image(systemName: "xmark.circle.fill")
//                                        .foregroundColor(.red)
//                                }
//                            } else {
//                                Button("Learn") {
//                                    midiManager.startMIDILearn(for: action)
//                                }
//                                .buttonStyle(.bordered)
//                            }
//                        }
//                    }
//                }
//                
//                if midiManager.isLearningMIDI {
//                    Section {
//                        HStack {
//                            Spacer()
//                            VStack(spacing: 10) {
//                                ProgressView()
//                                Text("Move a control on your MIDI device...")
//                                    .font(.caption)
//                                Button("Cancel") {
//                                    midiManager.cancelMIDILearn()
//                                }
//                                .buttonStyle(.bordered)
//                            }
//                            Spacer()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .navigationTitle("MIDI Learn")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button("Done") {
//                        dismiss()
//                    }
//                }
//            }
//        }
//    }
//    
//    private func getMappingFor(_ action: MIDILearnAction) -> MIDIMapping? {
//        midiManager.midiMappings.values.first { $0.action == action.rawValue }
//    }
//}
//
//struct TrackRow: View {
//    let track: TrackInfo
//    let channels: [AudioChannel]
//    let onToggleMute: () -> Void
//    let onToggleSolo: () -> Void
//    
//    var isAnyChannelActive: Bool {
//        track.channels.contains { channelIndex in
//            channelIndex < channels.count && channels[channelIndex].isActive
//        }
//    }
//    
//    var channelList: String {
//        let sortedChannels = track.channels.sorted()
//        return sortedChannels.map { "Ch\($0 + 1)" }.joined(separator: ", ")
//    }
//    
//    var body: some View {
//        HStack(spacing: 12) {
//            Circle()
//                .fill(isAnyChannelActive ? Color.green : Color.gray)
//                .frame(width: 12, height: 12)
//            
//            VStack(alignment: .leading, spacing: 4) {
//                Text(track.name)
//                    .font(.subheadline)
//                    .fontWeight(.medium)
//                
//                HStack {
//                    Text(channelList)
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    
//                    Text("•")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                    
//                    Text("\(track.eventCount) events")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                }
//            }
//            
//            Spacer()
//            
//            Button(action: onToggleSolo) {
//                Text("S")
//                    .font(.caption)
//                    .fontWeight(.bold)
//                    .frame(width: 28, height: 28)
//                    .background(track.isSolo ? Color.orange : Color.gray.opacity(0.3))
//                    .foregroundColor(track.isSolo ? .white : .gray)
//                    .clipShape(Circle())
//            }
//            
//            Button(action: onToggleMute) {
//                Text("M")
//                    .font(.caption)
//                    .fontWeight(.bold)
//                    .frame(width: 28, height: 28)
//                    .background(track.isMuted ? Color.red : Color.gray.opacity(0.3))
//                    .foregroundColor(track.isMuted ? .white : .gray)
//                    .clipShape(Circle())
//            }
//        }
//        .padding()
//        .background(
//            RoundedRectangle(cornerRadius: 10)
//                .fill(Color(UIColor.secondarySystemBackground))
//        )
//        .opacity(track.isMuted ? 0.5 : 1.0)
//    }
//}
//
//struct MIDIFilePicker: UIViewControllerRepresentable {
//    let midiManager: MIDIManager
//    @Environment(\.dismiss) private var dismiss
//    
//    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
//        let picker = UIDocumentPickerViewController(
//            forOpeningContentTypes: [UTType(filenameExtension: "mid")!],
//            asCopy: true
//        )
//        picker.delegate = context.coordinator
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
//        let parent: MIDIFilePicker
//        
//        init(_ parent: MIDIFilePicker) {
//            self.parent = parent
//        }
//        
//        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
//            guard let url = urls.first else { return }
//            
//            let accessing = url.startAccessingSecurityScopedResource()
//            defer {
//                if accessing {
//                    url.stopAccessingSecurityScopedResource()
//                }
//            }
//            
//            parent.midiManager.loadMIDIFile(url: url)
//            parent.dismiss()
//        }
//    }
//}
//
