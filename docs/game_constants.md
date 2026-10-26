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
