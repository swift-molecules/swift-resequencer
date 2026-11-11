public import Cardinal
import Index
public import Ordinal
import Queue

/// A reorder buffer: values arrive tagged with a position, in any order, and leave in position order.
///
/// `arrive(_:at:)` stores a value; `release()` hands on the value at `next`, once it has arrived.
/// Only the `window` positions from `next` onward can wait, so memory is bounded at construction.
public struct Resequencer<Value: ~Copyable>: ~Copyable {
    /// The number of positions, counted from `next`, that can wait at once.
    public let window: Cardinal

    /// The position `release()` hands on next; `nil` once the last position there is has been handed on.
    public private(set) var next: Ordinal?

    /// The number of values waiting.
    public private(set) var count: Cardinal

    /// One slot per position from `next` up to the furthest position waiting; the last slot is filled.
    private var slots: Queue<Value?>

    /// A resequencer that hands on `first`, then the position after it, and so on.
    public init(from first: Ordinal = .zero, window: Cardinal) {
        self.window = window
        self.next = first
        self.count = .zero
        self.slots = Queue()
    }
}

extension Resequencer: Sendable where Value: Sendable & ~Copyable {}

extension Resequencer where Value: ~Copyable {
    /// Whether no value is waiting.
    public var isEmpty: Bool { count == .zero }

    /// Stores `value` to be handed on at `position`.
    ///
    /// Fails with `.behind` for a position before `next`, `.waiting` for a position that already has a
    /// value waiting, and `.beyond` for a position `window` or more past `next`. A refused arrival
    /// changes nothing, and the refused value ends there.
    public mutating func arrive(_ value: consuming Value, at position: Ordinal) throws(Error) {
        guard let next else { throw .behind }
        let offset: Cardinal
        do throws(Ordinal.Error) {
            offset = try next.distance.forward(to: position)
        } catch {
            throw .behind
        }
        guard offset < window else { throw .beyond }
        let slot = Queue<Value?>.Index(Ordinal(offset))
        while slots.count <= slot { slots.enqueue(nil) }
        guard slots[slot] == nil else { throw .waiting }
        slots[slot] = consume value
        count += .one
    }

    /// Hands on the value at `next` and moves `next` one position on, or returns `nil`, changing
    /// nothing, while that value has not arrived.
    public mutating func release() -> Value? {
        guard let position = next, slots.peek({ $0 != nil }) == true, let value = slots.dequeue() else {
            return nil
        }
        next = try? position.successor.exact()
        count = count.subtract.saturating(.one)
        return value
    }
}
