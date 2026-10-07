import AppKit
import Combine
import ServiceManagement
import Darwin

struct TemperatureSensor: Identifiable, Codable {
    let key: String
    let name: String
    let group: String
    let celsius: Double
    var id: String { key }
}

struct HardwareSnapshot: Codable {
    var timestamp = Date()
    var sensors: [TemperatureSensor] = []
    var actualRPM: Double?
    var minimumRPM: Double?
    var maximumRPM: Double?
    var targetRPM: Double?
    var fanMode: Int?
    var error: String?
    var cpu: Double? { sensors.filter { $0.group == "CPU" }.map(\.celsius).max() }
    var gpu: Double? { sensors.filter { $0.group == "GPU" }.map(\.celsius).max() }
    var chip: Double? { [cpu, gpu].compactMap { $0 }.max() }
    var controllable: Bool {
        guard let lo = minimumRPM, let hi = maximumRPM else { return false }
        return lo > 0 && hi > lo && actualRPM != nil && fanMode != nil
    }
}

final class SMCReader {
    // M4 mappings from Stats. Unknown sensors keep their firmware key as a label.
    static let cpuKeys = ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
    static let gpuKeys = ["Tg0G", "Tg0H", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k", "Tg1U", "Tg1k"]
    var keys: [String] = []

    func number(_ key: String) -> Double? {
        var value = Double.nan
        return key.withCString { mt_number($0, &value) } == 0 && value.isFinite ? value : nil
    }

    func discover() {
        // T* also contains calibration constants and virtual policy channels.
        // Only display M4 channels whose meanings have been identified.
        let names = Set(Self.cpuKeys + Self.gpuKeys + ["Tm0p", "Tm1p", "Tm2p", "TA0P", "TH0a", "TH0b", "TH0c", "TW0P", "TT0P"])
        keys = names.sorted().filter { key in
            guard let value = number(key) else { return false }
            // Valid temperature readings only; zero marks disabled SMC channels.
            return value > 0 && value < 125
        }
    }

    func snapshot() -> HardwareSnapshot {
        var result = HardwareSnapshot()
        guard mt_open() == 0 else {
            result.error = "无法连接温度传感器：\(String(cString: mt_last_error()))"
            return result
        }
        if keys.isEmpty { discover() }
        for key in keys {
            guard let value = number(key), value > 0, value < 125 else { continue }
            let group = Self.cpuKeys.contains(key) ? "CPU" : Self.gpuKeys.contains(key) ? "GPU" : "其他"
            let name: String
            if group == "CPU" { name = key.hasPrefix("Te") ? "CPU 能效核心 · \(key)" : "CPU 性能核心 · \(key)" }
            else if group == "GPU" { name = "GPU · \(key)" }
            else if ["Tm0p", "Tm1p", "Tm2p"].contains(key) { name = "内存附近 · \(key)" }
            else if key.hasPrefix("TH") { name = "存储 · \(key)" }
            else if key == "TW0P" { name = "无线模块 · \(key)" }
            else if key == "TT0P" { name = "雷雳附近 · \(key)" }
            else { name = "环境 · \(key)" }
            result.sensors.append(TemperatureSensor(key: key, name: name, group: group, celsius: value))
        }
        result.actualRPM = number("F0Ac")
        result.minimumRPM = number("F0Mn")
        result.maximumRPM = number("F0Mx")
        result.targetRPM = number("F0Tg")
        var modeKey = [CChar](repeating: 0, count: 5)
        if mt_fan_mode_key(&modeKey) == 0, let mode = number(String(cString: modeKey)) { result.fanMode = Int(mode) }
        if result.cpu == nil || result.gpu == nil { result.error = "暂时无法完整读取芯片温度，请稍后重试。" }
        return result
    }
}

final class FanSession {
    var socket: Int32 = -1
    var socketPath: String?
    var authorized: Bool { socket >= 0 }

