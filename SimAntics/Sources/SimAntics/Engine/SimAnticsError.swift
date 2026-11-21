import TSOContent

/// An error from running SimAntics code.
///
/// Any of these thrown inside a thread resets the entity (``VMThread``).
public enum SimAnticsError: Error, Equatable, Sendable {
    /// The routine asked for something it can't have.
    case simantics(String)
    /// An array index out of range, which .NET throws as `IndexOutOfRangeException`.
    case indexOutOfRange(String)
    /// A missing object or entry.
    case nullReference(String)
    /// A cast to the wrong entity type, such as treating an object as a Sim (`InvalidCastException`).
    case invalidCast(String)
    /// 32-bit division overflow (`int.MinValue / -1`), which .NET throws as `OverflowException`.
    case overflow(String)
    /// More than ``VMThread/maximumInstructionsPerTick`` instructions in one tick.
    case infiniteLoop
    /// Content the code needs couldn't be loaded.
    case content(ContentError)
    /// Behavior Simburbia doesn't support yet, never the routine's own failure.
    case unsupported(String)
}
