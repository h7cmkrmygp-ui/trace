import CoreLocation
import EngramCore
import EngramStore
import MapKit
import SwiftUI

// P14 — rappels de lieu : l'adresse d'un lieu, la carte, et le rappel d'une note (« en arrivant · Costco »).

extension PlaceEvent {
    /// « En arrivant », « En partant ».
    var title: String { self == .arrive ? "En arrivant" : "En partant" }
    var symbol: String { self == .arrive ? "location.fill" : "figure.walk.departure" }
}

enum PlaceRadius {
    static let choices: [Double] = [100, 200, 500]

    static func text(_ radius: Double) -> String { "\(Int(radius.rounded())) m" }
}

/// Une petite carte fixe : le lieu et le cercle où le rappel se déclenche.
struct PlaceMap: View {
    let latitude: Double
    let longitude: Double
    let radius: Double
    let name: String

    private var center: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    var body: some View {
        let span = max(radius * 5, 600)
        Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)),
            interactionModes: []) {
            MapCircle(center: center, radius: radius)
                .foregroundStyle(Color.indigo.opacity(0.15))
                .stroke(Color.indigo, lineWidth: 1.5)
            Marker(name, systemImage: "mappin", coordinate: center)
                .tint(.indigo)
        }
        .mapControlVisibility(.hidden)
        .id("\(latitude),\(longitude),\(radius)")
        .accessibilityLabel("Carte de \(name)")
    }
}

