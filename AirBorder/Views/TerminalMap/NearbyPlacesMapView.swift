import MapKit
import SwiftUI

/// A geographic map for nearby layover places. MapKit owns collision handling
/// and groups dense markers until the passenger zooms in.
struct NearbyPlacesMapView: UIViewRepresentable {
    private enum CameraDefaults {
        /// Avoids an unusably close camera when one result (or colocated results) is shown.
        static let minimumUsefulSpanMapPoints = 1_000.0
        /// Keeps a single nearby result in recognizable airport context.
        static let singlePlaceRegionMeters = 4_000.0
        static let contentPadding = UIEdgeInsets(top: 64, left: 44, bottom: 64, right: 44)
    }

    let places: [LayoverPlace]
    @Binding var selectedPlaceID: String?
    var routes: [MKRoute] = []

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedPlaceID: $selectedPlaceID)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.mapType = .mutedStandard
        mapView.pointOfInterestFilter = .excludingAll
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Coordinator.placeReuseIdentifier
        )
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Coordinator.clusterReuseIdentifier
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.selectedPlaceID = $selectedPlaceID

        let visiblePlaces = places.filter { $0.coordinate != nil }
        let fingerprint = visiblePlaces.map {
            "\($0.id)|\($0.latitude ?? 0)|\($0.longitude ?? 0)|\($0.category.rawValue)|\($0.name)"
        }.sorted().joined(separator: "|")
        let routeFingerprint = routes.map {
            "\($0.distance)|\($0.expectedTravelTime)|\($0.polyline.pointCount)"
        }.joined(separator: "|")
        let combinedFingerprint = "\(fingerprint)#\(routeFingerprint)"
        guard combinedFingerprint != context.coordinator.fingerprint else {
            context.coordinator.syncSelection(on: mapView)
            return
        }

        context.coordinator.fingerprint = combinedFingerprint
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        let annotations = visiblePlaces.compactMap(NearbyPlaceAnnotation.init)
        mapView.addAnnotations(annotations)
        mapView.addOverlays(routes.map(\.polyline))

        guard !annotations.isEmpty || !routes.isEmpty else { return }
        context.coordinator.show(
            annotations: annotations,
            routes: routes,
            on: mapView,
            animated: context.coordinator.hasShownInitialRegion
        )
        context.coordinator.hasShownInitialRegion = true
        context.coordinator.syncSelection(on: mapView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let placeReuseIdentifier = "nearby-place"
        static let clusterReuseIdentifier = "nearby-place-cluster"

        var selectedPlaceID: Binding<String?>
        var fingerprint = ""
        var hasShownInitialRegion = false

        init(selectedPlaceID: Binding<String?>) {
            self.selectedPlaceID = selectedPlaceID
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(
                    withIdentifier: Self.clusterReuseIdentifier,
                    for: cluster
                ) as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: Self.clusterReuseIdentifier)
                view.annotation = cluster
                view.markerTintColor = UIColor(AirportXRPalette.actionTeal)
                view.glyphText = String(cluster.memberAnnotations.count)
                view.titleVisibility = .hidden
                view.subtitleVisibility = .hidden
                view.displayPriority = .required
                return view
            }

            guard let place = annotation as? NearbyPlaceAnnotation else { return nil }
            let view = (mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.placeReuseIdentifier,
                for: place
            ) as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(annotation: place, reuseIdentifier: Self.placeReuseIdentifier)
            view.annotation = place
            view.clusteringIdentifier = "nearby-places"
            view.collisionMode = .circle
            view.displayPriority = .defaultHigh
            view.canShowCallout = true
            view.titleVisibility = .adaptive
            view.subtitleVisibility = .adaptive
            view.markerTintColor = UIColor(AirportXRPalette.actionTeal)
            view.glyphImage = UIImage(systemName: PlaceCategorySymbol.name(for: place.category))
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                show(annotations: cluster.memberAnnotations, routes: [], on: mapView, animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
                return
            }
            guard let place = annotation as? NearbyPlaceAnnotation else { return }
            selectedPlaceID.wrappedValue = place.placeID
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(AirportXRPalette.actionTeal)
            renderer.lineWidth = 5
            renderer.lineJoin = .round
            renderer.lineCap = .round
            return renderer
        }

        func syncSelection(on mapView: MKMapView) {
            guard let selectedID = selectedPlaceID.wrappedValue,
                  let annotation = mapView.annotations
                    .compactMap({ $0 as? NearbyPlaceAnnotation })
                    .first(where: { $0.placeID == selectedID }) else { return }
            if !mapView.selectedAnnotations.contains(where: { ($0 as? NearbyPlaceAnnotation) === annotation }) {
                mapView.selectAnnotation(annotation, animated: true)
            }
        }

        func show(annotations: [MKAnnotation], routes: [MKRoute], on mapView: MKMapView, animated: Bool) {
            var rect = MKMapRect.null
            for annotation in annotations {
                let point = MKMapPoint(annotation.coordinate)
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
            }
            for route in routes {
                rect = rect.union(route.polyline.boundingMapRect)
            }
            guard !rect.isNull else { return }
            if rect.width < CameraDefaults.minimumUsefulSpanMapPoints || rect.height < CameraDefaults.minimumUsefulSpanMapPoints {
                let center = annotations.first?.coordinate
                    ?? routes.first?.polyline.coordinate
                    ?? mapView.centerCoordinate
                let region = MKCoordinateRegion(
                    center: center,
                    latitudinalMeters: CameraDefaults.singlePlaceRegionMeters,
                    longitudinalMeters: CameraDefaults.singlePlaceRegionMeters
                )
                mapView.setRegion(region, animated: animated)
            } else {
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: CameraDefaults.contentPadding,
                    animated: animated
                )
            }
        }
    }
}

private final class NearbyPlaceAnnotation: NSObject, MKAnnotation {
    let placeID: String
    let category: LayoverPlaceCategory
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init?(_ place: LayoverPlace) {
        guard let coordinate = place.coordinate else { return nil }
        placeID = place.id
        category = place.category
        self.coordinate = coordinate
        title = place.name
        subtitle = place.category.title
    }
}
