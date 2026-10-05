import Foundation
import ScaleKit

struct Options {
    var profile = UserProfile(heightCm: 175, age: 30, sex: .male, initialWeightKg: 75)
    var hasRealProfile = false
    var timeoutSeconds = 300
    var replay: URL?
    var capturesDirectory = URL.currentDirectory().appending(path: "captures")

    init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let flag = iterator.next() {
            guard let value = iterator.next() else { Self.fail("missing value for \(flag)") }
            switch flag {
            case "--height":
                profile.heightCm = Self.parse(Int(value), "bad --height")
                hasRealProfile = true
            case "--age":
                profile.age = Self.parse(Int(value), "bad --age")
            case "--sex":
                profile.sex = Self.parse(UserProfile.Sex(rawValue: value), "--sex must be male or female")
            case "--weight":
                profile.initialWeightKg = Self.parse(Double(value), "bad --weight")
            case "--timeout":
                timeoutSeconds = Self.parse(Int(value), "bad --timeout")
            case "--replay":
                replay = URL(fileURLWithPath: value)
            case "--captures":
                capturesDirectory = URL(fileURLWithPath: value)
            default:
                Self.fail("unknown flag \(flag)")
            }
        }
    }

    static func parse<T>(_ value: T?, _ message: String) -> T {
        guard let value else { fail(message) }
        return value
    }

    static func fail(_ message: String) -> Never {
        print("error: \(message)")
        print("usage: scale-probe [--height cm --age years --sex male|female --weight kg] [--timeout s] [--captures dir] [--replay file.jsonl]")
        exit(2)
    }
}

func fixed(_ value: Double, _ digits: Int = 1) -> String {
    value.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
}

func hex(_ byte: UInt8) -> String {
    String(format: "0x%02X", byte)
}

func describe(_ packet: ScalePacket?) -> String {
    switch packet {
    case nil:
        "not an Active Era packet"
    case let .liveWeight(kg, isStable, reportsHeartRate):
        "weight \(fixed(kg, 2)) kg" + (isStable ? " (stable)" : "") + (reportsHeartRate ? " [heart rate on]" : "")
    case let .balance(leftPercent, leftKg, isFinal):
        "balance left \(fixed(leftPercent))% (\(fixed(leftKg, 2)) kg)" + (isFinal ? " (final)" : "")
    case let .impedance(raw, algorithm):
        "impedance raw \(raw), algorithm \(hex(algorithm))"
    case let .heartRate(bpm):
        "heart rate \(bpm) bpm"
    case let .stored(measurement):
        describe(stored: ScaleReading(measurement))
    case let .unknown(type):
        "unknown type \(hex(type))"
    }
}

func describe(stored reading: ScaleReading) -> String {
    let impedance = reading.impedanceOhm.map { "\(fixed($0)) Ω" } ?? "no impedance"
    let heartRate = reading.heartRate.map { "heart rate \($0)" } ?? "no heart rate"
    let balance = reading.leftLegPercent.map { "left \(fixed($0))%" } ?? "no balance"
    return "stored reading \(reading.date.formatted(date: .abbreviated, time: .standard)): \(fixed(reading.weightKg, 2)) kg, \(impedance), \(heartRate), \(balance)"
}

func logPacket(_ hex: String, _ packet: ScalePacket?) {
    print("\(hex)  \(describe(packet))")
}

func printRows(_ rows: [(String, String?)]) {
    for case let (label, value?) in rows {
        print(label.padding(toLength: 16, withPad: " ", startingAt: 0) + value)
    }
}

func report(_ reading: ScaleReading, options: Options) {
    print("\n=== Result ===")
    printRows([
        ("weight", "\(fixed(reading.weightKg, 2)) kg"),
        ("impedance", reading.impedanceOhm.map { "\(fixed($0)) Ω (algorithm \(hex(reading.algorithm ?? 0)))" } ?? "none (barefoot? dry feet?)"),
        ("heart rate", reading.heartRate.map { "\($0) bpm" }),
        ("balance", reading.leftLegPercent.map { "left \(fixed($0))% / right \(fixed(100 - $0))%" }),
    ])
    guard options.hasRealProfile else {
        print("\nBody composition skipped: pass --height, --age, --sex to compute it.")
        return
    }
    guard let composition = BodyComposition(reading: reading, profile: options.profile) else {
        print("\nBody composition unavailable: no usable impedance.")
        return
    }
    let p = options.profile
    print("\n=== Body composition (\(p.heightCm) cm, \(p.age) y, \(p.sex.rawValue)) ===")
    printRows([
        ("body fat", "\(fixed(composition.bodyFatPercent)) %"),
        ("lean mass", "\(fixed(composition.leanMassKg)) kg"),
        ("muscle", composition.musclePercent.map { "\(fixed($0)) %" }),
        ("skeletal muscle", composition.skeletalMusclePercent.map { "\(fixed($0)) %" }),
        ("water", composition.waterPercent.map { "\(fixed($0)) %" }),
        ("protein", composition.proteinPercent.map { "\(fixed($0)) %" }),
        ("bone mass", composition.boneMassKg.map { "\(fixed($0)) kg" }),
        ("visceral fat", composition.visceralFat.map { fixed($0) }),
        ("BMR", composition.bmrKcal.map { "\($0) kcal" }),
        ("metabolic age", composition.metabolicAge.map { "\($0)" }),
    ])
}

