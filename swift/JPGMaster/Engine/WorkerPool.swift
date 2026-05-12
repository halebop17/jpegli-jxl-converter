import Foundation

/// Bounded parallel runner. Schedules N concurrent conversions using
/// Swift's `TaskGroup`, supports cancellation, and emits progress events
/// via a sendable closure. Mirrors the Python pipeline's
/// `ThreadPoolExecutor` model.
@MainActor
final class WorkerPool: ObservableObject {

    enum Status: Equatable {
        case waiting
        case processing
        case converted
        case failed(String)
        case cancelled
    }

    struct Item: Identifiable, Equatable {
        let id: UUID = UUID()
        let source: URL
        let destination: URL
        var status: Status = .waiting
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var completed: Int = 0
    @Published private(set) var failed: Int = 0
    @Published private(set) var cancelledCount: Int = 0
    @Published private(set) var isRunning: Bool = false
    @Published var errors: [String] = []

    private var cancelFlag = false

    func setItems(_ items: [Item]) {
        self.items = items
        self.completed = 0
        self.failed = 0
        self.cancelledCount = 0
        self.errors = []
    }

    func cancel() {
        cancelFlag = true
    }

    func run(workerCount: Int,
              settings: ConversionSettings,
              encoders: EncoderResolver) async {
        guard !isRunning else { return }
        isRunning = true
        cancelFlag = false
        defer { isRunning = false }

        let queue = items.indices.map { $0 }

        await withTaskGroup(of: Void.self) { group in
            var iterator = queue.makeIterator()
            // Prime the group with N tasks.
            for _ in 0..<max(1, workerCount) {
                guard let next = iterator.next() else { break }
                addTask(group: &group, index: next, settings: settings, encoders: encoders)
            }
            // As each finishes, schedule the next.
            for await _ in group {
                guard let next = iterator.next() else { continue }
                addTask(group: &group, index: next, settings: settings, encoders: encoders)
            }
        }
    }

    private func addTask(group: inout TaskGroup<Void>,
                          index: Int,
                          settings: ConversionSettings,
                          encoders: EncoderResolver) {
        let source      = items[index].source
        let destination = items[index].destination
        let id          = items[index].id

        group.addTask { [weak self] in
            // Cancellation check — runs before the work begins.
            let cancelled = await MainActor.run { [weak self] in self?.cancelFlag ?? true }
            if cancelled {
                await self?.markStatus(id: id, status: .cancelled)
                await self?.bumpCancelled()
                return
            }
            await self?.markStatus(id: id, status: .processing)

            do {
                try await Task.detached(priority: .userInitiated) {
                    try ConversionJob.run(source: source,
                                          destination: destination,
                                          settings: settings,
                                          encoders: encoders)
                }.value
                await self?.markStatus(id: id, status: .converted)
                await self?.bumpCompleted()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await self?.markStatus(id: id, status: .failed(message))
                await self?.bumpFailed(source: source, message: message)
            }
        }
    }

    private func markStatus(id: UUID, status: Status) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].status = status
        }
    }

    private func bumpCompleted()  { completed      += 1 }
    private func bumpCancelled()  { cancelledCount += 1 }
    private func bumpFailed(source: URL, message: String) {
        failed += 1
        errors.append("\(source.lastPathComponent): \(message)")
    }
}
