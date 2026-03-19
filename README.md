# Thunderbolt Budget ⚡️

A macOS utility for to explicitly map and monitor raw Thunderbolt & USB4 bandwidth consumption in real-time. 

Built natively and strictly optimized for the **Apple Silicon** architecture.

## Why this exists
Macs have a hard maximum data throughput of **40 Gbps** per Thunderbolt controller group. When cascading intensive data hardware—like multiple NVMe RAID arrays, 10Gb Ethernet adapters, and 4K/8K displays—it is incredibly easy to silently bottleneck the bus, causing dropped frames on set or crippled offload speeds. 

Thunderbolt Budget hooks directly into the core macOS `IOKit` hardware registry, identifies exactly where devices are physically plugged into the Mac's chassis, and charts the raw mathematical bandwidth usage to ensure your hardware topology is totally optimized.

## Features
- **Pure Apple Silicon Engine:** Hard-coded `usb-drd` kernel bindings for native M1/M2/M3/M4 unified memory read speed.
- **Physical Chassis Mapping:** Built-in dictionaries use your Mac's `sysctl` model to dictate whether a hub is explicitly plugged into the **"Left Back Port"** or the **"Right Port"** of your specific chassis.
- **Live Swift Charts Analytics:** Background daemon streams real-time `iostat` (Storage) and `netstat` (Ethernet) throughput deltas directly against mathematically calculated DP (DisplayPort) overhead into a fluid visual histogram.
- **Smart Bottleneck Notifications:** Native `UNUserNotificationCenter` integration automatically fires a local macOS push warning if a hot-plugged device pushes the active controller dangerously close to the 36 Gbps warning threshold.
- **Menu Bar Daemon:** A sleek menu bar overlay provides an instant visual readout of your active consumption without congesting your primary screens.

## Installation
1. Clone this repository.
2. Open `ThunderboltBudget.xcodeproj` in Xcode 15+.
3. Select your local Mac as the active deployment target.
4. Hit **Cmd + R** to run, or go to **Product > Archive** to package it into a distributable application.

*Built for absolute throughput precision on macOS Sonoma and later.*
