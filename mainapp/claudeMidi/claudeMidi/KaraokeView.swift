import SwiftUI

// MARK: - Data Models
struct KaraokeWord: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

struct KaraokeLine: Identifiable {
    let id = UUID()
    let words: [KaraokeWord]
    
    var startTime: TimeInterval {
        words.first?.time ?? 0
    }
    
    var fullText: String {
        words.map { $0.text }.joined()
    }
}

enum MidiTextType {
    case karaoke
    case chords
    case none
}

import SwiftUI

struct KaraokeView: View {

    let lines: [KaraokeLine]
    let currentTime: TimeInterval


    var body: some View {
        ScrollViewReader { proxy in

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {

                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let isActive = index == activeIndex

                        KaraokeLineView(
                            line: line,
                            currentTime: currentTime
                        )
                        .id(line.id)
                        .opacity(isActive ? 1.0 : 0.40) // ⭐ cleaner karaoke look
                        .animation(.easeOut(duration: 0.25), value: isActive)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .onChange(of: activeLineID) { id in
                guard let id else { return }

                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Active Line Detection

    private var activeIndex: Int? {
        lines.lastIndex { currentTime >= $0.startTime }
    }

    private var activeLineID: UUID? {
        guard let index = activeIndex else { return nil }
        return lines[index].id
    }
}



struct KaraokeLineView: View {

    let line: KaraokeLine
    let currentTime: TimeInterval

    var body: some View {
        Text(attributedLine)
            .font(.system(size: 26, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .padding(.horizontal)
    }

    private var attributedLine: AttributedString {
        var result = AttributedString()

        for word in line.words {
            var part = AttributedString(word.text)

            if currentTime >= word.time {
                part.foregroundColor = .orange
            } else {
                part.foregroundColor = .secondary
            }

            result.append(part)
        }

        return result
    }
}

struct SingleLineKaraokeView: View {

    let words: [KaraokeWord]
    let currentTime: TimeInterval

    var body: some View {

        ScrollViewReader { proxy in

            ScrollView(.vertical, showsIndicators: false) {

                Text(attributedLine)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding()
                    .id("LINE")
            }
            .background(Color(uiColor: .systemGray6))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .onChange(of: activeWordIndex) { _ in
                scrollToActive(proxy)
            }
        }
    }

    // MARK: - Attributed Builder

    private var attributedLine: AttributedString {

        var result = AttributedString()

        for word in words {

            var part = AttributedString(word.text)

            if currentTime >= word.time {
                part.foregroundColor = .orange
            } else {
                part.foregroundColor = .secondary
            }

            result.append(part)
        }

        return result
    }

    // MARK: - Active Detection

    private var activeWordIndex: Int? {
        words.lastIndex { currentTime >= $0.time }
    }

    private func scrollToActive(_ proxy: ScrollViewProxy) {

        guard let index = activeWordIndex else { return }

        // Scroll roughly toward the active section
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo("LINE", anchor: .trailing)
        }
    }
}
