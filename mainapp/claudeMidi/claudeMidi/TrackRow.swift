////
////  TrackRow.swift
////  claudeMidi
////
////  Created by macmini1 on 02/01/26.
////
//
//import SwiftUI
//
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
