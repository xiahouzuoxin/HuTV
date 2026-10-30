import Foundation
import Observation

enum SubscriptionEditError: LocalizedError {
    case missing, duplicate, changed
    var errorDescription: String? {
        switch self {
        case .missing: "此订阅已被删除。"
        case .duplicate: "相同类型的订阅地址已存在，请编辑已有订阅。"
        case .changed: "订阅已在其他操作中修改，请关闭后重新打开。"
        }
    }
}

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

    func update(id: UUID, name: String, address: String) async throws {
        guard let old = warehouses.first(where: { $0.id == id }) else { throw SubscriptionEditError.missing }
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.host != nil, ["http", "https"].contains(url.scheme?.lowercased()) else { throw URLError(.badURL) }
        func duplicate() -> Bool {
            warehouses.contains { $0.id != id && $0.kind == old.kind && DefaultSubscriptions.matches($0.configURL, url) }
        }
        guard !duplicate() else { throw SubscriptionEditError.duplicate }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedName.isEmpty ? old.name : trimmedName
        var replacement: Warehouse
        if url == old.configURL {
            replacement = old
            replacement.name = title
            if old.kind == .cms, replacement.config.sites.count == 1 { replacement.config.sites[0].name = title }
            if old.kind == .live, replacement.config.lives.count == 1 { replacement.config.lives[0].name = title }
        } else {
            var original = old
            original.etag = nil; original.lastModified = nil
            replacement = try await loader.load(from: url, kind: old.kind, name: title, replacing: original)
        }
        try Task.checkCancellation()
        guard let index = warehouses.firstIndex(where: { $0.id == id }) else { throw SubscriptionEditError.missing }
        guard warehouses[index].configURL == old.configURL, warehouses[index].name == old.name else { throw SubscriptionEditError.changed }
        guard !duplicate() else { throw SubscriptionEditError.duplicate }
        let previous = warehouses[index]
        warehouses[index] = replacement
        do { try save() }
        catch { warehouses[index] = previous; throw error }
    }

    func importBatch(_ entries: [BatchSubscriptionEntry]) async throws -> [BatchImportOutcome] {
        var outcomes: [Int: BatchImportOutcome] = [:]
        var pending: [BatchSubscriptionEntry] = []
        var seen = Set<String>()
        for entry in entries {
            guard let kind = entry.kind, entry.issue == nil, let url = URL(string: entry.address) else {
                outcomes[entry.id] = BatchImportOutcome(id: entry.id, name: entry.name, status: .skipped, message: entry.issue ?? "地址无效")
                continue
            }
            let key = kind.rawValue + "|" + DefaultSubscriptions.canonicalKey(url)
            if !seen.insert(key).inserted || warehouses.contains(where: { $0.kind == kind && DefaultSubscriptions.matches($0.configURL, url) }) {
                outcomes[entry.id] = BatchImportOutcome(id: entry.id, name: entry.name, status: .skipped, message: "相同订阅已存在，保留原名称和顺序")
            } else { pending.append(entry) }
        }
        let loader = self.loader
        let loaded = await withTaskGroup(of: (BatchSubscriptionEntry, Warehouse?, String?).self) { tasks in
            var iterator = pending.makeIterator()
            func enqueue(_ entry: BatchSubscriptionEntry) {
                tasks.addTask {
                    do {
                        let value = try await loader.load(from: URL(string: entry.address)!, kind: entry.kind!, name: entry.name)
                        return (entry, value, nil)
                    } catch { return (entry, nil, error.localizedDescription) }
                }
            }
            for _ in 0..<4 { if let entry = iterator.next() { enqueue(entry) } }
            var results: [Int: Warehouse] = [:]
            for await (entry, warehouse, error) in tasks {
                if Task.isCancelled { tasks.cancelAll(); break }
                if let warehouse { results[entry.id] = warehouse }
                else { outcomes[entry.id] = BatchImportOutcome(id: entry.id, name: entry.name, status: .failed, message: error ?? "验证失败") }
                if let next = iterator.next() { enqueue(next) }
            }
            return results
        }
        try Task.checkCancellation()
        let previous = warehouses
        for entry in pending {
            guard let warehouse = loaded[entry.id] else { continue }
            if warehouses.contains(where: { $0.kind == warehouse.kind && DefaultSubscriptions.matches($0.configURL, warehouse.configURL) }) {
                outcomes[entry.id] = BatchImportOutcome(id: entry.id, name: entry.name, status: .skipped, message: "相同订阅已存在")
            } else {
                warehouses.append(warehouse)
                outcomes[entry.id] = BatchImportOutcome(id: entry.id, name: entry.name, status: .added, message: "格式验证通过，已添加；不代表全部媒体可播放")
            }
        }
        do { try save() }
        catch { warehouses = previous; lastPersistenceError = error.localizedDescription; throw error }
        return entries.compactMap { outcomes[$0.id] }
    }

    func refresh(id: UUID) async throws {
        guard let index = warehouses.firstIndex(where: { $0.id == id }) else { return }
        let old = warehouses[index]
        refreshingIDs.insert(id)
        defer { refreshingIDs.remove(id) }
        let refreshed = try await loader.load(from: old.configURL, kind: old.kind, replacing: old)
        guard let currentIndex = warehouses.firstIndex(where: { $0.id == id }),
              warehouses[currentIndex].configURL == old.configURL,
              warehouses[currentIndex].name == old.name,
              warehouses[currentIndex].updatedAt == old.updatedAt else { return }
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