    static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    func authorize() throws {
        if authorized { return }
        guard let executable = Bundle.main.path(forAuxiliaryExecutable: "MiniThermalHelper") else {
            throw NSError(domain: "MiniThermal", code: 1, userInfo: [NSLocalizedDescriptionKey: "调速组件缺失，请重新安装。"])
        }
        let path = "/var/tmp/minithermal-\(getuid())-\(getpid())-\(UUID().uuidString.prefix(12)).sock"
        let command = "\(Self.shellQuote(executable)) --serve \(getpid()) \(getuid()) \(Self.shellQuote(path)) >/dev/null 2>&1 &"
        let script = "do shell script \(Self.appleString(command)) with administrator privileges with prompt \(Self.appleString("MiniThermal 需要授权才能调节风扇；温度查看不需要授权。"))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errors = Pipe(); process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8) ?? ""
            let message = detail.contains("-128") ? "已取消授权，温度监测仍可使用。" : "授权未完成：\(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
            throw NSError(domain: "MiniThermal", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
        for _ in 0..<25 {
            socket = path.withCString { mt_connect($0) }
            if socket >= 0 { socketPath = path; return }
            usleep(100000)
        }
        throw NSError(domain: "MiniThermal", code: 3, userInfo: [NSLocalizedDescriptionKey: "调速组件未能启动；请重新授权。"])
    }

    func command(_ text: String) throws -> String {
        guard authorized else { throw NSError(domain: "MiniThermal", code: 4, userInfo: [NSLocalizedDescriptionKey: "请先启用调速。"] ) }
        var reply = [CChar](repeating: 0, count: 256)
        let result = text.withCString { mt_exchange(socket, $0, &reply, reply.count) }
        guard result == 0 else {
            close(socket); socket = -1
            throw NSError(domain: "MiniThermal", code: 5, userInfo: [NSLocalizedDescriptionKey: "调速连接已断开，保护进程会尝试恢复系统自动控制。"])
        }
        let response = String(cString: reply)
        guard response.hasPrefix("ok ") else {
            let message = response.contains("thermal_guard") ? "温度较高或读取失败，已暂停手动调速。" : response.contains("restore") ? "恢复自动控制失败，请重试；保护进程仍在尝试恢复。" : "风扇设置未成功：\(response)"
            throw NSError(domain: "MiniThermal", code: 6, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return response
    }
    func end() {
        if authorized { _ = try? command("quit") }
        if socket >= 0 { close(socket) }
        socket = -1
    }
    deinit { end() }
}

final class Monitor: ObservableObject {
    @Published var snapshot = HardwareSnapshot()
    @Published var history: [Double] = []
    @Published var requestedRPM: Double = 1500
    @Published var effectiveRPM: Double?
    @Published var authorized = false
    @Published var busy = false
    @Published var controlMode = "auto"
    @Published var message = "正在读取温度与风扇…"
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    let reader = SMCReader()
    let session = FanSession()
    let queue = DispatchQueue(label: "local.MiniThermal.hardware")
    var timer: DispatchSourceTimer?
    var onUpdate: ((HardwareSnapshot) -> Void)?
    private var initializedSlider = false

    init() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer; timer.resume()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    }

    func tick() {
        let fresh = reader.snapshot()
        var response: String?
        var failure: String?
        if session.authorized {
            do { response = try session.command(ProcessInfo.processInfo.thermalState == .critical ? "auto" : "ping") } catch { failure = error.localizedDescription }
        }
        let available = session.authorized
        DispatchQueue.main.async {
            self.snapshot = fresh
            self.authorized = available
            if let temp = fresh.chip { self.history.append(temp); self.history = Array(self.history.suffix(60)) }
            if !self.initializedSlider, let low = fresh.minimumRPM, let high = fresh.maximumRPM {
                self.requestedRPM = min(high, max(low, fresh.actualRPM ?? low)); self.initializedSlider = true
            }
            if let error = fresh.error { self.message = error }
            else if !self.authorized && !self.busy && self.controlMode == "auto" { self.message = "实时监测中 · 每 2 秒更新" }
            if let response { self.handle(response) }
            if let failure { self.message = failure; self.controlMode = "auto"; self.effectiveRPM = nil }
            self.onUpdate?(fresh)
        }
    }

    func handle(_ response: String) {
        let components = response.split(separator: " ")
        guard components.count >= 2 else { return }
        let state = String(components[1])
        switch state {
        case "manual", "protected":
            controlMode = "manual"
            if components.count >= 3 { effectiveRPM = Double(components[2]) }
            message = state == "protected" ? "温控保护中 · 已自动提高目标转速" : "手动调速生效 · 温控保护已开启"
        case "auto": controlMode = "auto"; effectiveRPM = nil; message = "风扇由 macOS 自动管理"
        case "thermal_guard": controlMode = "auto"; effectiveRPM = nil; message = "温控保护已触发 · 已恢复系统自动控制"
        case "system_reclaimed": controlMode = "auto"; effectiveRPM = nil; message = "系统已接管风扇 · 手动设置已停止"
        case "restore_failed": message = "自动恢复尚未完成 · 保护进程正在重试"
        case "write_failed": controlMode = "auto"; effectiveRPM = nil; message = "设置未生效 · 已恢复系统自动控制"
        default: break
        }
    }

    func enable() { perform(authorizing: true, command: nil) }
    func apply() { perform(authorizing: true, command: "set \(Int(requestedRPM.rounded()))") }
    func automatic() {
        if snapshot.fanMode != 1 && !authorized { controlMode = "auto"; message = "风扇已由 macOS 自动管理"; return }
        perform(authorizing: true, command: "auto")
    }
    private func perform(authorizing: Bool, command: String?) {
        guard !busy else { return }
        busy = true; message = session.authorized ? "正在应用设置…" : "请在系统授权窗口完成授权…"
        queue.async {
            do {
                if authorizing { try self.session.authorize() }
                let reply = try self.session.command(command ?? "ping")
                DispatchQueue.main.async { self.authorized = self.session.authorized; self.busy = false; self.handle(reply) }
            } catch {
                DispatchQueue.main.async { self.authorized = self.session.authorized; self.busy = false; self.message = error.localizedDescription }
            }
        }
    }
    @objc func sleeping() {
        queue.async {
            if self.session.authorized { _ = try? self.session.command("auto") }
            DispatchQueue.main.async { self.controlMode = "auto"; self.effectiveRPM = nil }
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { message = "请在系统设置 → 登录项中允许 MiniThermal。" }
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; message = "登录启动设置失败：\(error.localizedDescription)" }
    }
    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MiniThermal-温度记录.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var text = "time,sensor,name,celsius,fan_rpm\n"
        for sensor in snapshot.sensors {
            text += "\(ISO8601DateFormatter().string(from: snapshot.timestamp)),\(sensor.key),\(sensor.name),\(String(format: "%.2f", sensor.celsius)),\(snapshot.actualRPM.map { String(Int($0)) } ?? "")\n"
        }
        do { try text.write(to: url, atomically: true, encoding: .utf8); message = "已导出当前传感器读数" }
        catch { message = "导出失败：\(error.localizedDescription)" }
    }
    func shutdown() {
        timer?.cancel()
        queue.sync { session.end(); mt_close() }
    }
}
