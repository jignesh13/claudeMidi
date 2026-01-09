////
////  MIDIDeviceView.swift
////  claudeMidi
////
////  Created by macmini1 on 02/01/26.
////
//
//import SwiftUI
//
//
//struct MIDIDeviceView: View {
//    @ObservedObject var midiManager: MIDIManager
//    @Environment(\.dismiss) private var dismiss
//    
//    var body: some View {
//        NavigationView {
//            deviceList
//                .navigationTitle("MIDI Devices")
//                .navigationBarTitleDisplayMode(.inline)
//                .toolbar {
//                    ToolbarItem(placement: .navigationBarTrailing) {
//                        Button("Done") { dismiss() }
//                    }
//                }
//        }
//    }
//    private var deviceList: some View {
//        List {
//            scanningSection
//            bluetoothOptionsSection
//            inputDevicesSection
//            outputDevicesSection
//            optionsSection
//            refreshSection
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
//                    midiManager.isSearchingDevices
//                        ? midiManager.stopDeviceScanning()
//                        : midiManager.startDeviceScanning()
//                }
//                .buttonStyle(.bordered)
//            }
//        }
//    }
//    private var bluetoothOptionsSection: some View {
//        Section("Bluetooth Options") {
//            Toggle(
//                "Auto-connect Bluetooth Output",
//                isOn: $midiManager.autoConnectBluetooth
//            )
//            .onChange(of: midiManager.autoConnectBluetooth) { enabled in
//                if enabled {
//                    midiManager.autoConnectFirstBluetoothOutput()
//                }
//            }
//
//            if hasBluetoothOutputs {
//                Button("Connect All Bluetooth Outputs") {
//                    midiManager.connectToAllBluetoothOutputs()
//                }
//            }
//        }
//    }
//
//    private var hasBluetoothOutputs: Bool {
//        midiManager.availableOutputDevices.contains {
//            midiManager.isBluetoothDevice($0.name)
//        }
//    }
//    private var inputDevicesSection: some View {
//        Section("Input Devices (MIDI IN)") {
//            if midiManager.availableInputDevices.isEmpty {
//                emptyDevicesRow
//            }
//
//            ForEach(midiManager.availableInputDevices) { device in
//                deviceRow(
//                    device: device,
//                    isSelected: midiManager.selectedInputDevice?.id == device.id
//                )
//                .onTapGesture {
//                    midiManager.selectedInputDevice?.id == device.id
//                        ? midiManager.disconnectInputDevice()
//                        : midiManager.connectInputDevice(device)
//                }
//            }
//        }
//    }
//    private var outputDevicesSection: some View {
//        Section("Output Devices (MIDI OUT)") {
//            if midiManager.availableOutputDevices.isEmpty {
//                emptyDevicesRow
//            }
//
//            ForEach(midiManager.availableOutputDevices) { device in
//                deviceRow(
//                    device: device,
//                    isSelected: midiManager.selectedOutputDevice?.id == device.id
//                )
//                .onTapGesture {
//                    midiManager.selectedOutputDevice?.id == device.id
//                        ? midiManager.disconnectOutputDevice()
//                        : midiManager.connectOutputDevice(device)
//                }
//            }
//        }
//    }
//    private func deviceRow(
//        device: MIDIDeviceInfo,
//        isSelected: Bool
//    ) -> some View {
//        HStack {
//            Image(systemName: midiManager.isBluetoothDevice(device.name) ? "wifi" : "cable.connector")
//                .foregroundColor(midiManager.isBluetoothDevice(device.name) ? .blue : .primary)
//
//            VStack(alignment: .leading) {
//                Text(device.name)
//                if midiManager.isBluetoothDevice(device.name) {
//                    Text("Bluetooth")
//                        .font(.caption)
//                        .foregroundColor(.blue)
//                }
//            }
//
//            Spacer()
//
//            if isSelected {
//                Image(systemName: "checkmark.circle.fill")
//                    .foregroundColor(.green)
//            }
//        }
//        .contentShape(Rectangle())
//    }
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
//
//    private var emptyDevicesRow: some View {
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
//
//}
