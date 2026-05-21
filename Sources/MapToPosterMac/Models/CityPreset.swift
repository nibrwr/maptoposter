import Foundation

struct CityPreset: Identifiable, Hashable {
    let id = UUID()
    let locationQuery: String
    let city: String
    let country: String
    let themeSlug: String
    let distance: Int

    static let samples: [CityPreset] = [
        CityPreset(locationQuery: "94103", city: "San Francisco", country: "USA", themeSlug: "sunset", distance: 10000),
        CityPreset(locationQuery: "Venice, Italy", city: "Venice", country: "Italy", themeSlug: "blueprint", distance: 4000),
        CityPreset(locationQuery: "Tokyo, Japan", city: "Tokyo", country: "Japan", themeSlug: "japanese_ink", distance: 15000),
        CityPreset(locationQuery: "Barcelona, Spain", city: "Barcelona", country: "Spain", themeSlug: "warm_beige", distance: 8000),
        CityPreset(locationQuery: "New York, NY", city: "New York", country: "USA", themeSlug: "noir", distance: 12000)
    ]
}
