import Foundation

/// In-memory presentation cache. Only a completed, current request may be reused on a quick revisit.
/// Tickets fence overlapping reads; a cancelled request never marks a partial presentation complete.
struct PresentationLoadState<Key: Equatable> {
    struct Ticket {
        let key: Key
        fileprivate let generation: UInt64
    }

    private var generation: UInt64 = 0
    private var activeGeneration: UInt64?
    private var completedKey: Key?
    private var completedAt: Date?

    mutating func begin(key: Key, now: Date = Date(), maxAge: TimeInterval = 30,
                        force: Bool = false) -> Ticket? {
        generation &+= 1
        activeGeneration = nil
        if !force, completedKey == key, let completedAt {
            let age = now.timeIntervalSince(completedAt)
            if age >= 0, age < maxAge { return nil }
        }
        // Callers may publish progressive sections. Once another load starts, the old completed
        // marker no longer describes all visible sections, even if navigation returns to its key.
        completedKey = nil
        completedAt = nil
        activeGeneration = generation
        return Ticket(key: key, generation: generation)
    }

    func isCurrent(_ ticket: Ticket, key: Key, cancelled: Bool) -> Bool {
        !cancelled && activeGeneration == ticket.generation && ticket.key == key
    }

    @discardableResult
    mutating func complete(_ ticket: Ticket, key: Key, cancelled: Bool,
                           now: Date = Date()) -> Bool {
        guard isCurrent(ticket, key: key, cancelled: cancelled) else { return false }
        completedKey = ticket.key
        completedAt = now
        return true
    }

    mutating func finish(_ ticket: Ticket) {
        if activeGeneration == ticket.generation { activeGeneration = nil }
    }
}
