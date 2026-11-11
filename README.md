# swift-resequencer

Use this package when values are produced out of order but must be consumed in order: frames rendered in parallel and handed to an encoder one by one, replies to numbered requests, chunks of a download. Start from `Resequencer<Value>`: each value arrives tagged with an `Ordinal` position, and the resequencer hands values on in position order, each as soon as every earlier position has been handed on. Call `arrive(_:at:)` as values come in and `release()` until it returns `nil`. Values may be `~Copyable`. The resequencer waits for every position, so use it only when each one will arrive. When values should leave smallest first without waiting for the ones in between, use swift-heap. When they should leave in arrival order, use swift-queue.

## Laws

- Order: `release()` hands on the value at `next` and moves `next` to the position after it. The first `next` is the `from` position given at construction, zero by default. So values leave at consecutive positions counted up from the first, whatever order they arrived in, and each value leaves exactly once.
- Nothing is skipped: while the value at `next` has not arrived, `release()` returns `nil` and changes nothing, however many later positions are waiting. Once it arrives, repeated `release()` hands on that value and every waiting value that follows it without a gap.
- Arrival never releases: `arrive(_:at:)` only stores. The caller decides when to call `release()`.
- A position before `next` is refused with `.behind`. That covers a position that was handed on already and a position before the first.
- A position that already has a value waiting is refused with `.waiting`. The value that arrived first stays.
- Only the `window` positions from `next` onward can wait. A position `window` or more past `next` is refused with `.beyond`; after a release moves `next` on, the same position is accepted. A window of zero refuses every position.
- A refused arrival changes nothing: `next`, `count` and the waiting values are as before. The refused value ends there, because an error cannot carry a `~Copyable` value back.
- `count` is the number of values waiting, and `isEmpty` says whether it is zero.
- Positions do not wrap. After the last position an `Ordinal` can hold has been handed on, `next` is `nil` and every arrival is refused with `.behind`.
- Every value ends exactly once: a released value when its new owner ends it, a refused value at the refusal, and the values still waiting when the resequencer ends.
- Cost: `release()`, `next`, `count`, `isEmpty` and `window` take O(1). `arrive(_:at:)` writes one slot and adds an empty slot for each position between the furthest one seen and the new one, so one arrival takes at most O(`window`), and arrivals take O(1) each on average when every position arrives. The slots in use span `next` to the furthest position waiting, never more than `window`.
