# SoilSense — Final Defense Build

## v4.3.0 — Reading clarity, criteria legend, AI guidance, and reset

- **Clear Reading History** now resets only Reading History and Historical Trends.
- The newest completed scan is retained as the account's **Current Reading** for Home, Analysis, AI, Crops, and Reports.
- New scans automatically begin a fresh history after the clear point.
- Accounts with no completed scan now show `--` / **No reading yet** instead of misleading `0.0` values.
- This revision adds a small Firestore preference document (`users/{uid}/preferences/history`), so deploy the included `firestore.rules` before testing Clear History.


SoilSense is the Flutter + ESP32 + Firebase build for the AI-Powered Soil Components Detection and Crop Management Decision Support System.

## Final mobile experience

- Home shows the latest completed soil measurements and keeps the previous valid values visible while a new scan is running.
- Soil Analysis contains the deterministic Soil Condition Assessment, Current Reading, a simplified Historical Trends chart, and private Reading History.
- Crop Management contains the local crop-suitability ranking plus optional Gemini guidance. The large completed-AI status cards were removed; completed AI now uses a compact `AI ready` badge.
- Smart Crop Plan uses a crop from the latest suitability ranking and also uses a compact `AI ready` badge when AI guidance is available.
- The redundant `Latest saved soil reading` card was removed from Crop Management.
- Bottom navigation changes tabs without page transition animation so Home, Analysis, Crops, and Reports feel like one static app shell.

## Soil balance and crop safety gate

The former fertility-style score is now presented as a **Soil Balance Index** / **Soil Condition Assessment** so excessive NPK does not look like a contradiction. SoilSense uses these project reference bands for the explainable balance calculation:

- Nitrogen: 40–100 mg/kg
- Phosphorus: 50–120 mg/kg
- Potassium: 100–300 mg/kg
- pH: 5.5–7.5
- Moisture: 40–90%

Each parameter is labeled Low, Normal, or High. Both low and excessive values can lower the balance score. These are SoilSense project reference bands for decision support, not universal laboratory sufficiency ranges for every crop, soil type, or extraction method.

Crop suitability now has a hard recommendation gate at **50%**. Scores below 50% remain visible under **Not Recommended**, but they cannot become Best Match, AI Crop Suggestion, Smart Crop Plan, or the planting recommendation in a generated report.

## Motion and dark-mode polish

- Main content cards use short fade/slide reveals and recommendation cards use subtle entrance motion.
- Bottom-navigation route switching remains transition-free; only the tapped icon gets a brief scale response.
- Dark-mode secondary text, cards, chips, icons, outlines, and recommendation values use higher-contrast theme colors.
- Smart Recommendation helper subtitles were removed to reduce visual clutter.

## Historical Trends redesign

The chart is intentionally simpler for defense and field use:

- uses straight line segments instead of curved interpolation, preventing the graph from visually dipping below zero between non-negative sensor values;
- displays the selected metric's unit;
- shows Latest, Average, Min, and Max summaries;
- uses adaptive Y-axis scaling;
- reduces X-axis clutter by showing only useful time/date labels;
- supports point tooltips for the exact date, time, and value;
- supports Moisture, N, P, K, pH, Temperature, and EC;
- displays up to the 10 most recent private readings.

## Settings

Profile is simplified. The following controls are now grouped under **Profile > Settings**:

- Edit Display Name
- Send Password Reset Email
- SoilSense Wi-Fi Setup
- Scan Duration
- Dark Mode
- App & AI Language

### Dark Mode

Dark Mode uses a forest-toned dark interface. It is cached locally for signed-out/authentication screens and synchronized per signed-in account through Firestore.

### Language

The current choices are **English** and **Filipino**. The setting changes key SoilSense navigation/screen labels and is also sent to Gemini, so newly generated AI crop guidance and Smart Crop Plan guidance use the selected language. Previously saved AI text is not rewritten retroactively.

App preferences are stored at:

`users/{uid}/preferences/app`

The included `firestore.rules` contains the matching per-account rule.



