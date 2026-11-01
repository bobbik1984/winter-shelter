# PTxx — Playtest sheet

> Copy to `playtests/PT01.md` (M1 gate) or `PT02.md` (M2 gate). One block per tester. Do **not** help the tester during play.
> After the session run `python3 tools/playtest_report.py` and paste the output at the bottom.

| Field | Tester 1 | Tester 2 | Tester 3 |
| :--- | :--- | :--- | :--- |
| Date / build (git commit) | | | |
| Tester (initials, gamer? y/n) | | | |
| **Asked at 30 s: "Where is the wind coming from?"** — answer / correct? | | | |
| **Asked at ~2 min: "Roughly what time is it / how much light is left?"** | | | |
| First probe location (leeward? from log) | | | |
| Shelter chosen / entrance direction | | | |
| Session length (log) | | | |
| Outcome (log) | | | |
| **"Why did that happen?"** — can they name the main cause? | | | |
| **"Want to play again?"** (asked, not hinted) | | | |
| Where they got stuck / confused (observer notes) | | | |
| Three things they said, verbatim | | | |

## Gates (PRODUCTION_PLAN §4)

- **M1:** ≥ 2/3 name the wind direction within 30 s · first probe on a leeward slope · nobody complains about movement.
- **M2:** a full game in 10–20 min · ≥ 2/3 volunteer to play again · testers can explain why they got their result.

## If a gate fails

Only change `resources/tuning.tres` values and on-screen wording — **no new systems** (PRODUCTION_PLAN §6). Re-run `tools/ci.sh` after changes.

## playtest_report.py output

```
(paste here)
```
