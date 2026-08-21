import Foundation

@MainActor
protocol SessionLocationResolving {
    func resolve(latitude: Double, longitude: Double) async -> ResolvedSessionLocation?
}
