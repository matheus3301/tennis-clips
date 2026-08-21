@preconcurrency import MapKit
import CoreLocation
import Foundation

@MainActor
struct SessionLocationResolver: SessionLocationResolving {
    func resolve(latitude: Double, longitude: Double) async -> ResolvedSessionLocation? {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "clube de tênis"
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 1_500,
            longitudinalMeters: 1_500
        )

        if let response = try? await MKLocalSearch(request: request).start(),
           let nearest = response.mapItems
            .compactMap({ item -> (MKMapItem, CLLocationDistance)? in
                guard let location = item.placemark.location else { return nil }
                let distance = location.distance(from: CLLocation(
                    latitude: latitude,
                    longitude: longitude
                ))
                return distance <= 600 ? (item, distance) : nil
            })
            .min(by: { $0.1 < $1.1 })?.0 {
            return ResolvedSessionLocation(
                name: nearest.name,
                locality: nearest.placemark.locality
                    ?? nearest.placemark.subAdministrativeArea
            )
        }

        let location = CLLocation(latitude: latitude, longitude: longitude)
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first else {
                return nil
            }
            return ResolvedSessionLocation(
                name: nil,
                locality: item.addressRepresentations?.cityName
                    ?? item.addressRepresentations?.regionName
            )
        }

        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        return ResolvedSessionLocation(
            name: nil,
            locality: placemark.locality ?? placemark.subAdministrativeArea
        )
    }
}
