import Foundation
import Observation

@MainActor
@Observable
final class WarehouseStore {
    private(set) var warehouses: [Warehouse] = []
    private(set) var refreshingIDs: Set<UUID> = []
    private(set) var lastPersistenceError: String?
    private let storageURL: URL
    private let loader: SubscriptionLoader
    private var defaultsInstalled = false
    private var installedPresetVersion = 0
    private struct Snapshot: Codable {
        var warehouses: [Warehouse]
        var defaultsInstalled: Bool
        var installedPresetVersion: Int?
    }

    init(storageURL: URL? = nil, loader: SubscriptionLoader = SubscriptionLoader(), includeDefaults: Bool = true) {
        self.loader = loader
        self.storageURL = storageURL ?? Self.defaultStorageURL
        let restored = restore()
        if restored && includeDefaults && installedPresetVersion < DefaultSubscriptions.version {
            addDefaultSubscriptions(since: installedPresetVersion)
        }
    }

    func importURL(_ text: String, kind: SubscriptionKind, name: String) async throws {
        guard let url = URL(string: text), url.host != nil, ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw URLError(.badURL)
        }
        let matching = warehouses.first { $0.configURL == url && $0.kind == kind }
        let warehouse = try await loader.load(from: url, kind: kind, name: name, replacing: matching)
        if let index = warehouses.firstIndex(where: { $0.id == warehouse.id }) {
            warehouses[index] = warehouse
        } else {
            warehouses.append(warehouse)
        }
        try save()
    }

    func refresh(id: UUID) async throws {
        guard let index = warehouses.firstIndex(where: { $0.id == id }) else { return }
        let old = warehouses[index]
        refreshingIDs.insert(id)
        defer { refreshingIDs.remove(id) }
        let refreshed = try await loader.load(from: old.configURL, kind: old.kind, replacing: old)
        guard let currentIndex = warehouses.firstIndex(where: { $0.id == id }) else { return }
        warehouses[currentIndex] = refreshed
        try save()
    }

    func refreshAll() async -> [String] {
        var failures: [String] = []
        for warehouse in warehouses {
            do { try await refresh(id: warehouse.id) }
            catch { failures.append("\(warehouse.name)：\(error.localizedDescription)") }
        }
        return failures
    }

    func delete(at offsets: IndexSet) {
        warehouses.remove(atOffsets: offsets)
        do { try save() }
        catch { lastPersistenceError = error.localizedDescription }
    }

    func delete(id: UUID) {
        guard let index = warehouses.firstIndex(where: { $0.id == id }) else { return }
        delete(at: IndexSet(integer: index))
    }

    func delete(at offsets: IndexSet, kind: SubscriptionKind) {
        let slots = warehouses.indices.filter { warehouses[$0].kind == kind }
        delete(at: IndexSet(offsets.compactMap { slots.indices.contains($0) ? slots[$0] : nil }))
    }

    func move(from offsets: IndexSet, to destination: Int, kind: SubscriptionKind) {
        let slots = warehouses.indices.filter { warehouses[$0].kind == kind }
        var group = slots.map { warehouses[$0] }
        group.move(fromOffsets: offsets, toOffset: destination)
        for (slot, value) in zip(slots, group) { warehouses[slot] = value }
        do { try save() }
        catch { lastPersistenceError = error.localizedDescription }
    }

    func addDefaultSubscriptions(since version: Int = 0) {
        for preset in DefaultSubscriptions.make(since: version) where !warehouses.contains(where: {
            $0.kind == preset.kind && DefaultSubscriptions.matches($0.configURL, preset.configURL)
        }) {
            warehouses.append(preset)
        }
        defaultsInstalled = true
        installedPresetVersion = DefaultSubscriptions.version
        do { try save() }
        catch { lastPersistenceError = error.localizedDescription }
    }

    func clearPersistenceError() { lastPersistenceError = nil }

    private func save() throws {
        let data = try JSONEncoder().encode(Snapshot(warehouses: warehouses, defaultsInstalled: defaultsInstalled, installedPresetVersion: installedPresetVersion))
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: storageURL, options: .atomic)
    }

    private func restore() -> Bool {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return true }
        do {
            let data = try Data(contentsOf: storageURL)
            if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                warehouses = snapshot.warehouses
                defaultsInstalled = snapshot.defaultsInstalled
                installedPresetVersion = snapshot.installedPresetVersion ?? (defaultsInstalled ? 1 : 0)
            } else {
                // Preserve subscriptions saved before default presets were introduced.
                warehouses = try JSONDecoder().decode([Warehouse].self, from: data)
            }
            return true
        } catch {
            lastPersistenceError = "读取订阅失败：\(error.localizedDescription)"
            return false
        }
    }

    private static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TVBoxiOS", isDirectory: true)
            .appendingPathComponent("subscriptions-v2.json")
    }
}
