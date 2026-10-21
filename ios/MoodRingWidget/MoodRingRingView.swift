//
//  MoodRingRingView.swift
//  MoodRingWidget
//
//  MRI スコア帯に応じて HSL グラデーションを描く円リング。
//  Figma の Glassmorphism リング (claude_conv.md §4) を SwiftUI で近似実装。
//

import SwiftUI

struct MoodRingRingView: View {
    let value: Int
    let hue: Double
    let label: String

    /// 0-100 の MRI 値 → 0.0-1.0 の進捗
    private var progress: Double {
        Double(max(0, min(100, value))) / 100.0
    }

    private var primary: Color {
        Color(hue: hue / 360.0, saturation: 0.65, brightness: 0.85)
    }

    private var secondary: Color {
        Color(hue: ((hue + 40).truncatingRemainder(dividingBy: 360)) / 360.0,
              saturation: 0.55, brightness: 0.95)
    }

    var body: some View {
        ZStack {
            // 背景リング (低コントラスト)
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 8)

            // 進捗リング (AngularGradient)
            Circle()
                .trim(from: 0.0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [primary, secondary, primary]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: primary.opacity(0.45), radius: 6)

            // 中央テキスト
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(4)
        }
    }
}
