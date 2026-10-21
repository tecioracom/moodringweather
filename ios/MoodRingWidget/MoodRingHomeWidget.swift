//
//  MoodRingHomeWidget.swift
//  MoodRingWidget
//
//  ホーム画面ウィジェット (Small / Medium)。
//  spec.md §15.2 v1.1 — iOS Home Small 170x170 / Medium 364x170。
//

import WidgetKit
import SwiftUI

struct MoodRingHomeWidget: Widget {
    let kind: String = "MoodRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodRingProvider()) { entry in
            if #available(iOS 17.0, *) {
                MoodRingHomeWidgetView(entry: entry)
                    .containerBackground(for: .widget) { backgroundGradient }
            } else {
                MoodRingHomeWidgetView(entry: entry)
                    .background(backgroundGradient)
            }
        }
        .configurationDisplayName("Mood-Ring Weather")
        .description("いまの体感(MRI)と気温をひと目で。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.12, blue: 0.22),
                Color(red: 0.04, green: 0.07, blue: 0.13)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct MoodRingHomeWidgetView: View {
    let entry: MoodRingEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
    }

    // MARK: - Small (170x170 想定)
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let location = entry.location {
                Text(location)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: 10) {
                MoodRingRingView(
                    value: entry.mriValue,
                    hue: entry.mriHue,
                    label: entry.mriBandLabel
                )
                .frame(width: 70, height: 70)

                VStack(alignment: .leading, spacing: 2) {
                    if let temp = entry.temperature {
                        Text("\(Int(temp.rounded()))°")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    if let apparent = entry.apparentTemperature {
                        Text("体感 \(Int(apparent.rounded()))°")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            Spacer(minLength: 0)
            Text(updatedLabel(entry.updatedAt))
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: - Medium (364x170 想定)
    private var mediumLayout: some View {
        HStack(spacing: 14) {
            MoodRingRingView(
                value: entry.mriValue,
                hue: entry.mriHue,
                label: entry.mriBandLabel
            )
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 6) {
                if let location = entry.location {
                    Text(location)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
                if let temp = entry.temperature {
                    Text("\(Int(temp.rounded()))°")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                HStack(spacing: 10) {
                    if let apparent = entry.apparentTemperature {
                        Label("体感 \(Int(apparent.rounded()))°",
                              systemImage: "thermometer.medium")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    if let humidity = entry.humidity {
                        Label("\(Int(humidity.rounded()))%",
                              systemImage: "drop.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    if let uv = entry.uvIndex, uv > 0 {
                        Label("UV \(uv)", systemImage: "sun.max")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                Text(updatedLabel(entry.updatedAt))
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
    }

    private func updatedLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "更新 \(fmt.string(from: date))"
    }
}
