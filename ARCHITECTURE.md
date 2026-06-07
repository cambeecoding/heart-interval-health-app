# BeatZone — Architecture

## Overview

BeatZone is a SwiftUI iOS app built around a single `ObservableObject` ViewModel (`ExerciseViewModel`) that owns all runtime state. Views are thin and purely reactive. Services are protocol-backed for testability: `AudioServiceProtocol` and `HealthKitServicing` enable test-double injection. `BLEHeartRateService` is a concrete class (not protocol-backed) injected directly. `WorkoutManager` suppresses the idle timer during exercise.

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
        SUMV[SummaryView\npost-exercise]
    end

    subgraph ViewModel
        VM[ExerciseViewModel\nAppState · HR · Timers · Settings]
    end

    subgraph Services
        BLE[BLEHeartRateService\nBluetooth LE — dual-mode]
        HK[HealthKitService\nprotocol: HealthKitServicing]
        AUD[AudioService\nprotocol: AudioServiceProtocol]
        WM[WorkoutManager\nidle timer]
    end

    subgraph UI_Components
        HRS[HRRangeSlider]
        MR[MetricRow]
        SPD[HRSpeedometer\nprivate in ExerciseView]
        HRG[HRGraph\nprivate in SummaryView]
        ZDB[ZoneDistributionBar\nprivate in SummaryView]
    end

    subgraph Models
        SS[SessionSummary\nHRSample · WorkoutActivityType]
    end

    subgraph Storage
        UD[UserDefaults\nminHR · maxHR\nspeakInterval · summaryInterval\nworkoutActivityType]
    end

    CV -->|appState| SV
    CV -->|appState| STB
    CV -->|appState| EV
    CV -->|appState| PV
    CV -->|appState| STAV
    CV -->|appState| SUMV

    STB --> VM
    EV --> VM
    PV --> VM
    SUMV --> VM

    STB --> HRS
    EV --> MR
    EV --> SPD
    PV --> MR
    SUMV --> HRG
    SUMV --> ZDB

    VM --> BLE
    VM --> HK
    VM --> AUD
    VM --> WM
    VM --> UD
    VM --> SS

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

    Note over BLE,VM: BLE scanning starts at VM init (passive discovery mode)
    Note over BLE,VM: On startExercise(), BLE switches to active connection mode
    BLE-->>VM: onHR(bpm) [priority source]
    HK-->>VM: startObservingHeartRate(bpm, date) [fallback — only if hrSource != .ble]
    Note over HK,VM: HK observer query + 5s polling fallback (for Garmin batch writes)
    Note over HK,VM: since: anchor is backdated 10s to tolerate Watch clock skew
    Note over HK,VM: HK observers remain active while paused; only timers stop
    VM->>VM: handleNewHRSample(bpm, source, date)
    VM->>VM: checkZoneBreaches()
    VM->>AUD: speak("Maximum/Minimum heart rate reached") [if zone breached]
    VM-->>EV: @Published currentHR / totalAvgHR / hrSource
```

### HR Source Timeout

```mermaid
sequenceDiagram
    participant VM as ExerciseViewModel
    participant EV as ExerciseView

    Note over VM: Exercise starts → 20s noHRTimeoutTimer begins
    alt HR sample arrives within 20s
        VM->>VM: cancel noHRTimeoutTimer, hrSourceTimedOut = false
    else No HR after 20s
        VM->>VM: hrSourceTimedOut = true
        VM-->>EV: NoHRWarning panel with troubleshooting + Settings deep-link
    end
```

### Standby Liveness Polling

```mermaid
sequenceDiagram
    participant VM as ExerciseViewModel
    participant HK as HealthKitService
    participant STB as StandbyView

    Note over VM: Poll starts after splash delay (every 5s)
    VM->>HK: fetchRecentSample(within: 60s)
    HK-->>VM: Double? (bpm or nil)
    VM-->>STB: standbyWatchBPM (drives Watch status indicator)
    Note over VM: Poll stops on startExercise(), resumes on dismissSummary()
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

    Note over AUD: If a new utterance interrupts, count increments before stop.<br/>didCancel fires for interrupted utterance, count decrements.<br/>Ducking only releases when activeSpeechCount reaches 0.

    AUD->>AUD: didFinish / didCancel — activeSpeechCount -= 1
    AUD->>iOS: releaseDucking() — .playback + [.mixWithOthers] only [if count == 0]
    iOS->>OA: restore volume

    Note over VM,AUD: appDidBecomeActive reactivates silent loop if exercising/paused