/// Ajouter ou changer l'adresse d'un lieu : ma position actuelle, ou une recherche (Plans d'Apple).
struct PlaceAddressSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let placeID: UUID
    let placeName: String
    let current: PlaceLocation?

    struct Choice: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let address: String?
        let latitude: Double
        let longitude: Double
    }

    @State private var query = ""
    @State private var results: [Choice] = []
    @State private var chosen: Choice?
    @State private var radius: Double = 200
    @State private var isSearching = false
    @State private var isLocating = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if let chosen {
                    Section {
                        PlaceMap(latitude: chosen.latitude, longitude: chosen.longitude, radius: radius, name: placeName)
                            .frame(height: 180)
                            .listRowInsets(EdgeInsets())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chosen.name).font(.headline)
                            if let address = chosen.address {
                                Text(address).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        Picker("Rayon", selection: $radius) {
                            ForEach(PlaceRadius.choices, id: \.self) { Text(PlaceRadius.text($0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Me prévenir à moins de")
                    } footer: {
                        Text("Un petit rayon pour un commerce, un plus grand pour un quartier.")
                    }
                }
                Section {
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        HStack {
                            Label("Ma position actuelle", systemImage: "location.fill")
                            if isLocating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLocating)
                } footer: {
                    Text("Tu es sur place ? C'est le plus précis, et rien n'est envoyé.")
                }
                if isSearching {
                    Section { HStack { Spacer(); ProgressView(); Spacer() } }
                } else if !results.isEmpty {
                    Section("Résultats") {
                        ForEach(results) { result in
                            Button {
                                chosen = result
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).foregroundStyle(.primary)
                                    if let address = result.address {
                                        Text(address).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityAddTraits(chosen == result ? .isSelected : [])
                        }
                    }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Chercher une adresse")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle(placeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(chosen == nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("La recherche passe par Plans d'Apple : seulement ce que tu tapes, jamais tes notes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            .onAppear {
                radius = current?.radius ?? 200
                if let current {
                    chosen = Choice(name: current.label ?? placeName, address: nil, latitude: current.latitude,
                                    longitude: current.longitude)
                }
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSearching = true
        message = nil
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems.prefix(8).map { item in
                let coordinate = item.location.coordinate
                return Choice(name: item.name ?? text, address: item.address?.shortAddress ?? item.address?.fullAddress,
                              latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
            if results.isEmpty { message = "Aucun résultat pour « \(text) »." }
        } catch {
            results = []
            message = "La recherche n'a pas fonctionné. Vérifie ta connexion, ou utilise ta position actuelle."
        }
    }

    private func useCurrentLocation() async {
        isLocating = true
        message = nil
        defer { isLocating = false }
        do {
            let location = try await LocationAccess.shared.currentLocation()
            chosen = Choice(name: "Ma position actuelle", address: nil, latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude)
        } catch {
            message = "Position introuvable. Autorise Engram dans Réglages › Confidentialité › Service de localisation."
        }
    }

    private func save() {
        guard let chosen else { return }
        let label = chosen.address ?? (chosen.name == "Ma position actuelle" ? nil : chosen.name)
        model.perform {
            try model.entities.setLocation(placeID, latitude: chosen.latitude, longitude: chosen.longitude, radius: radius,
                                           label: label)
        }
        Task {
            // iOS ne prévient en arrivant que si Engram a le droit à la position (« Lorsque l'app est active » suffit).
            await LocationAccess.shared.requestWhenInUse()
            await model.askForPlaceRemindersIfNeeded()
        }
        dismiss()
    }
}

/// Poser un rappel de lieu à la main : un lieu connu ou nouveau, en arrivant ou en partant.
struct PlaceTriggerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memoryID: UUID
    @State private var event: PlaceEvent = .arrive
    @State private var places: [EngramEntity] = []
    @State private var name = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Quand", selection: $event) {
                        ForEach(PlaceEvent.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Engram te rappelle cette note quand tu arrives à ce lieu (ou quand tu en pars).")
                }
                Section("Nouveau lieu") {
                    TextField("Nom du lieu (ex. : épicerie)", text: $name)
                        .submitLabel(.done)
                        .onSubmit(chooseNew)
                    if !trimmedName.isEmpty {
                        Button("Utiliser « \(trimmedName) »", systemImage: "plus.circle", action: chooseNew)
                    }
                }
                if !places.isEmpty {
                    Section("Tes lieux") {
                        ForEach(places) { place in
                            Button {
                                model.perform { try model.entities.setPlaceTrigger(for: memoryID, placeID: place.id, event: event) }
                                finish()
                            } label: {
                                HStack(spacing: 12) {
                                    EntityAvatar(entity: place, size: 28)
                                    Text(place.name).foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rappel de lieu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
            }
            .task {
                places = (try? model.entities.allEntities(kind: .place)) ?? []
                event = (try? model.entities.placeTrigger(for: memoryID))?.trigger.event ?? .arrive
            }
        }
    }

    private func chooseNew() {
        guard !trimmedName.isEmpty else { return }
        model.perform { try model.entities.setPlaceTrigger(for: memoryID, placeNamed: trimmedName, event: event) }
        finish()
    }

    private func finish() {
        Task {
            // P30 : le lieu choisi sans adresse est cherché tout de suite autour de toi.
            await model.locateMissingPlaces(askPermission: true)
            await model.askForPlaceRemindersIfNeeded()
        }
        dismiss()
    }
}

/// La position de l'iPhone, demandée seulement quand le propriétaire en a besoin (jamais suivie en arrière-plan par
/// Engram : c'est iOS qui surveille les lieux des rappels).
@MainActor
final class LocationAccess: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAccess()

    enum Failure: Error { case denied, unavailable }

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    /// Demande « Lorsque l'app est active » une seule fois ; attend la réponse.
    func requestWhenInUse() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Une position assez précise (moins de 50 m), ou la meilleure des premières.
    func currentLocation() async throws -> CLLocation {
        await requestWhenInUse()
        guard isAuthorized else { throw Failure.denied }
        var best: CLLocation?
        var count = 0
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied { throw Failure.denied }
            guard let location = update.location, location.horizontalAccuracy >= 0 else { continue }
            if best.map({ location.horizontalAccuracy < $0.horizontalAccuracy }) ?? true { best = location }
            count += 1
            if location.horizontalAccuracy <= 50 || count >= 6 { break }
        }
        guard let best else { throw Failure.unavailable }
        return best
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        Task { @MainActor in self.resumeWaiters() }
    }

    private func resumeWaiters() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

/// P30 — chercher un lieu autour du propriétaire (Plans d'Apple : seulement le nom du lieu et la zone, jamais une note).
enum PlaceSearch {
    /// Les commerces et lieux trouvés ; [] s'il n'y en a aucun, nil si la recherche n'a pas pu se faire (réseau).
    @MainActor
    static func search(_ text: String, near center: CLLocationCoordinate2D, span: Double = 60_000) async -> [PlaceFinder.Result]? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.map { item in
                PlaceFinder.Result(name: item.name ?? text, address: item.address?.shortAddress ?? item.address?.fullAddress,
                                   latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude)
            }
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        } catch {
            return nil
        }
    }
}
