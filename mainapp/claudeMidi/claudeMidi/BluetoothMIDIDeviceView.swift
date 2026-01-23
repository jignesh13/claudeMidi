import SwiftUI
import CoreAudioKit

struct BluetoothMIDIDeviceView: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> CABTMIDICentralViewController {
        CABTMIDICentralViewController()
    }

    func updateUIViewController(
        _ uiViewController: CABTMIDICentralViewController,
        context: Context
    ) {
        // No updates needed
    }
}
