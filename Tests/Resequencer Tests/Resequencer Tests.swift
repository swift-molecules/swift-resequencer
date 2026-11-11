import Resequencer
import Testing

enum `Resequencer Tests` {}

extension `Resequencer Tests` {
    @Suite
    struct `Values leave in position order` {}

    @Suite
    struct `Arrivals that break a law are refused` {}

    @Suite
    struct `Every value ends exactly once` {}
}

/// Counts the tokens that have ended.
private final class Ledger {
    var ended: [UInt] = []
}

/// A move-only value that reports its end.
private struct Token: ~Copyable {
    let position: UInt
    let ledger: Ledger

    deinit { ledger.ended.append(position) }
}

/// What a resequencer of `Int`s looks like from outside.
private struct Snapshot: Equatable {
    var next: Ordinal?
    var count: Cardinal
    var isEmpty: Bool

    init(_ resequencer: borrowing Resequencer<Int>) {
        next = resequencer.next
        count = resequencer.count
        isEmpty = resequencer.isEmpty
    }
}

private func error(
    _ resequencer: inout Resequencer<Int>,
    arriving value: Int,
    at position: UInt
) -> Resequencer<Int>.Error? {
    do throws(Resequencer<Int>.Error) {
        try resequencer.arrive(value, at: Ordinal(position))
        return nil
    } catch {
        return error
    }
}

private func drain(_ resequencer: inout Resequencer<Int>) -> [Int] {
    var released: [Int] = []
    while let value = resequencer.release() { released.append(value) }
    return released
}

extension `Resequencer Tests`.`Values leave in position order` {
    static let orders: [[UInt]] = [
        [0, 1, 2, 3, 4, 5],
        [5, 4, 3, 2, 1, 0],
        [3, 0, 5, 1, 4, 2],
        [1, 0, 3, 2, 5, 4],
        [2, 5, 0, 4, 1, 3],
    ]

    @Test
    func `whatever the arrival order, values leave at consecutive positions from the first`() throws {
        for first in [UInt(0), 7, 1000] {
            for order in Self.orders {
                var resequencer = Resequencer<Int>(from: Ordinal(first), window: 6)
                var released: [Int] = []
                for offset in order {
                    try resequencer.arrive(Int(offset) * 10, at: Ordinal(first + offset))
                    released += drain(&resequencer)
                }
                #expect(released == [0, 10, 20, 30, 40, 50])
                #expect(Snapshot(resequencer) == Snapshot(Resequencer<Int>(from: Ordinal(first + 6), window: 6)))
            }
        }
    }

    @Test
    func `each value leaves as soon as every earlier position has left and no sooner`() throws {
        var resequencer = Resequencer<Int>(window: 8)
        var batches: [[Int]] = []
        for position in [UInt(2), 1, 4, 0, 3, 6, 5] {
            try resequencer.arrive(Int(position), at: Ordinal(position))
            batches.append(drain(&resequencer))
        }
        #expect(batches == [[], [], [], [0, 1, 2], [3, 4], [], [5, 6]])
    }

    @Test
    func `a missing position holds back every later one and release changes nothing`() throws {
        var resequencer = Resequencer<Int>(window: 4)
        try resequencer.arrive(1, at: 1)
        try resequencer.arrive(3, at: 3)
        let before = Snapshot(resequencer)
        #expect(resequencer.release() == nil)
        #expect(resequencer.release() == nil)
        #expect(Snapshot(resequencer) == before)
        #expect(before.next == .zero)
        try resequencer.arrive(0, at: 0)
        #expect(drain(&resequencer) == [0, 1])
        #expect(resequencer.next == 2)
        try resequencer.arrive(2, at: 2)
        #expect(drain(&resequencer) == [2, 3])
    }

