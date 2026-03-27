# Audiogram EQ Converter

A macOS app that converts hearing test results (audiograms) into personalized parametric EQ settings for headphones, speakers, and IEMs — helping users with hearing loss hear better with their audio devices.

## Features

### Audiogram Input

- **Manual entry** — input hearing thresholds at standard frequencies (250 Hz – 8 kHz) for each ear, with an interactive click-to-plot chart
- **Import from image or PDF** — OCR-powered extraction of audiogram data using Apple Vision, with a manual overlay fallback

### Device Frequency Response

- **AutoEQ database** — browse and download from 7,000+ headphone measurements via the [AutoEQ](https://github.com/jaakkopasanen/AutoEq) project
- **Local file import** — load CSV/text frequency response files

### EQ Generation

- NAL-NL2-inspired hearing compensation algorithm (half-gain rule with high-frequency emphasis and compression for severe loss)
- Combines hearing compensation with device response correction
- Parametric EQ fitting with 5–31 configurable bands (peak, shelf, and pass filter types)
- Iterative Q-factor optimization across 50 refinement passes

### Export & Presets

- Export as **Parametric EQ text**, **AutoEQ format**, or **JSON**
- Save and manage named presets with full context (audiogram, device, EQ profile)

## Requirements

Tested on:

- macOS 26.3
- Xcode 26.3

## Building

Open `AudiogramEQ.xcodeproj` in Xcode and build the **AudiogramEQ** target. No external dependencies are required — the app uses only Apple-native frameworks:

- SwiftUI & AppKit — UI
- Vision — OCR text recognition
- PDFKit — PDF handling
- Charts — data visualization
- Accelerate — numerical computation

## Project Structure

```text
AudiogramEQ/
├── Models/              # Audiogram, EQProfile, EQPreset, FrequencyResponseCurve
├── Views/
│   ├── Components/      # AudiogramChartView
│   ├── Import/          # ImportAudiogramView (OCR + manual overlay)
│   └── Results/         # EQResultsView, PresetManagementView
├── Services/            # HearingCompensation, ParametricEQFitter, OCR,
│                        #   AutoEQ integration, export, preset storage
├── Utilities/           # TextFileDocument helper
├── AppState.swift       # Global observable state
└── AudiogramEQApp.swift # App entry point
```

## How It Works

1. **Input** an audiogram — manually or via image/PDF import
2. *(Optional)* **Load** your device's frequency response from AutoEQ or a local file
3. **Generate** — the app calculates per-frequency hearing compensation, combines it with any device correction, and fits optimized parametric EQ bands
4. **Export** the EQ settings to your equalizer of choice

## Acknowledgements

- [AutoEQ](https://github.com/jaakkopasanen/AutoEq) by Jaakko Pasanen — headphone frequency response database (MIT License)

## License

Copyright © 2025 AudiogramEQ. All rights reserved.
