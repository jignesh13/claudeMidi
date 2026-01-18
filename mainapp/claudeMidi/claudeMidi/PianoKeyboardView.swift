//
////  PianoKeyboardView.swift
////  claudeMidi
////
////  Created by macmini1 on 12/01/26.
////
//import SwiftUI
//import QuartzCore
//
//struct ActiveNote {
//    let note: Int
//    let velocity: Int
//    let startTime: TimeInterval
//}
//
//final class PianoState: ObservableObject {
//    @Published var activeNotes: [Int: ActiveNote] = [:]
//    @Published var history: [ActiveNote] = []
//
//    func clear() {
//        activeNotes.removeAll()
//        history.removeAll()
//    }
//}
//struct PianoKeyView: View {
//    let isBlack: Bool
//    let active: ActiveNote?
//
//
//
//    func velocityColor(_ velocity: Int) -> Color {
//        Color.blue.opacity(Double(velocity) / 127.0)
//    }
//
//    var body: some View {
//        Rectangle()
//            .fill(active != nil
//                  ? velocityColor(active!.velocity)
//                  : (isBlack ? .black : .white))
//            .frame(
//                width: isBlack ? 14 : 22,
//                height: isBlack ? 80 : 140
//            )
//            .scaleEffect(active != nil ? 1.05 : 1.0)
//            .animation(.easeOut(duration: 0.08), value: active != nil)
//            .border(Color.black.opacity(isBlack ? 0 : 0.3))
//    }
//}
//struct PianoKeyboardView: View {
//    @ObservedObject var piano: PianoState
//    private let notes = Array(21...108)
//
//    func isBlackKey(_ note: Int) -> Bool {
//        [1, 3, 6, 8, 10].contains(note % 12)
//    }
//    var body: some View {
//        ZStack(alignment: .topLeading) {
//
//            // White keys
//            HStack(spacing: 1) {
//                ForEach(notes.filter { !isBlackKey($0) }, id: \.self) { note in
//                    PianoKeyView(
//                        isBlack: false,
//                        active: piano.activeNotes[note]
//                    )
//                }
//            }
//
//            // Black keys
//            HStack(spacing: 1) {
//                ForEach(notes.filter { isBlackKey($0) }, id: \.self) { note in
//                    PianoKeyView(
//                        isBlack: true,
//                        active: piano.activeNotes[note]
//                    )
//                    .offset(x: blackKeyOffset(note))
//                }
//            }
//        }
//        .frame(height: 150)
//        .padding(.horizontal, 8)
//    }
//
//    private func blackKeyOffset(_ note: Int) -> CGFloat {
//        let index = note - 21
//        let octave = index / 12
//        let pos = index % 12
//
//        let map: [Int: CGFloat] = [
//            1: 16, 3: 40, 6: 78, 8: 102, 10: 126
//        ]
//        return CGFloat(octave * 154) + (map[pos] ?? 0)
//    }
//}
//
//struct PianoRollView: View {
//    @ObservedObject var piano: PianoState
//    let visibleDuration: TimeInterval = 4.0
//
//    func velocityColor(_ velocity: Int) -> Color {
//        Color.blue.opacity(Double(velocity) / 127.0)
//    }
//
//    var body: some View {
//        GeometryReader { geo in
//            Canvas { ctx, size in
//                let now = CACurrentMediaTime()
//
//                for note in piano.history {
//                    let age = now - note.startTime
//                    guard age < visibleDuration else { continue }
//
//                    let x = CGFloat(note.note - 21) / 88 * size.width
//                    let y = size.height - CGFloat(age / visibleDuration) * size.height
//
//                    let rect = CGRect(x: x, y: y, width: 6, height: 12)
//                    ctx.fill(Path(rect), with: .color(velocityColor(note.velocity)))
//                }
//            }
//        }
//        .frame(height: 120)
//        .background(Color.black.opacity(0.9))
//        .cornerRadius(10)
//        .padding(.horizontal, 16)
//    }
//}
