extension Resequencer where Value: ~Copyable {
    /// Why an arrival was refused. A refused arrival changes nothing.
    public enum Error: Swift.Error, Hashable, Sendable {
        /// The position is before `next`: it was handed on already, or it lies before the first position.
        case behind
        /// A value for the position is already waiting.
        case waiting
        /// The position is `window` or more positions past `next`.
        case beyond
    }
}
