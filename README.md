# Thunderbolt Budget ⚡️

A macOS utility to explicitly map and monitor raw Thunderbolt & USB4 bandwidth consumption in real-time.

Built natively and strictly optimized for the **Apple Silicon** architecture.

> **This is a fork of [ekwipt/ThunderboltBudget](https://github.com/ekwipt/ThunderboltBudget)** with bug fixes, live bandwidth updates, and stability improvements.

---

## Why this exists
Macs have a hard maximum data throughput of **40 Gbps** per Thunderbolt controller group. When cascading intensive data hardware — like multiple NVMe RAID arrays, 10Gb Ethernet adapters, and 4K/8K displays — it is incredibly easy to silently bottleneck the bus, causing dropped frames on set or crippled offload speeds.

Thunderbolt Budget hooks directly into the core macOS `IOKit` hardware registry, identifies exactly where devices are physically plugged into your Mac's chassis, and charts raw mathematical bandwidth usage to ensure your hardware topology is totally optimized.

---

## Features
- **Pure Apple Silicon Engine** — Hard-coded `usb-drd` kernel bindings for native M1/M2/M3/M4 unified memory read speed
- **Physical Chassis Mapping** — Built-in dictionaries use your Mac's `sysctl` model identifier to map hubs to their exact physical port (e.g. "Left Back Port" vs "Right Port")
- **Live Bandwidth Totals** — System total and per-port labels update every second from real `iostat` and `netstat` throughput deltas — not static link speed reservations
- **Live Swift Charts Analytics** — Background daemon streams real-time storage and Ethernet throughput into a fluid visual histogram
- **Smart Bottleneck Notifications** — Native `UNUserNotificationCenter` integration fires a local push warning when active throughput approaches the 36 Gbps threshold
- **Menu Bar Daemon** — A sleek menu bar overlay provides an instant visual readout of active consumption without taking over your primary screen

---

## Changes from upstream
- Fixed corrupted `.xcodeproj` and missing Compile Sources build phase
- Removed SwiftData `Item` template boilerplate that caused build failures
- Removed feedback loop in `LiveAnalytics` that caused cumulative instead of per-second throughput values
- `gatherSystemTotal()` now reads live `iostat`/`netstat` delta data instead of static `system_profiler` link speed
- Port labels update every second via a live timer tied to `LiveAnalytics`
- Fixed `@MainActor` concurrency warnings in `ContentView` and `LiveAnalytics`
- Fixed invalid SF Symbol names (`cube`, `display.circle.fill`)
- Replaced all app icon assets — regenerated full set from 16px up to 1024px for correct Xcode asset catalog compliance
- Cleaned up unused files (`BandwidthManager.swift`, `ThunderboltDevice.swift`)

---

## Installation
1. Clone this repository
2. Open `ThunderboltBudget.xcodeproj` in Xcode 15+
3. Select your local Mac as the active deployment target
4. Hit **Cmd + R** to run, or go to **Product > Archive** to package a distributable app

*Built for macOS Sonoma (14.0) and later. Apple Silicon only.*
