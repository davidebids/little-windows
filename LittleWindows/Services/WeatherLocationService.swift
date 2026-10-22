import CoreLocation
import Foundation
import MapKit

@MainActor
protocol WeatherLocationClient {
    func currentCity(requestAuthorization: Bool) async throws -> TripDestinationSelection
    func resolveCity(_ location: TripDestinationSelection) async throws -> TripDestinationSelection
}

enum WeatherLocationFailure: Error, Equatable {
    case permissionRequired
    case denied
    case unavailable

    var message: String {
        switch self {
        case .permissionRequired: "Use your current location or choose a city for local weather."
        case .denied: "Location access is off. Allow it in Settings or choose a city instead."
        case .unavailable: "Your location couldn't be found. Try again or choose a city."
        }
    }
}

enum WeatherCityNaming {
    static func name(locality: String?, district: String?, region: String?, fallback: String) -> String {
        [locality, district, region, fallback].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !isPostalCode($0) } ?? "Selected city"
    }

    static func isPostalCode(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.allSatisfy { $0.isNumber || $0 == "-" || $0.isWhitespace }
    }
}

/// One foreground location request; no continuous or background location tracking.
@MainActor
final class LiveWeatherLocationClient: NSObject, WeatherLocationClient, @preconcurrency CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeout: Task<Void, Never>?
    private var isRequestingFix = false

    func currentCity(requestAuthorization: Bool) async throws -> TripDestinationSelection {
        let location: CLLocation = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
                guard self.continuation == nil else {
                    continuation.resume(throwing: WeatherLocationFailure.unavailable)
                    return
                }
                let manager = self.manager ?? CLLocationManager()
                self.manager = manager
                self.continuation = continuation
                manager.delegate = self
                manager.desiredAccuracy = kCLLocationAccuracyKilometer
                switch manager.authorizationStatus {
                case .notDetermined:
                    if requestAuthorization {
                        manager.requestWhenInUseAuthorization()
                    } else {
                        finish(.failure(WeatherLocationFailure.permissionRequired))
                    }
                case .authorizedAlways, .authorizedWhenInUse:
                    requestFix(manager)
                case .denied, .restricted:
                    finish(.failure(WeatherLocationFailure.denied))
                @unknown default:
                    finish(.failure(WeatherLocationFailure.unavailable))
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
        try Task.checkCancellation()
        // Weather needs a city-scale position, not a precise saved coordinate.
        let approximate = CLLocation(
            latitude: (location.coordinate.latitude * 100).rounded() / 100,
            longitude: (location.coordinate.longitude * 100).rounded() / 100
        )
        let initial = TripDestinationSelection(
            name: "Current location", latitude: approximate.coordinate.latitude,
            longitude: approximate.coordinate.longitude, timeZoneIdentifier: TimeZone.current.identifier
        )
        return (try? await resolveCity(initial)) ?? initial
    }

    func resolveCity(_ location: TripDestinationSelection) async throws -> TripDestinationSelection {
        guard let latitude = location.latitude, let longitude = location.longitude else { return location }
        let places = try await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
        try Task.checkCancellation()
        guard let place = places.first else { return location }
        var resolved = location
        resolved.name = WeatherCityNaming.name(
            locality: place.locality, district: place.subAdministrativeArea,
            region: place.administrativeArea, fallback: location.name
        )
        resolved.detail = [place.administrativeArea, place.country].compactMap { $0 }.joined(separator: ", ")
        resolved.timeZoneIdentifier = place.timeZone?.identifier ?? location.timeZoneIdentifier
        return resolved
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: requestFix(manager)
        case .denied, .restricted: finish(.failure(WeatherLocationFailure.denied))
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 10 * 60 else {
            finish(.failure(WeatherLocationFailure.unavailable))
            return
        }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let failure: WeatherLocationFailure = (error as? CLError)?.code == .denied ? .denied : .unavailable
        finish(.failure(failure))
    }

    private func requestFix(_ manager: CLLocationManager) {
        guard !isRequestingFix else { return }
        isRequestingFix = true
        manager.requestLocation()
        timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            finish(.failure(WeatherLocationFailure.unavailable))
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        let pending = continuation
        continuation = nil
        timeout?.cancel()
        timeout = nil
        isRequestingFix = false
        manager?.stopUpdatingLocation()
        pending?.resume(with: result)
    }
}

enum WeatherCitySearch {
    static func search(_ query: String) async throws -> [TripDestinationSelection] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        let response = try await MKLocalSearch(request: request).start()
        try Task.checkCancellation()
        var seen = Set<String>()
        return response.mapItems.compactMap { item in
            let place = item.placemark
            let city = WeatherCityNaming.name(
                locality: place.locality, district: place.subAdministrativeArea,
                region: place.administrativeArea, fallback: item.name ?? query
            )
            let detail = [place.administrativeArea, place.country].compactMap { $0 }.joined(separator: ", ")
            guard seen.insert("\(city)|\(detail)").inserted else { return nil }
            return TripDestinationSelection(
                name: city, detail: detail,
                latitude: place.coordinate.latitude, longitude: place.coordinate.longitude,
                timeZoneIdentifier: place.timeZone?.identifier
            )
        }
        .prefix(8).map { $0 }
    }
}
