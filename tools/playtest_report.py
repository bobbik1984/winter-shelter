#!/usr/bin/env python3
"""Summarise playtest session logs (user://sessions/*.jsonl) against the M1 / M2 gates.

Usage:  python3 tools/playtest_report.py [sessions_dir]
Default dir (Linux): ~/.local/share/godot/app_userdata/Snow Shelter Challenge/sessions
Windows: %APPDATA%/Godot/app_userdata/Snow Shelter Challenge/sessions
"""
import json, sys, os, glob, statistics

d = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/.local/share/godot/app_userdata/Snow Shelter Challenge/sessions")
files = sorted(glob.glob(os.path.join(d, "*.jsonl")))
if not files:
    sys.exit(f"no session logs in {d}")

rows = []
for f in files:
    ev = [json.loads(l) for l in open(f, encoding="utf-8") if l.strip()]
    start = next((e for e in ev if e["ev"] == "start"), {})
    probes = [e for e in ev if e["ev"] == "probe"]
    site = next((e for e in ev if e["ev"] == "site"), None)
    rep = next((e for e in ev if e["ev"] == "report"), None)
    first = probes[0] if probes else None
    rows.append({
        "file": os.path.basename(f),
        "valley": start.get("valley"), "weather": start.get("weather"),
        "first_probe_s": first["t"] if first else None,
        "first_probe_leeward": (first["lee"] > 0.3) if first else None,
        "probes": len(probes),
        "best_depth": max((p["depth"] for p in probes), default=None),
        "site": site["preset"] if site else None,
        "site_clock": site["clock"] if site else None,
        "entrance_leeward": (site["wind_angle"] >= 120) if site else None,
        "outcome": rep["outcome"] if rep else "(quit)",
        "weakest": rep.get("min_axis") if rep else None,
        "forced_night": rep.get("forced") if rep else None,
        "minutes": round(ev[-1]["t"] / 60.0, 1),
        "fire_fails": sum(1 for e in ev if e["ev"] == "fire_fail"),
        "wet_logs": sum(1 for e in ev if e["ev"] == "gather" and e.get("kind") == "wet_log"),
    })

print(f"{len(rows)} session(s) in {d}\n")
for r in rows:
    print(f"- {r['file']}: {r['outcome']:<9} {r['minutes']:>5} min  site={r['site']} @ {r['site_clock']}  "
          f"probes={r['probes']} first@{r['first_probe_s']}s leeward={r['first_probe_leeward']}  "
          f"entrance_leeward={r['entrance_leeward']}  weakest={r['weakest']}  fire_fails={r['fire_fails']} wet_logs={r['wet_logs']}")

def frac(key):
    v = [r[key] for r in rows if r[key] is not None]
    return f"{sum(v)}/{len(v)}" if v else "n/a"

done = [r for r in rows if r["outcome"] != "(quit)"]
print("\nGate metrics")
print(f"  M1 first probe on a leeward slope:      {frac('first_probe_leeward')}")
fp = [r['first_probe_s'] for r in rows if r['first_probe_s'] is not None]
print(f"  M1 median time to first probe:          {statistics.median(fp):.0f} s" if fp else "  M1 time to first probe: n/a")
print(f"  M2 sessions finished (reached report):  {len(done)}/{len(rows)}")
mins = [r['minutes'] for r in done]
print(f"  M2 session length (target 10-20 min):   {min(mins)}-{max(mins)} min" if mins else "  M2 session length: n/a")
print(f"  entrance placed leeward:                {frac('entrance_leeward')}")
print(f"  outcomes: " + ", ".join(f"{o}={sum(1 for r in done if r['outcome']==o)}" for o in ("SAFE", "COLD", "DANGEROUS")))
print("  (Not measurable from logs: 'can say the wind direction within 30 s', 'wants to play again',"
      " 'can explain the result' — ask the tester; see playtests/PT_TEMPLATE.md)")
