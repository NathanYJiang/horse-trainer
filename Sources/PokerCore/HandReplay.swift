import Foundation

/// Rebuilds every state a finished hand passed through, for step-by-step replays.
public enum HandReplay {
    /// Frame 0 has the blinds posted; each later frame is the state right after one voluntary action.
    public static func frames(_ hand: HandState) -> [HandState] {
        let seats = hand.players.map { (seat: $0.seat, name: $0.name, stack: $0.startingStack) }
        let holes = Dictionary(uniqueKeysWithValues: hand.players.map { ($0.seat, $0.hole) })
        var rng = SplitMix64(seed: UInt64(hand.handNumber))
        var h = HandState(config: hand.config, handNumber: hand.handNumber, seats: seats, buttonSeat: hand.buttonSeat,
                          straddle: hand.straddleSeat != nil, rng: &rng, presetHoles: holes, presetBoard: hand.board)
        var out = [h]
        for a in hand.actions where a.type.isVoluntary {
            guard !h.isComplete, h.currentSeat == a.seat else { break }
            h.apply(SimGrader.decision(for: a))
            out.append(h)
        }
        return out
    }
}
