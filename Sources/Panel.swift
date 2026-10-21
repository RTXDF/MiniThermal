import SwiftUI

struct ThermalPanel: View {
    private static let applicationIcon: NSImage? = {
        guard let path = Bundle.main.path(forResource: "AppIcon", ofType: "png") else { return nil }
        return NSImage(contentsOfFile: path)
    }()
    @ObservedObject var monitor: Monitor
    @State private var showSensors = false
    private let accent = Color(red: 0.08, green: 0.51, blue: 0.55)
    private var minimum: Double { monitor.snapshot.minimumRPM ?? 1000 }
    private var maximum: Double { max(minimum + 1, monitor.snapshot.maximumRPM ?? 4000) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                HStack(spacing: 10) {
                    temperatureCard("CPU 最高", value: monitor.snapshot.cpu, symbol: "cpu")
                    temperatureCard("GPU 最高", value: monitor.snapshot.gpu, symbol: "square.stack.3d.up")
                }
                history
                fanCard
                controls
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: monitor.message.contains("失败") || monitor.message.contains("未成功") ? "exclamationmark.circle" : "checkmark.shield")
                        .foregroundStyle(accent)
                    Text(monitor.message).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if monitor.busy { ProgressView().controlSize(.small) }
                }
                DisclosureGroup(isExpanded: $showSensors) {
                    VStack(spacing: 8) {
                        ForEach(monitor.snapshot.sensors) { sensor in
                            HStack {
                                Text(sensor.name).foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f °C", sensor.celsius)).monospacedDigit()
                            }.font(.system(size: 11))
                        }
                    }.padding(.top, 8)
                } label: {
                    Text("全部温度传感器（\(monitor.snapshot.sensors.count)）").font(.system(size: 12))
                }
                Divider()
                footer
            }.padding(22)
        }
        .frame(width: 382, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
    }

    private var header: some View {
        HStack(spacing: 11) {
            if let icon = Self.applicationIcon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().frame(width: 48, height: 48)
            } else {
                Image(systemName: "fanblades.fill").font(.system(size: 25)).foregroundStyle(accent)
                    .frame(width: 44, height: 44).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("MiniThermal").font(.system(size: 18, weight: .semibold))
                Text("Mac mini · Apple M4").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(monitor.snapshot.chip == nil ? Color.orange : accent).frame(width: 6, height: 6)
            Text("实时").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    private func temperatureCard(_ title: String, value: Double?, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map { String(format: "%.1f", $0) } ?? "—").font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
                Text("°C").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("芯片最高温度").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("最近 2 分钟").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Canvas { context, size in
                let values = monitor.history
                let bottom = max(20, (values.min() ?? 35) - 5)
                let top = max(bottom + 15, (values.max() ?? 50) + 5)
                for fraction in [0.0, 0.5, 1.0] {
                    var line = Path(); let y = size.height * fraction
                    line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(.secondary.opacity(0.12)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                }
                guard !values.isEmpty else { return }
                let points = values.enumerated().map { index, value in
                    CGPoint(x: size.width * Double(index) / Double(max(1, values.count - 1)), y: size.height * (1 - (value - bottom) / (top - bottom)))
                }
                var path = Path(); path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }
                var fill = path; fill.addLine(to: CGPoint(x: points.last!.x, y: size.height)); fill.addLine(to: CGPoint(x: points[0].x, y: size.height)); fill.closeSubpath()
                context.fill(fill, with: .linearGradient(Gradient(colors: [accent.opacity(0.18), accent.opacity(0.02)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = points.last { context.fill(Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)), with: .color(accent)) }
            }.frame(height: 44)
        }
    }
    private var fanCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Label("风扇实际转速", systemImage: "fanblades").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(monitor.snapshot.actualRPM.map { String(Int($0.rounded())) } ?? "—")
                        .font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("RPM").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Text(monitor.snapshot.fanMode == 1 ? "手动控制" : "系统自动")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
                    .padding(.horizontal, 9).padding(.vertical, 5).background(accent.opacity(0.08), in: Capsule())
                Text("\(Int(minimum))–\(Int(maximum)) RPM").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.padding(15).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("风扇调节").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("恢复系统自动", action: monitor.automatic).font(.system(size: 11))
                    .disabled(monitor.busy || !monitor.snapshot.controllable)
            }
            HStack {
                Text("目标转速").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(monitor.requestedRPM.rounded())) RPM").font(.system(size: 12, weight: .medium)).monospacedDigit()
            }
            Slider(value: $monitor.requestedRPM, in: minimum...maximum, step: 50)
                .disabled(monitor.busy || !monitor.snapshot.controllable)
                .accessibilityLabel("目标风扇转速")
            if let target = monitor.effectiveRPM {
                Text("当前生效目标：\(Int(target)) RPM").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if !monitor.authorized {
                    Button("启用调速…", action: monitor.enable).buttonStyle(.bordered)
                }
                Button("应用转速", action: monitor.apply).buttonStyle(.borderedProminent)
                Spacer()
            }.controlSize(.small).disabled(monitor.busy || !monitor.snapshot.controllable)
            Text("温度升高时自动提高转速；达到 95°C 时恢复系统自动。退出、休眠或连接中断时尝试恢复自动控制。")
                .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var footer: some View {
        VStack(spacing: 10) {
            Toggle("登录时启动", isOn: Binding(get: { monitor.loginEnabled }, set: monitor.setLogin)).toggleStyle(.checkbox)
                .font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("导出读数…", action: monitor.export).font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
}