func replay(_ url: URL, options: Options) -> Never {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { Options.fail("cannot read \(url.path)") }
    let decoder = JSONDecoder()
    var session = MeasurementSession()
    var finishAtMs: Int?
    for line in text.split(separator: "\n") {
        guard let captured = try? decoder.decode(CapturedPacket.self, from: Data(line.utf8)), let data = captured.data else { continue }
        if let deadline = finishAtMs, captured.ms >= deadline, let reading = session.finish(at: .now) {
            report(reading, options: options)
            print("")
        }
        let packet = ActiveEraProtocol.decode(data)
        logPacket(captured.hex, packet)
        if let packet, let finishDelay = session.consume(packet) {
            finishAtMs = captured.ms + Int(finishDelay / .milliseconds(1))
        }
    }
    if let reading = session.finish(at: .now) {
        report(reading, options: options)
    } else if !session.isFinished {
        Options.fail("capture has no stable weight")
    }
    exit(0)
}

@MainActor
final class LiveProbe {
    private let options: Options
    private let connection = ScaleConnection()
    private let encoder = JSONEncoder()
    private let started = Date.now
    private let captureURL: URL
    private let captureFile: FileHandle
    private var lastState = ScaleConnection.State.idle

    init(options: Options) {
        self.options = options
        let directory = options.capturesDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        captureURL = directory.appending(path: "\(stamp).jsonl")
        FileManager.default.createFile(atPath: captureURL.path, contents: nil)
        guard let file = try? FileHandle(forWritingTo: captureURL) else { Options.fail("cannot write \(captureURL.path)") }
        captureFile = file
    }

    func run() {
        connection.onEvent = { [weak self] in self?.handle($0) }
        watchState()
        Task {
            try? await Task.sleep(for: .seconds(options.timeoutSeconds))
            print("\nTimed out after \(options.timeoutSeconds) s without a reading. Is the scale awake and free (phone Bluetooth off)?")
            exit(1)
        }
        print("scale-probe: capturing to captures/\(captureURL.lastPathComponent)")
        connection.start(profile: options.profile)
    }

    private func handle(_ event: ScaleConnection.Event) {
        switch event {
        case let .packet(data, packet):
            let captured = CapturedPacket(ms: Int(Date.now.timeIntervalSince(started) * 1000), data: data)
            if let line = try? encoder.encode(captured) {
                captureFile.write(line + Data("\n".utf8))
            }
            logPacket(captured.hex, packet)
        case let .reading(reading):
            report(reading, options: options)
            print("\nRaw packets saved to captures/\(captureURL.lastPathComponent)")
            Task {
                try? await Task.sleep(for: .seconds(3))
                exit(0)
            }
        case .storedReading:
            break
        }
    }

    private func watchState() {
        withObservationTracking {
            _ = connection.state
        } onChange: {
            Task { @MainActor in
                self.stateChanged()
                self.watchState()
            }
        }
    }

    private func stateChanged() {
        let state = connection.state
        switch state {
        case .searching where lastState != .searching:
            print("Searching for the scale... step on it now.")
        case .connecting:
            print("Scale found, connecting...")
        case .measuring(nil):
            print("Connected. Stay on the scale barefoot until the reading finishes.")
        case let .bluetoothUnavailable(problem):
            print("Bluetooth unavailable: \(problem)")
            exit(1)
        default:
            break
        }
        lastState = state
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
let options = Options(arguments: CommandLine.arguments)
if let replayURL = options.replay {
    replay(replayURL, options: options)
}
let probe = LiveProbe(options: options)
probe.run()
dispatchMain()
