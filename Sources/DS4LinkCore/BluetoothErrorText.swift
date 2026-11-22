import Foundation

/// IOKit return codes are C macros Swift cannot import, so the ones this app needs live here.
public enum IOCode {
    public static let success: Int32 = 0
    public static let error = Int32(bitPattern: 0xE00002BC)
    public static let noDevice = Int32(bitPattern: 0xE00002C0)
    public static let busy = Int32(bitPattern: 0xE00002D5)
    public static let timeout = Int32(bitPattern: 0xE00002D6)
    public static let notPermitted = Int32(bitPattern: 0xE00002E2)

    public static func hex(_ code: Int32) -> String {
        "0x" + String(UInt32(bitPattern: code), radix: 16, uppercase: true)
    }
}

/// Plain-language reasons for pairing and connection failures. IOBluetooth reports either an
/// IOKit code or a raw Bluetooth HCI status, so both ranges are covered.
public enum BluetoothErrorText {
    public static func describe(_ code: Int32) -> String {
        switch UInt32(bitPattern: code) {
        case 0x00: return "It worked"
        case 0x04: return "The controller stopped listening"
        case 0x05, 0x06: return "The controller refused the pairing"
        case 0x08, 0x22: return "The controller did not answer in time"
        case 0x0D, 0x0E, 0x0F: return "The controller rejected the connection"
        case 0x13, 0x15, 0x16: return "The connection was closed"
        case 0x18, 0x25, 0x29: return "The controller is not in pairing mode"
        case 0x1F: return "Bluetooth reported an unspecified error"
        case 0xE00002C0: return "The controller was not found"
        case 0xE00002D5: return "Bluetooth was busy"
        case 0xE00002D6: return "Pairing timed out"
        case 0xE00002E2: return "macOS did not allow the connection"
        case 0xE00002BC: return "Bluetooth reported an error"
        default: return "Bluetooth reported error \(IOCode.hex(code))"
        }
    }
}
