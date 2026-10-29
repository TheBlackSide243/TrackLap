import Foundation
import CoreLocation
import Observation

enum LocationError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Accesso alla posizione negato: abilitalo in Impostazioni → TrackLap → Posizione."
    }
}

/// The iPhone's own GPS: about 1 Hz, fine for trying the app and for marking the line on foot.
@Observable
final class PhoneGPS: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var accuracy: Double? = nil
    @ObservationIgnored var onSample: ((Sample) -> Void)? = nil

    private let manager = CLLocationManager()
    @ObservationIgnored private var streaming = false
    @ObservationIgnored private var waiting: [CheckedContinuation<CLLocation, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .otherNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    func start() {
        streaming = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    func stop() {
        streaming = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func currentLocation() async throws -> CLLocation {
        if let l = manager.location, l.timestamp.timeIntervalSinceNow > -5 { return l }
        return try await withCheckedThrowingContinuation { c in
            waiting.append(c)
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: fail(LocationError.denied)
            default: manager.requestLocation()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if !waiting.isEmpty { manager.requestLocation() }
        case .denied, .restricted:
            fail(LocationError.denied)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let l = locations.last, !waiting.isEmpty {
            let w = waiting
            waiting = []
            w.forEach { $0.resume(returning: l) }
        }
        guard streaming else { return }
        for l in locations where l.horizontalAccuracy >= 0 {
            accuracy = l.horizontalAccuracy
            onSample?(Sample(t: l.timestamp.timeIntervalSince1970, coord: Coord(l.coordinate),
                             speed: max(0, l.speed), heading: l.course >= 0 ? l.course : 0))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fail(error)
    }

    private func fail(_ e: Error) {
        let w = waiting
        waiting = []
        w.forEach { $0.resume(throwing: e) }
    }
}
