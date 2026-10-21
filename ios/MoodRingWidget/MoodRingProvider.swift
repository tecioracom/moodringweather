//
//  MoodRingProvider.swift
//  MoodRingWidget
//
//  WidgetKit の TimelineProvider。
//  App Group `group.com.teciora.moodringweather` の UserDefaults を読んで
//  MoodRingEntry を生成する。
//
//  更新頻度: 30 分ごとに timeline を返す。Flutter 側から push されたら
//  `WidgetCenter.shared.reloadAllTimelines()` (home_widget が呼ぶ) で即座に再描画される。
//

import WidgetKit
import SwiftUI

private let kAppGroupId = "group.com.teciora.moodringweather"

struct MoodRingProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoodRingEntry {
        MoodRingEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (MoodRingEntry) -> Void) {
        completion(readCurrentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoodRingEntry>) -> Void) {
        let entry = readCurrentEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        let timeline = Timeline(entries: [entry], policy: .after(next))
        completion(timeline)
    }

    private func readCurrentEntry() -> MoodRingEntry {
        guard let defaults = UserDefaults(suiteName: kAppGroupId) else {
            return .placeholder
        }
        // home_widget は flutter.<key> という prefix で書き込むのと、直接書く 2 つのパターンがある。
        // 0.7.x 系は flutter. プレフィックスなしで保存される (HomeWidget.saveWidgetData)。
        let mri = defaults.object(forKey: "mri_value") as? Int
            ?? defaults.object(forKey: "flutter.mri_value") as? Int
            ?? 64
        let band = defaults.string(forKey: "mri_band")
            ?? defaults.string(forKey: "flutter.mri_band")
            ?? "comfortable"
        let label = defaults.string(forKey: "mri_band_label")
            ?? defaults.string(forKey: "flutter.mri_band_label")
            ?? "COMFORTABLE"
        let hue = defaults.object(forKey: "mri_hue") as? Double
            ?? defaults.object(forKey: "flutter.mri_hue") as? Double
            ?? 120
        let temperature = defaults.object(forKey: "temperature") as? Double
            ?? defaults.object(forKey: "flutter.temperature") as? Double
        let apparent = defaults.object(forKey: "apparent_temperature") as? Double
            ?? defaults.object(forKey: "flutter.apparent_temperature") as? Double
        let condition = defaults.string(forKey: "condition")
            ?? defaults.string(forKey: "flutter.condition")
        let humidity = defaults.object(forKey: "humidity") as? Double
            ?? defaults.object(forKey: "flutter.humidity") as? Double
        let uv = defaults.object(forKey: "uv_index") as? Int
            ?? defaults.object(forKey: "flutter.uv_index") as? Int
        let location = defaults.string(forKey: "location")
            ?? defaults.string(forKey: "flutter.location")
        let updatedAtMs = defaults.object(forKey: "mri_updated_at") as? Int
            ?? defaults.object(forKey: "flutter.mri_updated_at") as? Int
            ?? Int(Date().timeIntervalSince1970 * 1000)
        let updatedAt = Date(timeIntervalSince1970: TimeInterval(updatedAtMs) / 1000)

        return MoodRingEntry(
            date: Date(),
            mriValue: mri,
            mriBand: band,
            mriBandLabel: label,
            mriHue: hue,
            temperature: temperature,
            apparentTemperature: apparent,
            condition: condition,
            humidity: humidity,
            uvIndex: uv,
            location: location,
            updatedAt: updatedAt
        )
    }
}
