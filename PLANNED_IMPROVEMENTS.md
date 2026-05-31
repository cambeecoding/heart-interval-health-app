# BeatZone — Planned Improvements

Features are listed in priority order by impact-to-effort ratio.

---

## 1. Session History
Store a summary of each session (date, duration, average HR, time in zone) on-device and optionally write it to Apple Health as a workout record. Gives users a sense of progress over time and leverages HealthKit infrastructure already in the app.

## 2. HR Zone Time Tracking
Record how many minutes were spent below, inside, and above the target zone during each session. Low effort — the data is already captured. Announced in the summary tick and shown on the pause/end screen. Particularly useful for interval training where deliberate zone spiking and recovery is the goal.

## 3. Rounds / Interval Timer
A configurable round structure (work duration, rest duration, number of rounds) with audio cues — "Round starting", "30 seconds remaining", "Rest". Opens BeatZone to combat sports, HIIT, and martial arts users with no external services required.

## 4. Recovery Heart Rate Tracking
At the end of a round or on pause, capture how quickly HR drops over the following 60 seconds. A well-established fitness metric — faster recovery indicates higher cardiovascular fitness. BeatZone already has the HR stream; this is a low-effort addition with high coaching value.

## 5. Calorie Estimate
A rough estimate based on HR, session duration, and optional user-entered age and weight. Not medically precise, but widely expected in fitness apps and straightforward to implement on-device with no external services.

## 6. GPS Route Tracking (optional)
Optional GPS acquisition and live route display on a MapKit map, with distance and speed announced alongside BPM. GPS is user-toggled on the standby screen — off by default for indoor sports (treadmill, judo, HIIT) and on for outdoor (cycling, running). Includes a signal strength indicator before exercise starts. Higher effort than the above; only relevant for outdoor use cases.
