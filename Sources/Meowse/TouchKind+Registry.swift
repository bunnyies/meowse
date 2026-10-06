import Foundation
import IOKit
import IOKit.hid
import MeowseCore

extension TouchKind {
    /// Looks up the touch surface with this registry ID. Its properties sit on
    /// the device or on the driver above it.
    init?(registryID: UInt64) {
        guard registryID != 0 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        func property(_ key: String) -> String? {
            IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as NSString, kCFAllocatorDefault,
                                            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? String
        }
        self.init(scrollAcceleration: property(kIOHIDScrollAccelerationTypeKey), product: property(kIOHIDProductKey))
    }
}
