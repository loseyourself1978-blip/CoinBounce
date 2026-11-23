# Coin Bounce — Game Design Constants

## Core Loops
- **Coin Drop**: Costs 1 coin. 30% slot machine trigger.
- **Fall Compensation**: 1:1 reward for every coin crossing the bottom edge.

## Hidden Mode Triggers
- **Pinball**: 0.8% chance on coin drop (increased to 4% by Slot 777).
- **Breakout**: 0.8% chance on coin drop (increased to 4% by Slot Joker).

## Reward Table
| Combo | Coins | Buff |
|-------|-------|------|
| 777   | 8     | Pinball Probability Boost |
| Joker | 18    | Breakout Probability Boost |
| Coins | 5     | Pusher Speed Up |
| Castle| 8     | Deflector Bonus Boost |
| Princess| 15  | Free Coin |
| Other | 1     | None |

## Physics & Timing
- **Swing Arms**: 30-60 RPM.
- **Pusher Bar**: 15-30 second random interval.
- **Pinball**: 1 score = 1 coin.
- **Breakout**: Time-based tiers (45/25/20 coins).

## Pachinko (v12.6, `PachinkoConstants.swift`; design: `docs/pachinko/PACHINKO_DESIGN.md` §5.7)
| Constant | Value |
|---|---|
| Ball price | 1 coin per ball, charged when it leaves; short shots that roll back are free |
| Tray | up to 50 balls (never more than the balance); chips +1 / +2 / +5 / +10 |
| Fire interval / max in flight | 0.6 s / 24 |
| Power | default 0.25, recommended zone 0.18–0.32 |
| Spring launcher (v12.6) | pull 0–1 maps to power piecewise: 0–0.5 → 0–0.18, 0.5–0.8 → 0.18–0.32 (gold zone), 0.8–1 → 0.32–1; a pull under 0.06 cancels; default pull 0.65 |
| Payouts | start pocket 1, tulip 2, side pocket 1, lucky cup 2, attacker 4 per ball (5 balls per round) |
| Lucky cup (v12.6) | slides ±0.17 board widths around the drain every 4 s, half-width 0.014; catches about 5.7% of balls |
| Lucky lamps (v12.6) | 7 lamps; a tulip or lucky-cup ball lights one; all 7 → 6 free golden balls, one every 0.16 s |
| Jackpot odds | normal and time-short 3095/65536 (1 in 21.2), ST 8192/65536 (1 in 8) |
| Jackpot kinds | SUPER 8% (10 rounds → ST), ROYAL 32% (5 rounds → ST), BONUS 60% (2 rounds → time-short) |
| ST / time-short | 12 spins each |
| Holds | 8; a start-pocket ball with full holds pays 1 and draws nothing |
| Spin times | 3 / 1.5 / 0.8 s (holds < 2 / ≥ 2 / ≥ 4); support 1 s, hit 4 s; reach 7 s; super reach 11 s (3 s with Reduce Motion) |
| Return | target 0.960, test band 0.95–0.97; measured coupled 10 × 1M balls: 0.9568 (v12.6 rules) |
| Physics | board 1 × 1.25 units, ball r 0.0165, nail r 0.006, gravity 7, step 1/240 s |

## Pinball (v12.7, `PinballRules.swift` / `PinballEngine.swift`)
| Constant | Value |
|---|---|
| Ball price | 1 coin per ball; a weak launch that rolls back is shot again for free |
| Coins | 9,500 points per coin, leftover points carry to the next ball, at most 15 coins per ball |
| Points | bumper 100 (×3 during super bumpers), slingshot 30, top lane 250 (repeat 50), all three lanes 1,000 and multiplier +1 (max ×5), drop target 400, all three 2,500, standup 300 (repeat 100), all three 2,000, Lucky Hole 500, inlane 150, outlane 300, mystery 3,000, jackpot 15,000, end bonus 200 per lit item |
| Mission | drops → 12 bumper hits → three stars → Lucky Hole (jackpot + 2 extra balls); saved across balls |
| Ball save | one free return if the ball drains within 7 s of entering the field |
| Physics | table 1 × 1.9, ball r 0.022, gravity 1.9, step 1/480 s, flipper up 30 rad/s, bumper kick 1.55, sling kick 1.25 |
| Return (auto-play bots, 9,000 balls each) | no flipping 0.51, average 0.94, expert 2.40 |

## Slots (v12.8, `SlotsMath.swift`)
| Constant | Value |
|---|---|
| Layout | 5 reels × 3 rows, 10 fixed lines, left to right; bets 1 / 2 / 5 / 10 |
| Line pays (× total bet, 3 / 4 / 5) | cherry, lemon 1 / 3 / 8; grapes, strawberry 1 / 4 / 12; diamond 2 / 6 / 20; crown 3 / 10 / 40; seven 5 / 25 / 100 |
| Wild | reels 2, 3, 4; substitutes for line symbols |
| Free spins | 3 / 4 / 5 scatters pay ×2 / ×5 / ×20 and award 8 / 12 / 20 spins; line wins ×2; no retrigger, no chest |
| Chest bonus | chests on reels 1, 3, 5; one of ×4, ×6, ×10, ×15, ×25 at equal odds |
| Strip lengths | 35, 34, 37, 34, 35 (counts in `stripCounts`) |
| Return | exact 0.9440 (lines 0.6163, scatter 0.0434, free spins 0.1984, chest 0.0858); hit rate 25.6% |

