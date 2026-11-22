import CoreBluetooth
import Foundation
import IOBluetooth
import DS4LinkCore

/// Tracks the two things that must be true before any Bluetooth call can work: the user has
/// allowed the app to use Bluetooth, and the radio is switched on. CoreBluetooth is the only
/// public API that reports both and notifies on change, so it is used purely as a sensor here.
final class BluetoothAuthority: NSObject, CBCentralManagerDelegate {
    var onChange: (() -> Void)?
    private var manager: CBCentralManager?

    /// Creating the manager is what makes macOS show the Bluetooth permission prompt.
    func start() {
        guard manager == nil else { return }
        manager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    var auth: AuthState {
        switch CBCentralManager.authorization {
        case .allowedAlways: return .allowed
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    var power: PowerState {
        switch manager?.state {
        case .poweredOn: return .on
        case .poweredOff: return .off
        case .unsupported: return .unsupported
        default: break
        }
        // CoreBluetooth has not reported yet (or is resetting): ask the classic stack directly.
        guard auth == .allowed, let controller = IOBluetoothHostController.default() else { return .unknown }
        return controller.powerState == kBluetoothHCIPowerStateON ? .on : .off
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Log.info("bluetooth state: auth=\(auth) power=\(power)")
        onChange?()
    }
}
