# endurancr: App Store Connect listing

Everything to paste into App Store Connect for version 1.0.0. Limits are Apple's;
the counts next to each field are for the text below.

## New App

| Field | Value |
|---|---|
| Platforms | iOS, iPhone only (the watch app comes inside the iOS app) |
| Name | endurancr |
| Primary language | English (U.S.) |
| Bundle ID | app.endurancr |
| SKU | endurancr |
| User access | Full access |

## App Information

| Field | Value |
|---|---|
| Subtitle (30) | Adaptive running plan |
| Category | Health & Fitness |
| Secondary category | Sports |
| Content rights | No, it does not contain, show or access third-party content |
| Age rating | Answer None / No to every question. Result: 4+ |
| Privacy Policy URL | https://endurancr.app/privacy |

## Pricing and Availability

- Price: Free (USD 0.00)
- Availability: all countries and regions
- EU Digital Services Act: "not a trader" (a free, non-commercial project by a
  private individual, as the privacy policy says). If you pick "trader", Apple
  shows your address, phone and email on the EU App Store.

## App Privacy

- Privacy Policy URL: https://endurancr.app/privacy
- Data collection: **No, we do not collect data from this app.**
  Health, location and runs stay on the device and in Apple Health; nothing is
  sent to a server, which is what Apple counts as collecting. This matches the
  PrivacyInfo.xcprivacy manifests (no tracking, no collected data).

## Version 1.0.0

### Promotional text (170)

A private running plan that adapts to what you really ran. Paced with the VDOT method from Jack Tupper Daniels. Free, with no account and no ads.

### Description (4000)

endurancr builds a running plan around one goal, records your runs on Apple Watch or iPhone, and adapts the plan to what you really ran. No account, no feed, no ads.

SET ONE GOAL
Pick a race, from 5K to the marathon, and its date. endurancr builds a full plan with the VDOT method from Jack Tupper Daniels, paced to the fitness you have now. It uses a recent run from Apple Health, or a race result you type in. A short race shows your speed, not your endurance, so marathon pace starts a little easier until your long runs prove it.

A PLAN THAT FOLLOWS YOU
After every run the plan adapts. Missed your long run? It moves to where it still fits. Ran short? The rest of the week's distance spreads over your easy runs, while the long run and the quality sessions keep theirs. Strong runs nudge your paces up a little at a time. Drag days to swap them when life gets in the way.

RUN ON YOUR WRIST OR YOUR PHONE
Start today's run on Apple Watch with heart rate, or on iPhone with GPS. The run screens show time, distance, your pace and the target pace. A Live Activity lets you pause and finish from the Lock Screen. Every run is saved to Apple Health.

SEE WHERE YOU STAND
Progress shows the days to race day, this week's distance, how well you stick to the plan, your fitness, your projected finish time and all your paces.

NOTHING HIDDEN
How it works explains every rule the plan follows, in plain words. endurancr is open source, so you can read every line that touches your data.

PRIVATE BY DESIGN
No account, no server, no analytics, no ads, no tracking. Your plan stays on your device, and your runs live in Apple Health.

FREE
No subscription and no in-app purchases.

endurancr is a training aid, not medical advice. Talk to a doctor before you start a new training plan.

### Keywords (100)

marathon,training,half marathon,10k,5k,vdot,daniels,coach,pace,runner,long run,race,health,gps

### URLs

| Field | Value |
|---|---|
| Support URL | https://endurancr.app |
| Marketing URL | https://endurancr.app |

### Copyright

2026 Sebastian Käßinger

### Screenshots

Upload in this order (the files in `screenshots/appstore/` are named that way):

- iPhone 6.9" (1320 × 2868): Today, Progress, Plan, Run, Run complete, Goal, Welcome
- Apple Watch (416 × 496, Series 11 46mm): Today, Run, Run complete

### Build

Pick the newest build once it's uploaded from Xcode Organizer.
Export compliance is answered in Info.plist (ITSAppUsesNonExemptEncryption = NO), so
there is no encryption question.