```

### Session Summary & Workout Saving

```mermaid
sequenceDiagram
    participant VM as ExerciseViewModel
    participant HK as HealthKitService
    participant SUMV as SummaryView

    VM->>VM: endExercise() builds SessionSummary from allSamples
    VM-->>SUMV: .summary(SessionSummary) state
    SUMV-->>SUMV: HRGraph + ZoneDistributionBar render

    alt User taps "Save to Health"
        SUMV->>VM: saveAndDismiss(summary)
        VM->>HK: saveWorkout(summary)
        HK->>HK: HKWorkoutBuilder + HR samples → finishWorkout
        HK-->>VM: Result<Void, Error>
        alt Success
            VM->>VM: dismissSummary() → .standby
        else Failure
            VM-->>SUMV: summaryError displayed
        end
    else User taps "Dismiss"
        SUMV->>VM: dismissSummary() → .standby
    end
```

---

## App State Machine

```mermaid
stateDiagram-v2
    [*] --> launching
    launching --> standby : 1.5s init delay (BLE + HK init)
    standby --> starting : startExercise()
    starting --> exercising : HealthKit auth callback completes\n(auth optional — timers start regardless)
    exercising --> paused : pauseExercise()
    paused --> exercising : continueExercise()
    paused --> summary : endExercise()
    exercising --> summary : endExercise()
    summary --> standby : dismissSummary()
```

> **Note on `starting → exercising`:** `startExercise()` sets `.starting` immediately, then waits 150ms before calling `requestHealthKitAndBegin()`. The transition to `.exercising` happens inside the HealthKit auth callback — whether or not permission was granted. HealthKit observation is registered regardless of whether permission was actually granted (the `granted` parameter from HealthKit reflects whether the dialog was presented, not whether read access was allowed). The `since:` anchor is backdated by 10 seconds (`Date().addingTimeInterval(-10)`) to tolerate Apple Watch sample clock skew — preventing the "frozen 61 bpm" bug where valid initial samples were rejected, while still excluding genuinely stale pre-exercise samples.

---

## BLE Dual-Mode Architecture

`BLEHeartRateService` operates in two distinct modes:

| Mode | Triggered by | Behaviour |
|------|-------------|-----------|
| **Standby (passive discovery)** | `startScanning()` at VM init | Scans with `allowDuplicates` to surface nearby HR monitors. No connection attempted. Drives `bleSourceStatus` on the standby screen. |
| **Exercise (active connection)** | `start()` on exercise start | Connects to discovered or system-connected peripheral. Subscribes to HR characteristic (UUID 2A37). Calls `onHR` callback on each notification. |

**Resilience:** If the peripheral disconnects during exercise (`isExercising && wantsConnection`), the service auto-reconnects immediately. After exercise, `returnToScanning()` disconnects and reverts to passive discovery mode.

---

## File Reference

All source files live under `HeartInterval/HeartInterval/`.

| File | Role |
|---|---|
| `ContentView.swift` | Root view — creates `@StateObject ExerciseViewModel` and routes to the correct view based on `appState` |
| `ExerciseViewModel.swift` | All runtime state, timers, HR logic, announcement settings, zone breach detection, standby polling, HR source timeout |
| `ExerciseView.swift` | Live exercise screen — `HRSpeedometer` gauge, BPM display, HR source badge, staleness indicator, `NoHRWarning` panel (shown after 20s timeout) |
| `StandbyView.swift` | Setup screen — zone slider, speak/summary interval pickers, workout type picker, BLE/Watch source status indicators |
| `PausedView.swift` | Pause screen — frozen metrics via `MetricRow`, end/continue buttons |
| `SummaryView.swift` | Post-exercise summary — `HRGraph` (Canvas line chart with zone bands), `ZoneDistributionBar`, save-to-Health button |
| `SplashView.swift` | Animated launch screen (shown during 1.5s init delay) |
| `StartingView.swift` | Loading indicator shown during exercise start and HealthKit auth |
| `SessionSummary.swift` | Data models: `SessionSummary`, `HRSample`, `WorkoutActivityType` (run/cycle/rowing/hiit/skiing/other) |
| `BLEHeartRateService.swift` | Dual-mode BLE: passive standby scanning + active exercise connection with auto-reconnect |
| `HealthKitService.swift` | Reads HR from Apple Health (observer query + 5s polling fallback); standby liveness polling; workout saving via `HKWorkoutBuilder` |
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
