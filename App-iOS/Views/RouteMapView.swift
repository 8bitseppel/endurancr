import SwiftUI
import MapKit
import HealthKit

/// Draws a recorded run's GPS route on an Apple Maps (MapKit) view. Give it a
/// HealthKit workout; it loads the route coordinates and renders them as a polyline.
/// Shows nothing but the map if the run has no route (e.g. an indoor treadmill run).
struct RouteMapView: View {
    let workout: HKWorkout
    let health: HealthKitService

    @State private var coordinates: [CLLocationCoordinate2D] = []
    @State private var loaded = false

    var body: some View {
        Map {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let start = coordinates.first {
                Marker("Start", systemImage: "flag", coordinate: start)
                    .tint(.green)
            }
            if let finish = coordinates.last, coordinates.count > 1 {
                Marker("Finish", systemImage: "flag.checkered", coordinate: finish)
                    .tint(.red)
            }
        }
        .overlay {
            if loaded && coordinates.isEmpty {
                ContentUnavailableView("No route", systemImage: "mappin.slash",
                    description: Text("This run wasn't recorded with GPS."))
            }
        }
        .task(id: workout.uuid) {
            coordinates = await health.routeCoordinates(for: workout)
            loaded = true
        }
    }
}
