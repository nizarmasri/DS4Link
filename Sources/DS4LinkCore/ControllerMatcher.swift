import Foundation

/// Decides whether a Bluetooth device is a game controller, from its Class of Device
/// (available the instant an inquiry sees it) or its name (may arrive later, or be cached).
public enum ControllerMatcher {
    private static let nameHints = [
        "wireless controller",   // DualShock 4 advertises exactly this; DualSense contains it
        "dualshock",
        "dualsense",
        "gamepad",
        "game controller",
        "pro controller",
        "joy-con",
        "xbox",
    ]

    /// Major device class, bits 8-12 of the Class of Device.
    public static func majorClass(_ cod: UInt32) -> UInt32 { (cod >> 8) & 0x1F }

    /// Minor device class, bits 2-7 of the Class of Device.
    public static func minorClass(_ cod: UInt32) -> UInt32 { (cod >> 2) & 0x3F }

    /// Peripheral major class with a joystick (1) or gamepad (2) minor. A DualShock 4 is 0x002508.
    public static func classSaysController(_ cod: UInt32) -> Bool {
        guard majorClass(cod) == 0x05 else { return false }
        let kind = minorClass(cod) & 0x0F
        return kind == 0x01 || kind == 0x02
    }

    /// Peripheral major class flagged as keyboard and/or pointing device with no gamepad bits.
    public static func classSaysKeyboardOrMouse(_ cod: UInt32) -> Bool {
        guard majorClass(cod) == 0x05 else { return false }
        let minor = minorClass(cod)
        return (minor & 0x30) != 0 && (minor & 0x0F) == 0
    }

    public static func nameSaysController(_ name: String?) -> Bool {
        guard let name = name?.lowercased(), !name.isEmpty else { return false }
        return nameHints.contains { name.contains($0) }
    }

    public static func isGameController(name: String?, classOfDevice cod: UInt32) -> Bool {
        if classSaysController(cod) { return true }
        if classSaysKeyboardOrMouse(cod) { return false }
        return nameSaysController(name)
    }

    /// A name fit for the window title. A DualShock 4 calls itself just "Wireless Controller".
    public static func displayName(_ name: String?) -> String {
        guard let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "Wireless Controller"
        }
        let lower = raw.lowercased()
        if lower == "wireless controller" || lower.contains("dualshock") { return "DualShock 4" }
        if lower.contains("dualsense") { return lower.contains("edge") ? "DualSense Edge" : "DualSense" }
        return raw
    }
}
