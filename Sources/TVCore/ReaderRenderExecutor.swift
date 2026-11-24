import Foundation

final class ReaderRenderExecutor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "reader.typesetting", qos: .userInitiated)
    private let key = DispatchSpecificKey<UInt8>()

    init() { queue.setSpecific(key: key, value: 1) }

    func sync<Value>(_ operation: () throws -> Value) rethrows -> Value {
        if DispatchQueue.getSpecific(key: key) != nil { return try operation() }
        return try queue.sync(execute: operation)
    }

    func perform<Value: Sendable>(_ operation: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: operation()) }
        }
    }
}
