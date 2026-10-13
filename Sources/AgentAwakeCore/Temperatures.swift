import Foundation
import IOKit

/// Battery and chip temperatures from the HID temperature sensors (Apple silicon), without root.
///
/// macOS's thermal pressure level only rises once it starts slowing the chip, which can be long after the case
/// is hot (a MacBook working in a bag). The battery sensor sits closest to the case, so it's the signal for
/// "too hot to keep going". These are private IOKit calls (the same ones Stats and macmon use); if they ever
/// disappear the readings are nil and only the pressure level is used.
public final class TemperatureReader {
    public struct Reading: Equatable {
        public var battery: Double?   // hottest "gas gauge battery" sensor, °C
        public var chip: Double?      // hottest "PMU tdie" sensor, °C
        public init(battery: Double? = nil, chip: Double? = nil) { self.battery = battery; self.chip = chip }
    }

    private let client: AnyObject?

    public init() {
        let c = hidClientCreate(kCFAllocatorDefault)?.takeRetainedValue()
        // Usage page 0xff00, usage 5: Apple vendor temperature sensors.
        if let c { _ = hidClientSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary) }
        client = c
    }

    public func read() -> Reading {
        guard let c = client, let services = hidClientCopyServices(c)?.takeRetainedValue() as? [AnyObject] else {
            return Reading()
        }
        var r = Reading()
        for s in services {
            guard let name = hidServiceCopyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = hidServiceCopyEvent(s, Int64(kTemperatureEvent), 0, 0)?.takeRetainedValue() else { continue }
            let t = hidEventGetFloatValue(event, kTemperatureEvent << 16)
            guard t > 0, t < 150 else { continue }   // unused channels report large negative values
            if name.hasPrefix("gas gauge battery") { r.battery = max(r.battery ?? t, t) }
            else if name.hasPrefix("PMU tdie") { r.chip = max(r.chip ?? t, t) }
        }
        return r
    }
}

private let kTemperatureEvent: Int32 = 15
@_silgen_name("IOHIDEventSystemClientCreate")
private func hidClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventSystemClientSetMatching")
private func hidClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices")
private func hidClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty")
private func hidServiceCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDServiceClientCopyEvent")
private func hidServiceCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventGetFloatValue")
private func hidEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double
