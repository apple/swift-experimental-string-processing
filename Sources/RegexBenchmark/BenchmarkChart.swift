//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if os(macOS)

import Charts
import SwiftUI

struct BenchmarkChart: View {
  struct Comparison: Identifiable {
    var id = UUID()
    var name: String
    var baseline: BenchmarkResult
    var latest: BenchmarkResult
  }

  var comparisons: [Comparison]

  var body: some View {
    VStack(alignment: .leading) {
      ForEach(comparisons) { comparison in
        let new = comparison.latest.median.seconds
        let old = comparison.baseline.median.seconds
        Chart {
          chartBody(
            name: comparison.name,
            new: new,
            old: old,
            sampleCount: comparison.latest.samples)
        }
        .chartXAxis {
          AxisMarks { value in
            AxisTick()
            AxisValueLabel {
              Text(String(format: "%.5fs", value.as(Double.self)!))
            }
          }
        }
        .chartYAxis {
          AxisMarks { value in
            AxisGridLine()
            AxisValueLabel {
              HStack {
                Text(value.as(String.self)!)
                let delta = (new - old) / old * 100
                Text(String(format: "%+.2f%%", delta))
                  .foregroundColor(delta <= 0 ? .green : .yellow)
              }
            }
          }
        }
        .frame(idealHeight: 60)
      }
    }
  }

  @ChartContentBuilder
  func chartBody(
    name: String,
    new: TimeInterval,
    old: TimeInterval,
    sampleCount: Int
  ) -> some ChartContent {
    // Baseline bar
    BarMark(
      x: .value("Time", old),
      y: .value("Name", "\(name) (\(sampleCount) samples)"))
    .position(by: .value("Kind", "Baseline"))
    .foregroundStyle(.gray)

    // Latest result bar
    BarMark(
      x: .value("Time", new),
      y: .value("Name", "\(name) (\(sampleCount) samples)"))
    .position(by: .value("Kind", "Latest"))
    .foregroundStyle(LinearGradient(
      colors: [.accentColor, new - old <= 0 ? .green : .yellow],
      startPoint: .leading,
      endPoint: .trailing))

    // Comparison
    RuleMark(x: .value("Time", new))
    .foregroundStyle(.gray)
    .lineStyle(.init(lineWidth: 0.5, dash: [2]))
  }
}

struct BenchmarkResultApp: App {
  static var comparisons: [BenchmarkChart.Comparison]?

  var body: some Scene {
    WindowGroup {
      if let comparisons = Self.comparisons {
        ScrollView {
          BenchmarkChart(comparisons: comparisons)
        }
      } else {
        Text("No data")
      }
    }
  }
}

#endif
