import SwiftUI
import AppKit
import Charts

struct ContentView: View {
    @ObservedObject var manager = HardwareManager.shared
    @ObservedObject var analytics = LiveAnalytics.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !manager.deviceTrees.isEmpty, !manager.isScanning {
                    let total = manager.gatherSystemTotal()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total System Bandwidth")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f Gbps", total))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()
                    LiveTrafficChart(analytics: analytics)
                    Divider()
                }

                if manager.deviceTrees.isEmpty || manager.isScanning {
                    VStack(spacing: 12) {
                        if manager.isScanning {
                            ProgressView("Scanning Thunderbolt Bus...")
                        } else {
                            Text("No hardware detected.")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color.black.opacity(0.05))
                    .padding()
                } else {
                    List {
                        ForEach(manager.deviceTrees) { node in
                            DeviceNodeView(node: node, expandedNodes: $manager.expandedNodes)
                        }
                    }
                    .background(Color.black.opacity(0.05))
                    .padding()
                }
            }
            .navigationTitle("Thunderbolt Bandwidth Budget")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { manager.performScan() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: { manager.copyMarkdownAction() }) {
                        Label("Copy Markdown", systemImage: "doc.on.clipboard")
                    }
                    .disabled(manager.deviceTrees.isEmpty || manager.isScanning)
                }
            }
        }
        .frame(minWidth: 650, minHeight: 850)
    }
}

struct DeviceNodeView: View {
    let node: DeviceNode
    @Binding var expandedNodes: Set<UUID>

    var body: some View {
        if let children = node.children, !children.isEmpty {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedNodes.contains(node.id) },
                    set: { isExpanding in
                        if isExpanding {
                            expandedNodes.insert(node.id)
                        } else {
                            expandedNodes.remove(node.id)
                        }
                    }
                )
            ) {
                ForEach(children) { child in
                    DeviceNodeView(node: child, expandedNodes: $expandedNodes)
                }
            } label: {
                DeviceRow(node: node)
            }
        } else {
            DeviceRow(node: node)
        }
    }
}

struct DeviceRow: View {
    let node: DeviceNode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: node.iconName)
                    .foregroundColor(.blue)
                Text(node.name)
                    .font(.system(.body, design: .rounded))
                Spacer()
                if let bw = node.bandwidthLabel {
                    Text(bw)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(pillColor(for: node))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }

            if let ratio = node.bandwidthRatio {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                        Rectangle()
                            .fill(pillColor(for: node))
                            .frame(width: max(0, min(CGFloat(ratio), 1.0) * geo.size.width))
                    }
                }
                .frame(height: 4)
                .cornerRadius(2)
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 4)
    }

    private func pillColor(for node: DeviceNode) -> Color {
        guard let ratio = node.bandwidthRatio else { return Color.blue.opacity(0.8) }
        if ratio >= 0.80 { return .red }
        if ratio >= 0.50 { return .orange }
        return .green
    }
}

struct LiveTrafficChart: View {
    @ObservedObject var analytics: LiveAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Data Throughput")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Chart {
                ForEach(Array(analytics.totalTrafficGbps.enumerated()), id: \.offset) { index, value in
                    AreaMark(
                        x: .value("Time", index),
                        y: .value("Gbps", value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue.opacity(0.6), .blue.opacity(0.0)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", index),
                        y: .value("Gbps", value)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis(.hidden)
            .chartYScale(domain: 0...max(40.0, (analytics.totalTrafficGbps.max() ?? 40.0) + 5))
            .frame(height: 120)
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}
