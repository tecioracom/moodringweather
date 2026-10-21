//
//  MoodRingEntry.swift
//  MoodRingWidget
//
//  Timeline Provider が生成する 1 エントリ分のデータモデル。
//  Flutter 側 lib/services/home_widget_service.dart の `saveWidgetData` キーと整合。
//

import WidgetKit
import Foundation

struct MoodRingEntry: TimelineEntry {
    let date: Date
    let mriValue: Int          // 0-100
    let mriBand: String        // "hotWarning" | "hot" | "warm" | "comfortable" | "cool"
    let mriBandLabel: String   // "COMFORTABLE" 等
    let mriHue: Double         // 0-360 HSL hue
    let temperature: Double?   // °C
    let apparentTemperature: Double?
    let condition: String?
    let humidity: Double?
    let uvIndex: Int?
    let location: String?
    let updatedAt: Date

    static let placeholder = MoodRingEntry(
        date: Date(),
        mriValue: 64,
        mriBand: "comfortable",
        mriBandLabel: "COMFORTABLE",
        mriHue: 120,
        temperature: 19,
        apparentTemperature: 21,
        condition: "sunny",
        humidity: 55,
        uvIndex: 5,
        location: "Shibuya",
        updatedAt: Date()
    )
}