## Onboarding and authentication polish (v4.2.0)

- First-time users now see a short 3-page SoilSense onboarding flow with **Get Started**.
- Onboarding is stored locally and is shown only on the first app run.
- Dark Mode and language are cached locally, so Login, Sign Up, onboarding, and other signed-out screens keep the user's selected appearance instead of reverting to light mode after logout.
- Signed-in account preferences still sync through `users/{uid}/preferences/app`.
- Profile, Notifications, Settings, Help, Privacy, and Wi-Fi setup use small fade/slide transitions, while Home/Analysis/Crops/Reports bottom navigation remains transition-free.

## Report download behavior (v4.2.0)

- The Reports tab no longer opens as a blank page with a blocking full-screen spinner. Its app bar and report controls appear immediately while saved reports load in the background.
- **Generate & Download Report** saves the report in Firestore and automatically writes the PDF to **Downloads/SoilSense** on Android.
- **Download PDF** on an existing saved report also saves directly to **Downloads/SoilSense** and no longer opens the Android share/send sheet.
- Printing remains available as a separate report action.

This v4.2.0 UX revision does not require a Firestore-rule change or a new ESP32 firmware upload. The included firmware remains `3.9.2-hybrid-wifi`.

## AI stability fix (v4.1.1)

The AI flow was hardened after a UX issue where Smart Recommendations and Crop Management could repeatedly switch between loading and result states.

- ESP32/device heartbeat changes no longer restart Gemini processing.
- Repeated Firestore emissions of the same completed soil reading are ignored for AI triggering.
- Each completed reading is processed once, with only controlled background retries after temporary AI failures.
- Background retries preserve the last terminal AI status instead of forcing the UI back to a loading state.
- Home Smart Recommendations keep deterministic recommendations visible while AI works.
- Crop Suitability Ranking and Smart Crop Plan no longer disappear behind AI skeleton loaders.
- AI remains an enhancement layer; the built-in decision-support result stays stable even when Gemini is slow, unavailable, or rate-limited.

No Firestore-rule or ESP32 firmware change was required for this AI stability revision. The included firmware remains `3.9.2-hybrid-wifi`.

## AI scope

AI remains limited to decision-support guidance for:

1. Crop Suitability / Smart Recommendations
2. Smart Crop Plan

Soil Condition Assessment and report generation remain deterministic and do not require AI quota.

Gemini may explain and refine up to 5 crops only when those crops already meet SoilSense's deterministic suitability threshold. AI cannot promote a crop classified as Not Recommended. If every evaluated crop is below 50%, Crop Management, Smart Recommendations, Smart Crop Plan, and generated reports show no planting recommendation or crop plan.

## Scan controls

### Physical buttons

- **START:** GPIO 27 -> momentary button -> GND (`INPUT_PULLUP`)
- **STOP:** GPIO 14 -> momentary button -> GND (`INPUT_PULLUP`)

STOP cancels an active scan, discards all partial samples, and does **not** upload an incomplete soil reading.

Holding START for 3 seconds starts SoilSense Wi-Fi setup when the user intentionally wants to change networks. Holding STOP for 3 seconds while Wi-Fi setup is active cancels setup and restores the previously saved Wi-Fi credentials. A brand-new device with no saved Wi-Fi enters setup automatically; a device with saved credentials keeps retrying that network until the user manually opens setup.

### Adjustable duration

Go to **Profile > Settings > Scan Duration**.

- Minimum: 30 seconds
- Maximum: 5 minutes
- Step: 30 seconds
- Default: 2 minutes

The selected duration is stored in `system/scan_settings` and the ESP32 reads it when a scan begins.

## Final LED behavior

Use one 220-ohm resistor per LED, with the LED return connected to the shared ESP32 GND rail.

