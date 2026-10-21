//
//  MoodRingWidgetBundle.swift
//  MoodRingWidget
//
//  Mood-Ring Weather — iOS WidgetKit エントリ。
//  Home (Small/Medium) + Lock Screen (Inline/Circular/Rectangular) を登録。
//  v1.1 では Control Center / Live Activity は未使用。
//
//  データは App Group `group.com.teciora.moodringweather` 経由で
//  Flutter (home_widget パッケージ) と共有。
//

import WidgetKit
import SwiftUI

@main
struct MoodRingWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoodRingHomeWidget()
        if #available(iOS 16.0, *) {
            MoodRingLockWidget()
        }
    }
}