    @Test
    func `arrival only stores and release hands on one value at a time`() throws {
        var resequencer = Resequencer<Int>(window: 4)
        try resequencer.arrive(1, at: 1)
        try resequencer.arrive(0, at: 0)
        #expect(resequencer.next == .zero)
        #expect(resequencer.count == 2)
        #expect(resequencer.release() == 0)
        #expect(resequencer.next == 1)
        #expect(resequencer.count == .one)
        #expect(resequencer.release() == 1)
        #expect(resequencer.next == 2)
        #expect(resequencer.count == .zero)
    }

    @Test
    func `the first position is zero unless construction says otherwise`() throws {
        var zero = Resequencer<Int>(window: 2)
        #expect(zero.next == .zero)
        try zero.arrive(1, at: 1)
        #expect(zero.release() == nil)

        var five = Resequencer<Int>(from: 5, window: 2)
        #expect(five.next == 5)
        try five.arrive(50, at: 5)
        #expect(five.release() == 50)
        #expect(five.next == 6)
    }

    @Test
    func `count is the number of values waiting and isEmpty says whether it is zero`() throws {
        var resequencer = Resequencer<Int>(window: 8)
        #expect(Snapshot(resequencer) == Snapshot(Resequencer<Int>(window: 8)))
        #expect(resequencer.isEmpty == true)
        #expect(resequencer.count == .zero)
        #expect(resequencer.window == 8)
        try resequencer.arrive(3, at: 3)
        #expect(resequencer.isEmpty == false)
        #expect(resequencer.count == .one)
        try resequencer.arrive(0, at: 0)
        try resequencer.arrive(1, at: 1)
        #expect(resequencer.count == 3)
        #expect(drain(&resequencer) == [0, 1])
        #expect(resequencer.count == .one)
        #expect(resequencer.isEmpty == false)
        try resequencer.arrive(2, at: 2)
        #expect(drain(&resequencer) == [2, 3])
        #expect(resequencer.count == .zero)
        #expect(resequencer.isEmpty == true)
    }
}

extension `Resequencer Tests`.`Arrivals that break a law are refused` {
    @Test
    func `a position handed on already is behind`() throws {
        var resequencer = Resequencer<Int>(window: 4)
        try resequencer.arrive(0, at: 0)
        try resequencer.arrive(1, at: 1)
        try resequencer.arrive(3, at: 3)
        #expect(drain(&resequencer) == [0, 1])
        let before = Snapshot(resequencer)
        #expect(error(&resequencer, arriving: -1, at: 0) == .behind)
        #expect(error(&resequencer, arriving: -1, at: 1) == .behind)
        #expect(Snapshot(resequencer) == before)
        try resequencer.arrive(2, at: 2)
        #expect(drain(&resequencer) == [2, 3])
    }

    @Test
    func `a position before the first is behind`() throws {
        var resequencer = Resequencer<Int>(from: 5, window: 4)
        let before = Snapshot(resequencer)
        #expect(error(&resequencer, arriving: -1, at: 4) == .behind)
        #expect(error(&resequencer, arriving: -1, at: 0) == .behind)
        #expect(Snapshot(resequencer) == before)
        #expect(resequencer.release() == nil)
    }

    @Test
    func `a position that is waiting is refused and the first value stays`() throws {
        var resequencer = Resequencer<Int>(window: 4)
        try resequencer.arrive(10, at: 1)
        try resequencer.arrive(30, at: 3)
        let before = Snapshot(resequencer)
        #expect(error(&resequencer, arriving: -1, at: 1) == .waiting)
        #expect(error(&resequencer, arriving: -3, at: 3) == .waiting)
        #expect(Snapshot(resequencer) == before)
        try resequencer.arrive(0, at: 0)
        #expect(error(&resequencer, arriving: -9, at: 0) == .waiting)
        try resequencer.arrive(20, at: 2)
        #expect(drain(&resequencer) == [0, 10, 20, 30])
    }

