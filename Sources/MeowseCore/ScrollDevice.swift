/// The kind of device behind a scroll event, as far as its fields tell.
public enum ScrollDevice: UInt8, Sendable {
    /// Discrete ticks from a mouse wheel: what Meowse smooths.
    case wheel
    /// Continuous, phased scrolling from a trackpad or Magic Mouse, which
    /// Meowse leaves alone.
    case touch

    /// Source data on every frame Meowse posts. The frames are copies of the
    /// wheel's event, so without it they'd look like hardware.
    public static let frameTag: Int64 = 0x4D65_6F77  // "Meow"

    /// Classifies one scroll event. Every discrete tick is a wheel's, even one
    /// relayed by a mouse utility. Continuous scrolling counts only when it
    /// comes straight from hardware with a gesture phase, as trackpads send it;
    /// software posts it too (Meowse's own frames, remote sessions).
    @inline(__always)
    public static func of(continuous: Bool, sourcePID: Int64, userData: Int64,
                          scrollPhase: Int64, momentumPhase: Int64) -> ScrollDevice? {
        if !continuous { return .wheel }
        guard sourcePID == 0, userData != frameTag else { return nil }
        return scrollPhase != 0 || momentumPhase != 0 ? .touch : nil
    }
}
