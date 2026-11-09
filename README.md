# Horse Trainer 🐴

A macOS practice app for live $1/$2 No-Limit Hold'em. You learn to **classify** the
table (whales, fish, trying recs, nits, regs) and to **exploit** each type, following
the live-exploit school of Hungry Horse, Sao Costa and similar coaches. Play chips only.

The full spec is in [PRODUCT.md](PRODUCT.md).

## Run

Requires macOS 26 and Xcode 26+ (Swift 6.2+).

```bash
swift run -c release HorseTrainer      # quickest
scripts/bundle.sh && open build/HorseTrainer.app   # proper .app bundle
swift test                              # engine, bots, coach, drills, equity tests
```

You can also open `Package.swift` in Xcode and run the `HorseTrainer` scheme.

## What's inside

| Screen | What it trains |
|---|---|
| **Home** | Dashboard: today's workout, streak heatmap, level/XP, weakest skills, last session. |
| **Daily Workout** | The gym: 3 rounds × 5 fresh reps (preflop, spot-the-type reads, value). Combos, XP, streaks. Adapts to what you miss. |
| **Cash Game** | Real conditions: 9-handed or 6-max 1/2 vs the modeled pool, no labels, grades sealed until the session ends. Tracked. |
| **Tracker** | Long-run results for Cash Game: winnings graph, bb/100 with a confidence range, stats vs a winning profile, by position and by opponent type. |
| **Training Table** | Same table with training wheels: show types, instant coaching, spot practice. Not tracked. |
| **Read the Table** | Sit out, watch or fast-forward hands, tag every seat, then get scored on your reads. |
| **Exploit Drills** | Type-dependent spots (bluff-catching, flop raises, iso-raises, limp-raises, cold 4-bets, value sizing…). |
| **Sizing Lab** | Inverse question for value ("what bet folds their TPTK? bet just under it"), reading their bet sizes, and a size-it drill. |
| **Range Builder** | Paint ranges, top-X% slider, the bots' real opening ranges by type and position, and "name the %" quizzes. |
| **Equity Calculator** | Cards / ranges / any-two vs each other, with a 13×13 range grid. |
| **Playbook** | Type cards and the principles that every grade cites. |

Keyboard at the table: `F` fold · `C` check/call · `R` bet/raise · `Space` deal.

First launch shows a short onboarding. Reopen it anytime from **Guide** in the sidebar.

## Claude coach (optional)

"Ask Claude" sends the hand history (with villain types), the coach's grades and the
playbook to the Claude API for a deeper review. Add an Anthropic API key in
**Settings** (saved to a user-only file in Application Support, no Keychain prompts), or launch with `ANTHROPIC_API_KEY` set.
It defaults to `claude-opus-5-5` at medium effort, with the server-side refusal
fallback turned on.

## Layout

- `Sources/PokerCore`: UI-free engine. Evaluator, NLHE state machine (side pots,
  straddles, incomplete raises), hand reading, bot archetypes and brains, coach
  rules, drills, the sizing lab, the equity calculator and read tracking.
- `Sources/HorseTrainer`: the SwiftUI app.

Dev flags: `HT_AUTOPLAY=1` lets a reg-profile bot play your seat. `HT_SCREEN=drills`
picks the starting screen. `--snapshot <dir>` renders screens to PNGs offscreen.
