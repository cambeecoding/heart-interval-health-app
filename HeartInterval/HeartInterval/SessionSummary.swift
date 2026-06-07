import Foundation
import HealthKit

enum WorkoutActivityType: String, CaseIterable, Equatable {
    case run, cycle, rowing, hiit, skiing, other

    var hkType: HKWorkoutActivityType {
        switch self {
        case .run:    return .running
        case .cycle:  return .cycling
        case .rowing: return .rowing
        case .hiit:   return .highIntensityIntervalTraining
        case .skiing: return .crossCountrySkiing
        case .other:  return .other
        }
    }

    var label: String {
        switch self {
        case .run:    return "Run"
        case .cycle:  return "Cycle"
        case .rowing: return "Row"
        case .hiit:   return "HIIT"
        case .skiing: return "Ski"
        case .other:  return "Other"
        }
    }
}

struct HRSample: Equatable {
    let bpm: Double
    let date: Date
}

struct SessionSummary: Equatable {
    let startDate: Date
    let endDate: Date
    let durationSeconds: Int
    let samples: [HRSample]
    let minHR: Int
    let maxHR: Int
    let activityType: WorkoutActivityType

    var avgHR: Int? {
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0.0) { $0 + $1.bpm }
        return Int((total / Double(samples.count)).rounded())
    }

    var samplesInZone: Int { samples.filter { $0.bpm >= Double(minHR) && $0.bpm <= Double(maxHR) }.count }
    var samplesAbove:  Int { samples.filter { $0.bpm > Double(maxHR) }.count }
    var samplesBelow:  Int { samples.filter { $0.bpm < Double(minHR) }.count }

    var inZoneFraction: Double { samples.isEmpty ? 0 : Double(samplesInZone) / Double(samples.count) }
    var aboveFraction:  Double { samples.isEmpty ? 0 : Double(samplesAbove)  / Double(samples.count) }
    var belowFraction:  Double { samples.isEmpty ? 0 : Double(samplesBelow)  / Double(samples.count) }
}
