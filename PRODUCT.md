# Horse Trainer — Product Requirements

A macOS practice app for beating **live $1/$2 No-Limit Hold'em** by learning to
(a) **classify** opponents by type and (b) **exploit** each type correctly. The
strategy model is based on live-exploit creators (Hungry Horse Poker / Marc
Goone, Sao Costa, and similar): live pools under-bluff, size-tell, and over- or
under-fold in predictable ways. No real money. Play chips only.

## 1. Goals

1. **Realistic 1/2 tables.** Random 9-handed tables with the right mix of live
   player types. Each bot plays like its type, with per-player variation and
   quirks, so you can't memorize the bots.
2. **Classification reps.** Find out who's who from the same evidence you'd
   have live: limps, open sizes, showdowns, bet sizes, table talk/appearance.
3. **Exploit reps.** Make the right adjustment against each type, and get
   graded on it immediately.
4. **Principle-first feedback.** Every grade cites the principle behind it
   (e.g. "overfold to fish aggression", "size up value vs stations", "the
   inverse question").

Non-goals (v1): online multi-tabling, GTO solver output, tournaments, real
money, accounts or sync.

## 2. Player-type model (the core of everything)

Every mode (bots, coach, drills, reads quiz) uses the same archetype model, so
what you learn in drills is exactly how the table plays.

| Type | VPIP / PFR | Profile | Primary exploit |
|---|---|---|---|
| **Whale** | 60–75 / 20–35 | Loose-aggressive station. Straddles, big random opens ($20–40), barrels air when checked to ("given rope"), calls too much. | Value bet huge, bluff rarely, give rope (check to them) and bluff-catch. Overfold when they raise *your* bet ("fire with fire" = value). |
| **Fish** | 40–55 / 5–12 | Loose-passive station. Limps, limp-calls, calls down with any pair or draw. Bluffs too little. Strong sizing tells: small = medium, big = nuts. Raises = nuts. | "What does my hand want?" Put money in for them: big value sizes early, small bluff sizes only. **Overfold massively** to their aggression. |
| **Trying Rec** | 18–26 / 10–16 | Tight-passive "trying to play right". Opens $10–15, c-bets value, gives up air, folds to big bets, rarely bluffs. | Bigger value early, **size down value on the river**, bluff more often with **larger** sizes. Overfold to their aggression. |
| **Nit / OMC** | 10–15 / 5–9 | Plays only big cards and pairs. Sometimes limp-raises AA/KK. Never bluffs rivers. Raises = nutted. | Steal and bluff a lot. Tighten vs their opens/limp-raises. Fold to their big postflop aggression. |
| **Reg** | 22–28 / 17–23 | Winning TAG. Iso-raises fish limps, ranges c-bets small, bluffs in small and medium pots, plays straightforwardly when the pot gets big. | "Put yourself in their shoes." Play your value like they play bluffs (and vice versa). Overfold in big pots. Bluff big pots, which make them uncomfortable. |

Per-seat variation: every bot gets ±15% jitter on its parameters and a few
quirks: limp-traps premiums, big opens with premiums (a preflop sizing tell),
straddles, donk-leads value on the river, plays draws passively, and fast-plays
wet boards. Bots also get an "appearance" line that correlates with type but
doesn't decide it, as live tells do.

Table presets match live 1/2: *Typical weekend*, *Weekday grind* (reg- and
nit-heavy), *Juicy Saturday* (2 whales), and *Random*. Blinds are $1/$2 with an
optional $5 straddle. Buy-ins run $100–$300; whales and regs often sit deeper.
Busted players either rebuy or get replaced.

## 3. Modes

### 3.0 Home, Onboarding and the Daily Workout (the gym)
- **Onboarding** runs on first launch and can be reopened from the sidebar's Guide button. It covers the classify → exploit → review loop, the five types, how a session works (with keyboard shortcuts), the training tools, Claude key setup, and where to start.
- **Home** is the dashboard. It shows today's workout, your streak with an activity heatmap, your level and XP, the four-step loop, your weakest skills (each with a one-click drill), and your last live session.
- **Daily Workout** is 3 rounds × 5 reps of freshly generated spots:
  - Preflop: iso-raises, opens, limp-raises, cold 4-bets, and "is it in the top X%?"
  - Reads: Spot the type. A real table is simulated for ~80 hands, then you classify a player from their stats and showdowns. Also bluff-catching, sizing tells and flop raises.
  - Value: the inverse question, value sizing, thin value, barrels, bluffs and c-bets.
- Skills you miss get weighted to come up more often.
- Scoring: +10 XP per correct rep, with a combo multiplier (×2 at 3 in a row, ×3 at 6). Finishing a workout gives +50 XP and counts toward your daily streak. 20 reps or a 30+ hand session also counts as an active day. Levels run from Tourist up to Pro.

### 3.1 Cash Game, Training Table and Tracker
- **Cash Game** (tracked, label-free): the closest thing to real reps. Types are hidden with no reveal button, there is no spot filter, and the coach grades every decision but seals them until you end the session. Every hand is recorded in the Tracker. Hand reviews with Claude get only what you could see.
- **Training Table** (training wheels): Show types, instant coaching, the practice/spot filter, per-hand Claude reviews with types. Not tracked.
- **Tracker**: like HM/PT for the simulated pool. Cumulative winnings graph (total / showdown / non-showdown, hover crosshair), hands, net, bb/100 with a 95% interval, live-hour equivalent (30 hands/hr) and $/hr, "real or luck" variance read with hands needed to pin the win rate down, lifetime stats vs a winning 1/2 profile, results by position and by opponent type (revealed after the fact), and a session list with coach grades. Stored in `tracker.json`.

### 3.1b Table details
- 9-max table UI styled after a major online site: felt, seats, chip stacks,
  bets, dealer button, pot, and an action bar with Fold / Check-Call / Bet-Raise.
  The bet slider has presets (preflop: 3x, $10, $15, +$5/limper; postflop:
  ⅓, ½, ¾, pot, 1.5x, all-in) and keyboard shortcuts.
- Bots act with human-like delays. A speed setting controls the pace.
- **Hidden reads**: types are hidden by default. You can tag any seat with your
  read and write notes. A "Reveal HUD" toggle shows each seat's true type and
  observed stats (VPIP/PFR/3B/AF/WTSD), for learning.
- **Coach**: every hero decision is graded (✅ good / ⚠️ inaccuracy / ❌
  mistake) against the exploit model, with the principle and a short "why".
  Grades show after the hand, or instantly if you turn that on.
- **Ask Claude**: send the hand history, villain types, and coach grades to
  Claude for a deeper write-up. Follow-up questions are supported.
- Session stats: hands, net $, bb/100, decision grade breakdown.
- **End session → Session report** (every session): a one-line verdict that separates results from decision quality, your stats against a winning live 1/2 profile (VPIP, PFR, limp, 3-bet, c-bet, AF, WTSD), ranked findings each with a one-click drill, and a full Claude review.
- **Analyze session**: Claude reviews the whole session. It gets your stats vs.
  a winning 1/2 profile, the leaks grouped by principle, how you adjusted to
  each type, the biggest pots, and the next drills to run.
- Table size is adjustable from 2 to 9 players. The default is 9-max, like live 1/2; a 6-max / 9-handed toggle sits in the practice bar.
- **Practice filter (spot mode, Training Table only)**: pick a real spot (limpers in front, facing an open, blind defense, facing a 3-bet, c-bet or check, facing a c-bet, turn/river bets, your bet got raised, river value, multiway) and optionally a villain type. The table fast-forwards (a solid-reg autopilot plays your earlier streets) until you face that decision, then you play the hand out and the coach grades it. Spot hands are kept out of your session stat benchmarks; results feed skill history.
- **Pre-actions**: while others act you can pre-select Check/Fold, Check, or Call any (F / K / C). When you're out of the hand, Space skips to the next hand instantly. Auto-deal is a one-click toggle in the action bar.
- Hand history log, with showdowns visible (the "tabled" hands you'd see live).

### 3.2 Read the Table
- Same engine. You sit out (or play) while the table runs, either animated or
  fast-forwarded N hands at a time.
- Evidence feed: limps, open sizes, 3-bets, showdowns with the line taken
  ("called 3 streets with 2nd pair", "overbet river with the nuts").
- Quiz: classify every seat, then get a score and a reveal with the tells you
  should have used.

### 3.3 Exploit Spot Drills
- Generated multiple-choice spots in which **the right answer depends on the
  villain's type**: river bluff-catch vs a big bet, flop raise vs top pair,
  iso vs limpers, 3-bet vs opens, cold 4-bets, limp-raises, barrel or give up,
  thin value, and bluff opportunities.
- Real cards. Hands are generated to fit the spot's template.
- Feedback: right or wrong, the principle, and the explanation for each type.
  You can also ask Claude to go deeper.
- Filters by type and by concept. Accuracy is tracked per type and concept.

### 3.4 Sizing Lab / Inverse Question
- **Inverse question (value)**: "If they have TPTK here, what's the smallest
  bet that folds it?" Then: "so bet just under that." Fold points come from the
  same calling model the bots use, by type, holding and street. Each spot shows
  what the type calls with every other holding, plus a plan for getting stacks
  in (geometric sizing vs. the fold point).
- **Size it**: you pick a bet size for your hand against a given type, and the
  answer is graded against a target band, with the reason (e.g. "fish:
  value-bet 75–100%+ pot, they don't fold pairs").
- **Read their bet**: before acting, ask "if this player had *the nuts*
  here, how much would they bet? With a *draw*? With *air*?" Then: "so what
  does their actual bet mean?" Answers come from the same sizing model the bots
  use. The flip side applies to hero: "if *I* had the nuts here, what would I
  bet? A bluff?"

### 3.5 Range Builder
- A 13×13 matrix you paint by clicking and dragging, a "top X%" slider with
  5/10/15/20/25/30/40/50 shortcuts, compact notation in and out (`TT+, ATs+,
  KQo`), combo counts, and saved named ranges.
- "How the table plays": load the exact first-in raise and limp ranges the bots
  use for any type and position.
- Quizzes: paint the top X% (scored by combo overlap), "is this hand in the top
  X%?", and name the % for a shown range.
- The ranking blends all-in equity vs 1 and vs 3 random hands, because live pots
  are often multiway.

### 3.5b Equity Calculator
- Up to 9 players. Each holding can be exact cards (picked from a card grid), a
  range (standard notation like `QQ+, AKs, ATs+, 76s-54s, 22-55, 15%`, or a
  13×13 grid), or any two cards.
- Optional board (flop, turn or river). Exact enumeration when every holding is
  fixed and the runouts are few enough; Monte Carlo (120k samples) otherwise.
- Presets for live spots, e.g. JJ vs a nit's 3-bet range or AQ vs a limp-raise.

### 3.6 Playbook
A reference card for each type: tendencies, tells, exploits, and the flop
c-bet framework (½-pot range bet on non-A-high boards, overbet-or-check on
A-high boards, plus the exceptions).

### 3.7 Progress
Persistent stats: drill accuracy by type and concept, read-quiz accuracy, and
live session history.

## 4. Look and feel

Modern and neutral, in the style of Aside, Linear and Vercel. Not stock macOS.
- Neutral palette: `#0A0A0A` background, `#171717` cards, 10% white borders and white primary buttons. Color is used only for signals (good, warning, mistake) and player types.
- Fonts: **Geist** for the UI and **Geist Mono** for labels, numbers and keyboard hints. Both are bundled under the SIL OFL license.
- Custom controls instead of system ones: sidebar, tabs, dropdowns, sliders, toggles, in-window modals, and a right-side Claude drawer. There are no system sheets, no glass, no gradients and no emoji.
- Table: minimal black felt with a thin rail and white cards with big indices (four-color deck). Nameplates are blocky, and a white bar marks whose turn it is. Action buttons show their keyboard hints, with Raise as the primary.

## 5. Technical

- Swift 6 / SwiftUI, macOS 26+ (Liquid Glass), Swift Package Manager (`swift run`, or open in
  Xcode). `scripts/bundle.sh` builds a `.app`.
- `PokerCore` library (UI-free, unit-tested): cards, a 7-card evaluator, the
  NLHE engine (side pots, straddles, incomplete all-in raises, uncalled-bet
  return), hand strength and draws, archetypes and bot brains, coach rules,
  drill generators, and read tracking.
- `HorseTrainer` app target: SwiftUI views, game controller, persistence (JSON
  in Application Support), the Claude client (Messages API over URLSession,
  streaming), and the API key in a user-only (0600) file in Application Support (or `ANTHROPIC_API_KEY`). No Keychain, so rebuilds never re-prompt.
- Claude defaults: `claude-opus-5-5`, effort `medium`, server-side refusal
  fallback on. The model can be changed in Settings.

## 6. Acceptance

- The engine never loses or creates chips. A test runs thousands of random
  hands and checks chip conservation.
- Bots' observed VPIP/PFR over 2,000+ simulated hands fall inside each type's
  band. A test checks this.
- Each drill template produces valid, type-dependent answers. A test checks
  this.
- The equity calculator matches known results (AA vs KK ≈ 82%). Exact flop
  enumeration is tested.
- The app builds and launches with `swift run`.
