import UniformTypeIdentifiers

extension UTType {
    static var sf2: UTType {
        UTType(filenameExtension: "sf2")!
    }
}

import Foundation
import CoreMIDI
import AudioToolbox
import MidiParser

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
        fluid_settings_setnum(settings, "synth.gain", 0.8)
        fluid_settings_setstr(settings, "synth.interpolation", "4")
        fluid_settings_setint(settings, "synth.polyphony", 256)
        
//        fluid_settings_setint(settings, "synth.reverb.active", 1)
//        fluid_settings_setnum(settings, "synth.reverb.room-size", 0.7)
//        fluid_settings_setnum(settings, "synth.reverb.damp", 0.5)
//        fluid_settings_setnum(settings, "synth.reverb.level", 0.3)
//
//        fluid_settings_setint(settings, "synth.chorus.active", 1)
//        fluid_settings_setnum(settings, "synth.chorus.level", 2.0)
//        fluid_settings_setnum(settings, "synth.chorus.depth", 6.0)
        
        fluid_settings_setint(settings, "synth.reverb.active", 0)
        fluid_settings_setint(settings, "synth.chorus.active", 0)

        
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
            if d2 == 0 {
                // Velocity 0 = Note Off
                fluid_synth_noteoff(synth, Int32(ch), Int32(d1))
            } else {
                let scaledVelocity = Int32(min(127, Int(Double(d2) * 1.25)))
                fluid_synth_noteon(synth, Int32(ch), Int32(d1), scaledVelocity)
            }
            
        case 0xB0: // Control Change
            handleCC(ch: ch, cc: Int(d1), value: Int(d2))
            
        case 0xC0: // Program Change
            program[ch] = Int(d1)
            applyBankAndProgram(ch)
            
        case 0xE0: // Pitch Bend
            let bend = (Int32(d2) << 7) | Int32(d1)  // raw 0–16383, center = 8192
               print("pitchbend: ch=\(ch) raw=\(bend) offset=\(bend - 8192)")
               fluid_synth_pitch_bend(synth, Int32(ch), bend)
            
        default:
            break
        }
    }
    
    // ===============================
    // MARK: CC / RPN HANDLING
    // ===============================
    private func handleCC(ch: Int, cc: Int, value: Int) {
        print("handle cc: ch =\(ch) and cc = \(cc) and value = \(value)")
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
                // 🔑 Reset RPN (SpessaSynth does this)
                    rpnMSB[ch] = 127
                    rpnLSB[ch] = 127
                    fluid_synth_cc(synth, Int32(ch), 101, 127)
                    fluid_synth_cc(synth, Int32(ch), 100, 127)
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
    
    func exportToWAV(soundFontUrl: URL?, midiURL: URL, outputURL: URL, progress: @escaping (Double) -> Void, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in

            guard let self = self else { return }

            guard let exportSettings = new_fluid_settings() else {
                completion(false); return
            }
            defer { delete_fluid_settings(exportSettings) }

            fluid_settings_setstr(exportSettings, "audio.driver", "file")
            fluid_settings_setstr(exportSettings, "audio.file.name", outputURL.path)
            fluid_settings_setstr(exportSettings, "audio.file.type", "wav")
            fluid_settings_setstr(exportSettings, "audio.file.format", "s16")
            fluid_settings_setnum(exportSettings, "synth.sample-rate", 44100)
            fluid_settings_setnum(exportSettings, "synth.gain", 0.8)
            fluid_settings_setint(exportSettings, "synth.reverb.active", 0)
            fluid_settings_setint(exportSettings, "synth.chorus.active", 0)
            fluid_settings_setint(exportSettings, "synth.polyphony", 256)
            fluid_settings_setint(exportSettings, "synth.lock-memory", 0)
            
            guard let exportSynth = new_fluid_synth(exportSettings) else {
                completion(false); return
            }
            defer { delete_fluid_synth(exportSynth) }
            
            guard let sfURL = soundFontUrl else {
                print("❌ No soundfont URL stored")
                completion(false); return
            }
            print("✅ SF2 path: \(sfURL.path)")

            let sfResult = fluid_synth_sfload(exportSynth, sfURL.path, 1)
            print("SF load result: \(sfResult)") // -1 = failed, >= 0 = success
            guard sfResult >= 0 else {
                print("❌ Soundfont failed to load")
                completion(false); return
            }

            guard let exportPlayer = new_fluid_player(exportSynth) else {
                completion(false); return
            }
            defer { delete_fluid_player(exportPlayer) }
            
            let playerAddResult = fluid_player_add(exportPlayer, midiURL.path)
            print("Player add result: \(playerAddResult)") // -1 = failed
            guard playerAddResult == 0 else {
                print("❌ MIDI file failed to load into player")
                completion(false); return
            }
            guard let renderer = new_fluid_file_renderer(exportSynth) else {
                print("❌ Failed to create file renderer")
                completion(false); return
            }
            defer { delete_fluid_file_renderer(renderer) }
            
            fluid_player_play(exportPlayer)
            print("▶️ Player started, status: \(fluid_player_get_status(exportPlayer))")
            // Check what was actually written
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                let path = outputURL.path.removingPercentEncoding ?? outputURL.path
                print("File exists: \(FileManager.default.fileExists(atPath: path))")
                print("File size after 1s: \(((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int) ?? 0)")
            }
            // Get total duration for progress tracking
            // We poll status until done
            var blockCount = 0
            let sampleRate = 44100
            let blockSize  = 64
            
            while fluid_player_get_status(exportPlayer) == 1 {
                if fluid_file_renderer_process_block(renderer) != 0 {
                    print("❌ Renderer block failed at block \(blockCount)")

                    break
                }
                blockCount += 1
                
                // Report progress every ~0.5 seconds worth of blocks
                if blockCount % (sampleRate / blockSize / 2) == 0 {
                    let secondsRendered = Double(blockCount * blockSize) / Double(sampleRate)
                    print("⏱ Rendered \(secondsRendered)s")

                    DispatchQueue.main.async {
                        progress(secondsRendered)
                    }
                }
            }
            print("✅ Render loop done, blocks: \(blockCount)")
            let finalPath = outputURL.path.removingPercentEncoding ?? outputURL.path
            let finalSize = ((try? FileManager.default.attributesOfItem(atPath: finalPath))?[.size] as? Int) ?? 0
            print("Final WAV size: \(finalSize) bytes")
            print("Final WAV path: \(finalPath)")

            
            // Render ~3 second tail for note release
            let tailBlocks = (sampleRate / blockSize) * 3
            for _ in 0..<tailBlocks {
                fluid_file_renderer_process_block(renderer)
            }
            self.addWAVHeader(to: outputURL)
            // Try reading first few bytes to check WAV header
            if let fileHandle = FileHandle(forReadingAtPath: finalPath) {
                let header = fileHandle.readData(ofLength: 4)
                fileHandle.closeFile()
                let headerStr = String(bytes: header, encoding: .ascii) ?? "unreadable"
                print("WAV header bytes: \(headerStr)") // should print "RIFF"
            }
            completion(true)
        }
    }
    
    private func addWAVHeader(to fileURL: URL, sampleRate: Int = 44100, channels: Int = 2, bitsPerSample: Int = 16) {
        guard let fileHandle = try? FileHandle(forUpdating: fileURL) else { return }
        defer { fileHandle.closeFile() }
        
        let dataSize = UInt32((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int ?? 0)
        let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        
        var header = Data()
        
        // RIFF chunk
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize + 36).littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })          // chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })           // PCM format
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })    // channels
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })  // sample rate
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })            // byte rate
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })          // block align
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) }) // bits per sample
        
        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        // Read existing raw PCM data
        let pcmData = fileHandle.readDataToEndOfFile()
        
        // Write header + PCM back to file
        fileHandle.seek(toFileOffset: 0)
        fileHandle.write(header)
        fileHandle.write(pcmData)
    }
    func gmResetChannel(_ ch: Int) {
        // Reset controllers
        fluid_synth_cc(synth, Int32(ch), 121, 0)

        // Volume (optional but recommended)
        fluid_synth_cc(synth, Int32(ch), 7, 127)

        // Pan center
        fluid_synth_cc(synth, Int32(ch), 10, 64)

        // Expression full
        fluid_synth_cc(synth, Int32(ch), 11, 127)

        // Reverb & chorus off
        fluid_synth_cc(synth, Int32(ch), 91, 0)
        fluid_synth_cc(synth, Int32(ch), 93, 0)

        // Pitch bend center
        fluid_synth_pitch_bend(synth, Int32(ch), 0)

        // Pitch bend range = 2 semitones
        fluid_synth_pitch_wheel_sens(synth, Int32(ch), 2)

        // Bank & program (GM)
        let bank: Int32 = (ch == 9) ? 128 : 0
        fluid_synth_bank_select(synth, Int32(ch), bank)
        fluid_synth_program_change(synth, Int32(ch), 0)
    }

    
    func systemReset() {
        fluid_synth_system_reset(synth)
    }
}