### App Review Information

- Sign-in required: **No** (there is no account)
- Contact: Sebastian Käßinger, +49 172 2774876, info@kaessinger.com
- Notes:

```
endurancr is a free running plan for iPhone and Apple Watch. There is no account,
no server and no in-app purchase; all data stays on the device and in Apple Health.

To try it:
1. Tap "Set your goal", pick a race and a date, and enter a recent result under
   "Recent effort" (or pick a run from Health). Tap Save to see the plan.
2. Today shows the day's run. "Start run" records it on iPhone with GPS; on Apple
   Watch the same run records heart rate too.

HealthKit: reads past runs, heart rate and VO2 max to set and adapt the plan, and
saves recorded runs as workouts. Nothing leaves the device.
Location (including background): used only while a run is being recorded, so
distance, pace and the route keep counting with the screen locked.
Live Activity: shows the running run on the Lock Screen with Pause and Finish.
```

### Version release

Manually release this version (so you choose the day it goes live).

## Version 1.0.2

### Promotional text (170)

Your marathon plan now builds to two 32 km long runs, your half to 19 km. A private, adaptive running plan, paced with the VDOT method from Jack Tupper Daniels.

### What's New (4000)

Longer long runs for the big races
- Marathon plans now build to a 32 km long run, 5 weeks and again 3 weeks before race day, with a shorter one in between. The two taper weeks bring it down to 19 km and 13 km.
- Half marathon plans build to 19 km the same way.
- The long run grows about 2 km a week and never takes more than half the week. A shorter plan stops below the peak instead of jumping to it.
- Lighter weeks are counted back from race day, so the week between the two 32 km runs is an easier one.

Time off
- Add as many vacations as you like when you set a goal. Each new one starts the day after the last.

How it works explains the new long-run rules, with Hal Higdon and Hansons as sources.

## Version 1.0.3

### Promotional text (170)

Pause with a double tap on Apple Watch and follow your watch run on the iPhone Lock Screen. A private running plan that adapts to every run.

### What's New (4000)

Apple Watch
- Your run on the watch now shows on your iPhone's Lock Screen as a Live Activity, with heart rate, distance and pace. Pause and Finish there act on the watch.
- Double tap (pinch twice) to pause or resume without touching the screen.
- A clearer run screen: the first page shows only what you need while running, time, heart rate, distance and pace with their targets, with no scrolling. Turn the Digital Crown or swipe up for Pause and Finish.
- Auto-Pause from your watch's Workout settings now shows on the run screen, with a tap on your wrist when the run pauses and resumes.

### Screenshots (refreshed for 1.0.3)

`./scripts/screenshots.sh`, then copy into `screenshots/appstore/` (same names and order
as before). The sizes Apple accepts are on its screenshot specifications page.

- iPhone 6.9" (1320 × 2868): `screenshots/appstore/iphone-*.png`
- iPhone 6.5" (1284 × 2778): `screenshots/appstore/6.5-inch/`
- iPhone 6.3" (1206 × 2622), the size Apple lists as required: `screenshots/appstore/6.3-inch/`
- Apple Watch (416 × 496): `screenshots/appstore/watch-*.png`. The run screen now shows
  its first page.

### Creative assets (iOS 27 product page header and search results)

`python3 scripts/appstore-creatives.py` writes `screenshots/appstore/creative/`:

| File | Use | Size |
|---|---|---|
| `header-21x9.png` | Product page header, 21:9 | 3840 × 1646 |
| `search-3x2.png` | Search results, 3:2 | 3840 × 2560 |

Upload them in App Store Connect under the new version, or in the Asset Library. Then
check them with the product page preview tool, in Dark Mode too. They follow Apple's asset
best practices:
- The real interface, one short phrase and a centered focal point.
- No prices, URLs, awards or other platforms. The text is in English only, like the listing.
- No alpha channel.
