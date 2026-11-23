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

## Pachinko (v12.5, `PachinkoConstants.swift`; design: `docs/pachinko/PACHINKO_DESIGN.md` §5.7)
| Constant | Value |
|---|---|
| Ball price | 1 coin per ball, charged when it leaves; short shots that roll back are free |
| Tray | up to 50 balls (never more than the balance); chips +1 / +2 / +5 / +10 |
| Fire interval / max in flight | 0.6 s / 24 |
| Power | default 0.25, recommended zone 0.18–0.32 |
| Payouts | start pocket 1, tulip 3, side pocket 2, attacker 4 per ball (5 balls per round) |
| Jackpot odds | normal and time-short 2950/65536 (1 in 22.2), ST 8192/65536 (1 in 8) |
| Jackpot kinds | SUPER 8% (10 rounds → ST), ROYAL 32% (5 rounds → ST), BONUS 60% (2 rounds → time-short) |
| ST / time-short | 12 spins each |
| Holds | 8; a start-pocket ball with full holds pays 1 and draws nothing |
| Spin times | 3 / 1.5 / 0.8 s (holds < 2 / ≥ 2 / ≥ 4); support 1 s, hit 4 s; reach 7 s; super reach 11 s (3 s with Reduce Motion) |
| Return | target 0.960, test band 0.95–0.97; measured coupled 10 × 1M balls: 0.9630 |
| Physics | board 1 × 1.25 units, ball r 0.0165, nail r 0.006, gravity 7, step 1/240 s |