    @Test
    func `a position a window or more past next is beyond until next moves on`() throws {
        var resequencer = Resequencer<Int>(from: 10, window: 3)
        let before = Snapshot(resequencer)
        #expect(error(&resequencer, arriving: -1, at: 13) == .beyond)
        #expect(error(&resequencer, arriving: -1, at: 14) == .beyond)
        #expect(error(&resequencer, arriving: -1, at: .max) == .beyond)
        #expect(Snapshot(resequencer) == before)
        try resequencer.arrive(12, at: 12)
        try resequencer.arrive(10, at: 10)
        #expect(error(&resequencer, arriving: -1, at: 13) == .beyond)
        #expect(resequencer.release() == 10)
        try resequencer.arrive(13, at: 13)
        #expect(error(&resequencer, arriving: -1, at: 14) == .beyond)
        try resequencer.arrive(11, at: 11)
        #expect(drain(&resequencer) == [11, 12, 13])
    }

    @Test
    func `a window of zero refuses every position`() {
        var resequencer = Resequencer<Int>(window: .zero)
        #expect(error(&resequencer, arriving: 0, at: 0) == .beyond)
        #expect(error(&resequencer, arriving: 1, at: 1) == .beyond)
        #expect(resequencer.release() == nil)
        #expect(resequencer.isEmpty == true)
    }

    @Test
    func `after the last position there is, next is nil and every arrival is behind`() throws {
        var resequencer = Resequencer<Int>(from: Ordinal(UInt.max - 1), window: 4)
        try resequencer.arrive(2, at: Ordinal(UInt.max))
        try resequencer.arrive(1, at: Ordinal(UInt.max - 1))
        #expect(resequencer.release() == 1)
        #expect(resequencer.next == Ordinal(UInt.max))
        #expect(resequencer.release() == 2)
        #expect(resequencer.next == nil)
        #expect(resequencer.release() == nil)
        #expect(error(&resequencer, arriving: -1, at: .max) == .behind)
        #expect(error(&resequencer, arriving: -1, at: 0) == .behind)
        #expect(resequencer.isEmpty == true)
    }
}

extension `Resequencer Tests`.`Every value ends exactly once` {
    @Test
    func `released values end with their owner and waiting values with the resequencer`() throws {
        let ledger = Ledger()
        do {
            var resequencer = Resequencer<Token>(window: 8)
            for position in [UInt(4), 1, 0, 6, 2] {
                try resequencer.arrive(Token(position: position, ledger: ledger), at: Ordinal(position))
            }
            #expect(ledger.ended.isEmpty)
            #expect(resequencer.count == 5)
            var released: [UInt] = []
            while let token = resequencer.release() {
                released.append(token.position)
                #expect(ledger.ended == Array(released.dropLast()))
            }
            #expect(released == [0, 1, 2])
            #expect(ledger.ended == [0, 1, 2])
            #expect(resequencer.count == 2)
        }
        #expect(ledger.ended.sorted() == [0, 1, 2, 4, 6])
    }

    @Test
    func `a refused value ends at the refusal and the waiting one is untouched`() throws {
        let ledger = Ledger()
        var resequencer = Resequencer<Token>(from: 1, window: 2)
        try resequencer.arrive(Token(position: 2, ledger: ledger), at: 2)
        #expect(throws: Resequencer<Token>.Error.waiting) {
            try resequencer.arrive(Token(position: 200, ledger: ledger), at: 2)
        }
        #expect(ledger.ended == [200])
        #expect(throws: Resequencer<Token>.Error.behind) {
            try resequencer.arrive(Token(position: 100, ledger: ledger), at: 0)
        }
        #expect(throws: Resequencer<Token>.Error.beyond) {
            try resequencer.arrive(Token(position: 300, ledger: ledger), at: 3)
        }
        #expect(ledger.ended == [200, 100, 300])
        #expect(resequencer.count == .one)
        try resequencer.arrive(Token(position: 1, ledger: ledger), at: 1)
        var released: [UInt] = []
        while let token = resequencer.release() { released.append(token.position) }
        #expect(released == [1, 2])
        #expect(ledger.ended == [200, 100, 300, 1, 2])
    }
}