- **Blue — GPIO 25:** Wi-Fi setup active.
- **Yellow — GPIO 26:** immediately turns solid when START is accepted, then begins blinking after scan-state synchronization. It returns to solid while a scan is being finalized/uploaded or a cancellation is being synchronized.
- **Green — GPIO 33:** scan successfully uploaded, or manual STOP successfully acknowledged. Green is intentionally delayed until after the ESP32 sends `scanning=false`, reducing the case where green is already on while the mobile loading indicator is still visible.
- **Red — GPIO 32:** error indication.

Firmware version in this package: `3.9.2-hybrid-wifi`.

## Loading/state synchronization

- Home **Soil Measurements** shows a scan loading indicator while `system/device_status.scanning == true`.
- Soil Analysis **Current Reading** now shows the same scan/loading state.
- Previous valid measurements remain visible until a completed new scan arrives.
- START uses a short solid-yellow preparation phase before blinking so the physical device gives immediate feedback while Firestore/mobile state catches up.
- STOP and normal completion send `scanning=false` before green confirmation, reducing visible app/LED mismatch.
- Network latency can never be mathematically zero, but hardware feedback and app state are now ordered so the user does not get a misleading green-success signal before the mobile scan state is cleared.

## Device online/offline behavior

The app waits **60 seconds** without a fresh ESP32 heartbeat before treating the device as offline. This reduces noisy offline/reconnected notifications caused by short Wi-Fi interruptions.

Saved private readings remain available when the device is offline.

## Ownership/privacy model

- One physical SoilSense device has one current owner account at a time.
- Admin controls the current owner.
- New scans are stored only for the owner assigned at the time of upload.
- Previous owners retain only their own historical readings.
- Borrowers/new owners do not receive another account's historical readings.

## Sensor and RS485 wiring

7-in-1 sensor:

- Brown -> external sensor supply positive (use the voltage required by your sensor setup)
- Black -> sensor supply GND
- Yellow -> RS485 A / D+
- Blue -> RS485 B / D-

ESP32 / RS485 interface used by this firmware:

- RX2 -> GPIO 16
- TX2 -> GPIO 17
- RE/DE -> GPIO 4 when required by the transceiver configuration

Do not route the external sensor supply voltage into a GPIO or START/STOP button input.

## Stop button terminal note

For a 3-terminal momentary button, use **COM + NO**. NC remains disconnected. COM and NO are not polarized for this GPIO-to-GND input, so either of those two contacts may be connected to GPIO 14 and the other to GND.

## Firebase files

This package includes:

- `firestore.rules`
- `firestore.indexes.json`
- `firebase.json`
- `iot/esp32_soilsense.ino`

The separate finished admin web project is intentionally **not included**.

## Required update steps

1. If you are already using the v4.1.1 Firestore rules, no rule redeploy is required for this v4.2.0 UX update.

2. No ESP32 re-upload is required for this update if `3.9.2-hybrid-wifi` is already installed.

3. Rebuild the Flutter app:

```bash
flutter clean
flutter pub get
flutter build apk
```

Because `flutter_localizations` is now used for the language setting, run `flutter pub get` before building this revision.

## Defense checklist

Run this sequence before the presentation:

1. Sign in with the intended owner account.
2. Confirm the device is online.
3. Open Profile > Settings and verify Scan Duration.
4. Press START: yellow should become solid, then blink; Home and Soil Analysis should show scanning.
5. Let one scan complete: the final reading should upload, loading should clear, then green should confirm success.
6. Start another scan and press STOP: partial data must be discarded and no new soil-reading document should be created.
7. Confirm crop ranking and Smart Crop Plan update from the latest completed reading.
8. Test English/Filipino AI language once while internet is available.
9. Test Dark Mode.
10. Power off the ESP32 and verify the app waits about 60 seconds before declaring it offline.


### v4.3.0 changes
- NPK is displayed as mg/kg instead of ppm in the app, AI context, and reports.
- Added a reading-criteria and color legend to the information sheet.
- Removed duplicate in-app notification SnackBars; system notification-area alerts remain.
- Smart Recommendations now allow moderately detailed, measurement-aware guidance.
- Added Reset Current Reading on Soil Analysis. It clears current/live views without deleting saved history; the next completed scan restores a current reading.
