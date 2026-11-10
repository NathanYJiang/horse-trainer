import Testing
@testable import PokerCore

@Suite struct HandReplayTests {
    @Test func replayEndsWhereTheHandEnded() {
        var session = TableSession(preset: .typical, seats: 9, includeHero: false)
        for _ in 0..<40 {
            let h = session.simulateHand()
            let frames = HandReplay.frames(h)
            let last = frames.last!
            #expect(frames.count == h.actions.filter(\.type.isVoluntary).count + 1)
            #expect(last.board == h.board)
            #expect(last.result?.net == h.result?.net)
            #expect(last.players.map(\.stack) == h.players.map(\.stack))
        }
    }
}
