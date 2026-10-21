//
//  MoodRingLockWidget.swift
//  MoodRingWidget
//
//  iOS 16+ ロック画面 / 常時表示 (AOD) 用 Accessory Widget。
//  claude_conv.md §4 — Inline 257x26 / Circular 76x76 / Rectangular 172x76 をカバー。
//

import WidgetKit
import SwiftUI

@available(iOS 16.0, *)
struct MoodRingLockWidget: Widget {
    let kind: String = "MoodRingLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodRingProvider()) { entry in
            if #available(iOS 17.0, *) {
                MoodRingLockWidgetView(entry: entry)
                    .containerBackground(for: .widget) { Color.clear }
            } else {
                MoodRingLockWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("MRI ロック画面")
        .description("ロック画面で現在の体感を確認。")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

@available(iOS 16.0, *)
struct MoodRingLockWidgetView: View {
    let entry: MoodRingEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryInline:
            // 1 行テキスト (時計の下に表示される)
            Text("MRI \(entry.mriValue) · \(entry.mriBandLabel)")
        case .accessoryCircular:
            // 76x76 の円形 (時刻横の小さな枠)
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("MRI")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(entry.mriValue)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        case .accessoryRectangular:
            // 172x76 の長方形
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: Double(entry.mriValue) / 100.0)
                        .stroke(Color.white,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(entry.mriValue)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("MRI · \(entry.mriBandLabel)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                    if let t = entry.temperature {
                        Text("\(Int(t.rounded()))°  \(entry.location ?? "")")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            Text("MRI \(entry.mriValue)")
        }
    }
}
