import Foundation
import Darwin
import notify

/// Reads thermal and memory pressure without root: a notify(3) state read and two sysctls, cheap enough to poll
/// every few seconds.
public final class LiveStrainSensor: StrainSensing {
    /// Raw readings, injectable for tests. Each returns nil when unavailable.
    public struct Readers {
        /// `OSThermalPressureLevel` (macOS: 0 nominal, 1 moderate, 2 heavy, 3 trapping, 4 sleeping).
        public var thermalPressure: () -> UInt64?
        /// Fallback when the thermal pressure notification can't be read.
        public var thermalState: () -> ProcessInfo.ThermalState
        /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
        public var memoryPressure: () -> Int32?
        /// `vm.swapusage` bytes used.
        public var swapUsed: () -> UInt64?
        /// Battery and chip sensor temperatures.
        public var temperatures: () -> TemperatureReader.Reading

        public init(thermalPressure: @escaping () -> UInt64?, thermalState: @escaping () -> ProcessInfo.ThermalState,
                    memoryPressure: @escaping () -> Int32?, swapUsed: @escaping () -> UInt64?,
                    temperatures: @escaping () -> TemperatureReader.Reading = { .init() }) {
            self.thermalPressure = thermalPressure; self.thermalState = thermalState
            self.memoryPressure = memoryPressure; self.swapUsed = swapUsed; self.temperatures = temperatures
        }
    }

    private let readers: Readers
    private let token: Int32

    public init(readers: Readers? = nil) {
        if let readers { self.readers = readers; token = NOTIFY_TOKEN_INVALID; return }
        // The system's thermal pressure level (libkern/OSThermalNotification.h): finer than ProcessInfo.thermalState
        // (heavy vs trapping), and once registered notify_get_state is a cheap shared-memory read.
        var registration = NOTIFY_TOKEN_INVALID
        let ok = notify_register_check(kOSThermalNotificationPressureLevelName, &registration) == NOTIFY_STATUS_OK
        let token = ok ? registration : NOTIFY_TOKEN_INVALID
        self.token = token
        self.readers = Readers(
            thermalPressure: {
                var state: UInt64 = 0
                return token != NOTIFY_TOKEN_INVALID && notify_get_state(token, &state) == NOTIFY_STATUS_OK ? state : nil
            },
            thermalState: { ProcessInfo.processInfo.thermalState },
            memoryPressure: { Self.sysctl("kern.memorystatus_vm_pressure_level", Int32.self) },
            swapUsed: {
                var usage = xsw_usage()
                var size = MemoryLayout<xsw_usage>.size
                return sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 ? usage.xsu_used : nil
            },
            temperatures: { [temps = TemperatureReader()] in temps.read() })
    }

    deinit { if token != NOTIFY_TOKEN_INVALID { notify_cancel(token) } }

    /// Battery temperature (°C) at which the Mac counts as hot / overheating. macOS's own pressure level stays
    /// nominal well past the point where the case is too hot to touch, so the battery sensor decides earlier.
    /// From strain.log on a MacBook Pro M4 Pro: 33-38 °C at a desk, 42-43.5 °C after 30-60 min working in a bag.
    public static let batteryHot: Double = 41
    public static let batteryOverheating: Double = 44

    public func read() -> Strain {
        let pressure = readers.thermalPressure().map(Self.thermalLevel(pressure:))
            ?? Self.thermalLevel(state: readers.thermalState())
        let t = readers.temperatures()
        return Strain(thermal: max(pressure, Self.thermalLevel(battery: t.battery)),
                      memory: readers.memoryPressure().map(Self.memoryLevel(pressure:)) ?? .normal,
                      swapUsed: readers.swapUsed(), batteryTemp: t.battery, chipTemp: t.chip)
    }

    public static func thermalLevel(battery: Double?) -> StrainLevel {
        guard let b = battery else { return .normal }
        return b >= batteryOverheating ? .critical : b >= batteryHot ? .elevated : .normal
    }

    /// Moderate is routine under a long build; heavy is where macOS starts capping CPU speed, trapping is near
    /// shutdown territory.
    public static func thermalLevel(pressure: UInt64) -> StrainLevel {
        switch pressure {
        case 0, 1: return .normal     // nominal, moderate
        case 2: return .elevated      // heavy
        default: return .critical     // trapping, sleeping
        }
    }

    public static func thermalLevel(state: ProcessInfo.ThermalState) -> StrainLevel {
        switch state {
        case .nominal, .fair: return .normal
        case .serious: return .elevated
        default: return .critical
        }
    }

    /// The kernel's own verdict, the same one that triggers jetsam and the "out of application memory" dialog.
    /// Values are DISPATCH_MEMORYPRESSURE_NORMAL/WARN/CRITICAL (1/2/4).
    public static func memoryLevel(pressure: Int32) -> StrainLevel {
        switch pressure {
        case 4...: return .critical
        case 2...: return .elevated
        default: return .normal
        }
    }

    private static func sysctl<T: FixedWidthInteger>(_ name: String, _: T.Type) -> T? {
        var value: T = 0
        var size = MemoryLayout<T>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }
}
