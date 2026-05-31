# BeatZone — Architecture

## Overview

BeatZone is a SwiftUI iOS app built around a single `ObservableObject` ViewModel (`ExerciseViewModel`) that owns all runtime state. Views are thin and purely reactive. `AudioService` is protocol-backed for testability; `BLEHeartRateService` and `HealthKitService` are concrete classes injected directly.

---

## Module Diagram

```mermaid
graph TD
    subgraph Views
        CV[ContentView\nstate router]
        SV[SplashView]
        STB[StandbyView\nconfigure & start]
        EV[ExerciseView\nlive metrics]
        PV[PausedView\npause controls]
        STAV[StartingView\nloading]
    end

    subgraph ViewModel
        VM[ExerciseViewModel\nAppState · HR · Timers · Settings]
    end

    subgraph Services
        BLE[BLEHeartRateService\nBluetooth LE — scans from init]
        HK[HealthKitService\nApple Health]
        AUD[AudioService\nAVSpeechSynthesizer\nprotocol-backed]
        WM[WorkoutManager\nidle timer]
    end

    subgraph UI_Components
        HRS[HRRangeSlider]
        MR[MetricRow]
        HZB[HRZoneBar\nprivate in ExerciseView]
    end

    subgraph Storage
        UD[UserDefaults\nminHR · maxHR\nspeakInterval · summaryInterval]
    end

    CV -->|appState| SV
    CV -->|appState| STB
    CV -->|appState| EV
    CV -->|appState| PV
    CV -->|appState| STAV

    STB --> VM
    EV --> VM
    PV --> VM

    STB --> HRS
    EV --> MR
    EV --> HZB
    PV --> MR

    VM --> BLE
    VM --> HK
    VM --> AUD
    VM --> WM
    VM --> UD

    BLE -->|onHR callback| VM
    BLE -->|onStateChange| VM
    HK -->|HR + date| VM
```

---

## Data Flow

### Heart Rate

```mermaid
sequenceDiagram
    participant BLE as BLEHeartRateService
    participant HK as HealthKitService
    participant VM as ExerciseViewModel
    participant AUD as AudioService
    participant EV as ExerciseView

    Note over BLE,VM: BLE scanning starts at VM init, before standby
    BLE-->>VM: onHR(bpm) [priority source]
    HK-->>VM: startObservingHeartRate(bpm, date) [fallback — only if no BLE]
    Note over HK,VM: HK observers remain active while paused; only timers stop
    VM->>VM: handleNewHRSample(bpm, source)
    VM->>VM: checkZoneBreaches()
    VM->>AUD: speak("Maximum/Minimum heart rate reached") [if zone breached]
    VM-->>EV: @Published currentHR / totalAvgHR / hrSource
```

### Announcements

```mermaid
sequenceDiagram
    participant CT as clockTimer (1s)
    participant ST as speakTimer
    participant SUT as summaryTimer
    participant VM as ExerciseViewModel
    participant AUD as AudioService

    CT-->>VM: elapsedSeconds++ / secondsSinceLastHR++

    ST-->>VM: onSpeakTick() every speakInterval
    VM->>AUD: speak("Current X B.P.M.")

    SUT-->>VM: onSummaryTick() every summaryInterval
    VM->>AUD: speak("Current X B.P.M. Total average Y B.P.M.")
    VM->>ST: invalidate + restart speakTimer (prevents back-to-back)

    Note over VM,AUD: pauseExercise() stops all timers and calls announceMetrics(includeTotal: true)
```

### Audio Session

```mermaid
sequenceDiagram
    participant VM as ExerciseViewModel
    participant AUD as AudioService
    participant iOS as iOS Audio Session
    participant OA as Other Audio (music/podcast)

    Note over VM,AUD: Exercise starts — silent loop begins
    VM->>AUD: startSilentLoop()
    AUD->>iOS: setCategory(.playback, options: [.mixWithOthers, .duckOthers])
    AUD->>AUD: play silent buffer on loop (keeps session alive in background)

    Note over VM,AUD: Each announcement
    VM->>AUD: speak(text)
    AUD->>AUD: activeSpeechCount += 1
    AUD->>iOS: reactivateSession() — .playback + [.mixWithOthers, .duckOthers]
    iOS->>OA: lower volume
    AUD->>AUD: synthesizer.speak(utterance)

    Note over AUD: If a new utterance interrupts, count increments before stop.\ndidCancel fires for interrupted utterance, count decrements.\nDucking only releases when activeSpeechCount reaches 0.

    AUD->>AUD: didFinish / didCancel — activeSpeechCount -= 1
    AUD->>iOS: releaseDucking() — .playback + [.mixWithOthers] only [if count == 0]
    iOS->>OA: restore volume
```

---

## App State Machine

```mermaid
stateDiagram-v2
    [*] --> launching
    launching --> standby : 1.5s init delay
    standby --> starting : startExercise()
    starting --> exercising : HealthKit auth callback completes\n(auth optional — timers start regardless)
    exercising --> paused : pauseExercise()
    paused --> exercising : continueExercise()
    paused --> standby : endExercise()
```

> **Note on `starting → exercising`:** `startExercise()` sets `.starting` immediately, then waits 150ms before calling `requestHealthKitAndBegin()`. The transition to `.exercising` happens inside the HealthKit auth callback — whether or not permission was granted. HealthKit observation is only registered if permission was granted. The duration of `.starting` is unpredictable as it includes any system auth UI shown to the user.

---

## File Reference

All source files live under `HeartInterval/HeartInterval/`.

| File | Role |
|---|---|
| `ContentView.swift` | Root view — creates `@StateObject ExerciseViewModel` and routes to the correct view based on `appState` |
| `ExerciseViewModel.swift` | All runtime state, timers, HR logic, announcement settings |
| `ExerciseView.swift` | Live exercise screen — progress ring, BPM display, zone bar (`HRZoneBar` is a private struct here) |
| `StandbyView.swift` | Setup screen — zone slider, speak/summary interval pickers |
| `PausedView.swift` | Pause screen — frozen metrics, end/continue buttons |
| `SplashView.swift` | Animated launch screen |
| `StartingView.swift` | Loading indicator shown during exercise start and HealthKit auth |
| `BLEHeartRateService.swift` | Scans and connects to BLE HR monitors; scanning starts at VM init |
| `HealthKitService.swift` | Reads HR from Apple Health / Apple Watch; observer query + 5s polling fallback |
| `AudioService.swift` | TTS announcements with audio session ducking; `AudioServiceProtocol` enables test injection |
| `WorkoutManager.swift` | Suppresses idle timer during exercise |
| `HRRangeSlider.swift` | Custom dual-handle zone slider (80–180 bpm, 5 bpm steps) |
| `MetricRow.swift` | Reusable animated metric display component |
| `HeartIntervalApp.swift` | App entry point |

> Simulator builds include a mock HR timer (`#if targetEnvironment(simulator)`) in `ExerciseViewModel` that feeds synthetic BPM values so the exercise screen can be tested without a real HR monitor.

---

## Planned Additions

See [PLANNED_IMPROVEMENTS.md](PLANNED_IMPROVEMENTS.md) for the feature roadmap. Key architectural impacts:

- **Session History** — adds a persistence layer (likely a lightweight JSON store or CoreData)
- **HR Zone Time Tracking** — extends `ExerciseViewModel` with zone time counters
- **Rounds Timer** — adds a new timer type and round state to `ExerciseViewModel`; likely a new `RoundView`
- **GPS Tracking** — adds `LocationService` alongside `BLEHeartRateService` and `HealthKitService`; new `MapView` component
