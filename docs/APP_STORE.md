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

HealthKit: reads past runs and routes, heart rate, resting heart rate, VO2 max,
steps, running speed and power to set and adapt the plan, and saves recorded runs
as workouts. Nothing leaves the device.
Location (including background): used only while a run is being recorded, so
distance, pace and the route keep counting with the screen locked.
Live Activity: shows the running run on the Lock Screen with Pause and Finish.
Apple Watch (new in 1.0.3): start a run on the watch, then open endurancr on the
iPhone. The watch run appears on the iPhone's Lock Screen through HealthKit workout
mirroring, and Pause and Finish there control the watch. On the watch, double tap
pauses and resumes.
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
- Your watch run now shows on your iPhone's Lock Screen as a Live Activity, with heart rate, distance and pace, once you've opened endurancr on the iPhone during the run. Pause and Finish there act on the watch.
- Double tap (pinch twice) to pause or resume without touching the screen.
- A clearer run screen: the first page shows only what you need while running, time, heart rate, distance and pace with their targets. Turn the Digital Crown or swipe up for Pause and Finish.
- The run clock now ticks every second, also in Always On.
- The summary after a run has two pages too: distance, time and pace first, then what's left this week.
- Auto-Pause from your watch's Workout settings now shows on the run screen, with a tap on your wrist when the run pauses and resumes.
- If the app closes during a run, your run picks up where it was when it opens again.

Also
- Better VoiceOver on the watch run screen: each number is read with its label and target.
- Smaller fixes for steadier recording and saving of runs.

### Build

Pick build 21 for 1.0.3. Builds 15 to 20 aren't for release (20 is the first without the invalid iPhone background mode, 21 adds the review fixes).

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

## Version 1.1.0

### Promotional text (170)

Your running buddy: the plan follows the weeks you really run, eases you back in after a break, and tells you honestly whether your target time fits.

### What's New (4000)

A plan that adapts like a running buddy
- Missed or shorter runs are never piled onto the days after.
- Ran less than planned? The coming weeks build from what you actually ran, at most 10% more each week, and one hard session that week becomes an easy run.
- Back from a break of more than 5 days? Your paces ease a little and you start with easy runs at part of your usual week, following the steps in Daniels' Running Formula.
- Long runs grow step by step: each one at most 10% longer than your longest recent run, based on a 2025 study of over 5,000 runners.
- Paces rise by at most 1 VDOT point for every 3 weeks of the plan, and come down a little when hard sessions keep coming in slower than their target.

An honest outlook on your goal
- Progress shows a finish-time range for today and for race day, instead of a single number.
- It tells you whether your target is on track, within reach, a stretch or unlikely, and why.
- If your target looks out of reach, it suggests a realistic time or a later race. It only changes your target if you tap it.

Also
- How it works explains every new rule and lists the books and studies behind it.

### Screenshots

Re-take them with `./scripts/screenshots.sh`, then `./scripts/publish-screenshots.sh`.
The iPhone Progress screenshot (`iphone-2-progress.png`) now shows the outlook. The
header and search images in `screenshots/appstore/creative/` are rebuilt from the
new screens.

## Version 1.2.0

### Promotional text (170)

Train like the books: marathon-pace runs, strides and a tune-up race, and a Plan tab that shows what you ran, what changed and why, up to race day.

### What's New (4000)

A Plan tab worth opening
- Past days show what you actually ran: done runs are highlighted, missed ones struck through, with distance and pace.
- A run on a rest day shows up as an extra run that counts toward the week, with how hard it was.
- A day the plan changed shows what it was, and the week says why.
- When your paces change, every coming run shows its new pace next to the old one, and this week says why: a run that showed you're fitter, hard sessions that came in slow, or time off.
- Each week says what it's for, its long run, and how much of it you've run.
- On top: the week you're in and the phases up to race day.
- Your 32 km runs and the start of the taper are marked, and the plan ends with your race and its outlook.

Please create your plan again
- After updating, set up your goal again (Today > the menu > Set your goal, or delete the old one first) so your plan gets the new sessions. Update endurancr on your Apple Watch too, so it shows the same plan.

Sessions from the training books
- Marathon-pace runs: every other build week, and the last part of the peak long runs at marathon pace, as in Jack Tupper Daniels, Pete Pfitzinger, the Hansons and Hal Higdon.
- Strides: once or twice a week, an easy run ends with 6 × 20 s quick and light.
- A tune-up race: a 10 km 6 weeks before the marathon (in plans of 14 weeks or more), 5 weeks before a half. Run it all out and your paces follow the result.
- Never more than two harder sessions a week, each within Jack Tupper Daniels' limits.
- Race day tells you how to pace it and how much to eat and drink on the way.
- After the race: rest, then short easy runs, an easy day for every 3 km you raced. Saving your goal as achieved keeps them in your plan.

Try it without installing
- An App Clip: enter one recent race and your goal, and see your VDOT, your five training paces, a race-day range and the plan endurancr would build. Open it from endurancr.app/clip.

Also
- After an easier cutback week, a lighter stretch now holds you at the level of your last full week, not at the cutback.
- Runs on the day your plan starts count, also on a rest day before the first planned run. Before, they were left out until that first run.
- Recordings with hardly any running in them (under 200 m or a minute) are no longer listed or counted, and a run recorded on the watch and the iPhone at once counts once. Recent runs show which app recorded each run.
- A clearer welcome screen with bigger text.
- The goal form and How it works now say clearly that training paces come from your current fitness, not your target time.
- The keyboard closes when you open a date in the goal form, and tapping today as the start date moves on to race day.
- Race-week rest days show a rest icon instead of the vacation one.
- The "Skip Christmas & New Year" switch is gone. To keep a day free, drag its run to another day in the calendar.

### Description (4000)

endurancr builds a running plan around one goal, records your runs on Apple Watch or iPhone, and adapts the plan to what you really ran, like a running buddy who isn't pushy. No account, no feed, no ads.

SET ONE GOAL
Pick a race, from 5K to the marathon, and its date. endurancr builds a full plan with the VDOT method from Jack Tupper Daniels, paced to the fitness you have now. It uses a recent run from Apple Health, or a race result you type in. A short race shows your speed, not your endurance, so marathon pace starts a little easier until your long runs prove it.

TRAINING FROM THE BOOKS
Easy runs, threshold runs, intervals and marathon-pace runs, never more than two hard sessions a week. Strides keep your legs quick. Long runs build to 32 km for the marathon. A tune-up race six weeks out sets your paces. Race day tells you how to pace it and what to eat and drink, and after the race the plan brings you back with rest and easy runs. Based on Jack Tupper Daniels, Pete Pfitzinger, the Hansons and Hal Higdon.

A PLAN THAT FOLLOWS YOU
Every run counts, even one on a rest day. Missed kilometres are never piled onto the days after. Ran less than planned? The coming weeks build from what you actually ran, at most 10% more each week. Back from a break? Your paces ease a little and you start with easy runs. Strong runs nudge your paces up a little at a time. Drag days to swap them when life gets in the way.

THE WHOLE PLAN
See what you ran on each day, what you missed, what changed and why, your new paces next to the old ones, and what each week is for, all the way to race day.

AN HONEST OUTLOOK
Progress shows a finish-time range for today and for race day, and tells you whether your target is on track, within reach, a stretch or unlikely, and why. If it's out of reach, it suggests a realistic time. It only changes your target if you tap it.

RUN ON YOUR WRIST OR YOUR PHONE
Start today's run on Apple Watch with heart rate, or on iPhone with GPS. The run screens show time, distance, your pace and the target pace. The watch's own Auto-Pause holds your run at a traffic light, and a run on the watch shows on your iPhone's Lock Screen, where you can pause and finish it. Every run is saved to Apple Health.

TRY IT WITHOUT INSTALLING
The endurancr App Clip works out your training paces from one recent race, right in Safari or from a link.

NOTHING HIDDEN
How it works explains every rule the plan follows, in plain words, with the books and studies behind it. endurancr is open source, so you can read every line that touches your data.

PRIVATE BY DESIGN
No account, no server, no analytics, no ads, no tracking. Your plan stays on your device, and your runs live in Apple Health.

FREE
No subscription and no in-app purchases.

endurancr is a training aid, not medical advice. Talk to a doctor before you start a new training plan.

### App Clip (new in 1.2.0)

A pace calculator that opens without installing: one recent race and a goal give the
VDOT, the five training paces, a race-day range and a preview of the plan, then
Apple's overlay offers the full app. No HealthKit (App Clips can't use it), nothing
stored. Bundle ID `app.endurancr.Clip`, embedded in the app, so it ships with the build.

In App Store Connect, on the 1.2.0 version page under App Clip:
- **Header image:** `screenshots/appstore/appclip/card-3x2.png` (1800 x 1200, no text; save the subtitle and action first, App Store Connect only takes the image for a saved language).
- **Subtitle (56):** `Your training paces from one recent race, in a minute.`
- **Action:** Open.
- **Default experience:** used by the App Store, Messages and the Safari banner on
  https://endurancr.app/clip (that page has the `app-clip-bundle-id` meta tag, and
  `/.well-known/apple-app-site-association` lists the clip).
- **Advanced experience (optional):** for QR codes or an App Clip Code, add one with
  the URL `https://endurancr.app/clip`, the same image and texts. App Clip Codes can be
  made in App Store Connect once it's live.

The card's title is the app name. To try it before release: run the EndurancrClip
scheme on an iPhone once, then Settings > Developer > App Clips Testing > Local
Experiences, register `https://endurancr.app/clip` for `app.endurancr.Clip`, and scan a
QR code of that URL.

### App Preview video (new in 1.2.0)

`screenshots/appstore/preview/iphone-6.9.mp4`: 886 x 1920, 30 fps, about 25 s, a
silent stereo track, only app footage. Upload it under the 6.9" iPhone screenshots
(App Store Connect uses it for the smaller sizes too); the poster frame can be picked
there. Re-record with `./scripts/app-preview.sh` after `./scripts/screenshots.sh`.

### Screenshots

The iPhone Plan screenshots (`iphone-3-plan.png`, and the new `iphone-4-week.png` with last week) show what was run, the changed
days and the overview. Re-take with `./scripts/screenshots.sh`, then
`./scripts/publish-screenshots.sh`; everything in `screenshots/appstore/` is current.

## Version 1.3.0

### Promotional text (170)

A fresh new look, light and dark, with every run in its own colour. And your paces in a minute: one recent race gives your VDOT, your paces and the plan to start.

### What's New (4000)

A fresh new look
- endurancr has a new design, in light and dark: a calm purple background, glass cards and rounded numbers.
- Every kind of run has its own colour, the same on Today, in the plan and in your paces: easy teal, long run cyan, marathon pace blue, threshold indigo, intervals purple, speed pink, race green.
- Today shows your run big, with its pace and time, and under it your week: a circle for every day, filled once it's done, crossed out if you missed it.
- Below that, your next run and how training is going.
- In the plan, every day has a stripe in its run's colour. Runs with parts (intervals, tempo, a marathon-pace finish) show them as a bar in their colours.
- Progress has a big countdown and your paces as coloured tiles. The longer explanations are one tap away under "How it's worked out".

The pace calculator, now in the app
- The calculator from the App Clip is in endurancr too. Enter one recent race and your goal, and see your VDOT, your five training paces, a race-day range and the plan endurancr would build.
- No plan yet? Open it from the welcome screen with "Work out your paces first", then tap Create this plan: the goal form opens with your race, race day and recent effort filled in.
- Already training? Find it under Progress > Planning > Pace calculator, to check your paces for another race.

Also
- The App Clip has the new look too, in light and dark.

### Description (4000)

endurancr builds a running plan around one goal, records your runs on Apple Watch or iPhone, and adapts the plan to what you really ran, like a running buddy who isn't pushy. No account, no feed, no ads.

SET ONE GOAL
Pick a race, from 5K to the marathon, and its date. endurancr builds a full plan with the VDOT method from Jack Tupper Daniels, paced to the fitness you have now. It uses a recent run from Apple Health, or a race result you type in. A short race shows your speed, not your endurance, so marathon pace starts a little easier until your long runs prove it.

TRAINING FROM THE BOOKS
Easy runs, threshold runs, intervals and marathon-pace runs, never more than two hard sessions a week. Strides keep your legs quick. Long runs build to 32 km for the marathon. A tune-up race six weeks out sets your paces. Race day tells you how to pace it and what to eat and drink, and after the race the plan brings you back with rest and easy runs. Based on Jack Tupper Daniels, Pete Pfitzinger, the Hansons and Hal Higdon.

A PLAN THAT FOLLOWS YOU
Every run counts, even one on a rest day. Missed kilometres are never piled onto the days after. Ran less than planned? The coming weeks build from what you actually ran, at most 10% more each week. Back from a break? Your paces ease a little and you start with easy runs. Strong runs nudge your paces up a little at a time. Drag days to swap them when life gets in the way.

THE WHOLE PLAN
See what you ran on each day, what you missed, what changed and why, your new paces next to the old ones, and what each week is for, all the way to race day.

AN HONEST OUTLOOK
Progress shows a finish-time range for today and for race day, and tells you whether your target is on track, within reach, a stretch or unlikely, and why. If it's out of reach, it suggests a realistic time. It only changes your target if you tap it.

A CALM LOOK, LIGHT AND DARK
Every kind of run has its own colour, the same on Today, in the plan and in your paces. Today shows your run and your week at a glance, a circle for every day.

RUN ON YOUR WRIST OR YOUR PHONE
Start today's run on Apple Watch with heart rate, or on iPhone with GPS. The run screens show time, distance, your pace and the target pace. The watch's own Auto-Pause holds your run at a traffic light, and a run on the watch shows on your iPhone's Lock Screen, where you can pause and finish it. Every run is saved to Apple Health.

YOUR PACES IN A MINUTE
The pace calculator turns one recent race into your VDOT, your five training paces, a race-day range and the plan endurancr would build, ready to start with one tap. It's in the app, and as an App Clip it opens without installing, right in Safari or from a link.

NOTHING HIDDEN
How it works explains every rule the plan follows, in plain words, with the books and studies behind it. endurancr is open source, so you can read every line that touches your data.

PRIVATE BY DESIGN
No account, no server, no analytics, no ads, no tracking. Your plan stays on your device, and your runs live in Apple Health.

FREE
No subscription and no in-app purchases.

endurancr is a training aid, not medical advice. Talk to a doctor before you start a new training plan.

### Build

1.3.0 (35). Build 32 was an unreleased 1.2.0 archive, 33 and 34 earlier 1.3.0 ones; use 35.

### Screenshots and App Preview

All new, in the new design, in light mode. Nine iPhone screenshots: `iphone-5-paces.png`
is the pace calculator, and run, summary, goal and welcome are 6 to 9. Upload all nine
from `screenshots/appstore/` (and the 6.5" and 6.3" folders), in file name order, and
the new App Preview `screenshots/appstore/preview/iphone-6.9.mp4` (886 x 1920, about
27 s). The website shows each screen in light and dark with a slider.

The App Clip card image is new too (`screenshots/appstore/appclip/card-3x2.png`,
1800 x 1200, the clip in its new look): replace it under App Clip on the 1.3.0 page.

## Version 1.4.0

### Promotional text (170)

Intervals on your wrist: your Apple Watch guides every rep with a tap, its pace and a count, then shows honestly how each rep went against its target.

### What's New (4000)

Intervals on your wrist
- On a day with intervals, a threshold run, a marathon-pace block, a tune-up race or strides, your Apple Watch guides you through the session. Its home screen says what's in it, and the button reads Start intervals.
- About 100 m before a rep the watch taps your wrist: "Rep 3 of 6 in 100 m, get ready".
- When the rep starts it taps again, differently: "Go, Rep 3 of 6, 1 km at 4:15/km".
- When it's done a softer tap: "3 of 6 done, easy now". After the last one: "All 6 done".
- Strides are guided the same way: six times about 100 m quick and light, with easy running between.
- The paces come from your current fitness, so they change when your paces do.

Every rep, honestly
- endurancr saves every rep with the run in Apple Health: its distance, time, pace and heart rate, also as segments the Fitness app shows.
- After the run, on the watch and the iPhone, and on that day in the plan, you see each rep against its target: green on pace, orange slower, blue faster than planned. In plain words too, like "4 of 6 reps on pace. Reps 5 and 6 slower."
- The plan follows how your reps really went: when most reps of your hard sessions keep coming in slower than their target, the paces ease a little so they fit again.
- How it works explains it all, with the rules behind it.

### Description (4000)

endurancr builds a running plan around one goal, records your runs on Apple Watch or iPhone, and adapts the plan to what you really ran, like a running buddy who isn't pushy. No account, no feed, no ads.

SET ONE GOAL
Pick a race, from 5K to the marathon, and its date. endurancr builds a full plan with the VDOT method from Jack Tupper Daniels, paced to the fitness you have now. It uses a recent run from Apple Health, or a race result you type in. A short race shows your speed, not your endurance, so marathon pace starts a little easier until your long runs prove it.

TRAINING FROM THE BOOKS
Easy runs, threshold runs, intervals and marathon-pace runs, never more than two hard sessions a week. Strides keep your legs quick. Long runs build to 32 km for the marathon. A tune-up race six weeks out sets your paces. Race day tells you how to pace it and what to eat and drink, and after the race the plan brings you back with rest and easy runs. Based on Jack Tupper Daniels, Pete Pfitzinger, the Hansons and Hal Higdon.

A PLAN THAT FOLLOWS YOU
Every run counts, even one on a rest day. Missed kilometres are never piled onto the days after. Ran less than planned? The coming weeks build from what you actually ran, at most 10% more each week. Back from a break? Your paces ease a little and you start with easy runs. Strong runs nudge your paces up a little at a time. Drag days to swap them when life gets in the way.

THE WHOLE PLAN
See what you ran on each day, what you missed, what changed and why, your new paces next to the old ones, and what each week is for, all the way to race day.

AN HONEST OUTLOOK
Progress shows a finish-time range for today and for race day, and tells you whether your target is on track, within reach, a stretch or unlikely, and why. If it's out of reach, it suggests a realistic time. It only changes your target if you tap it.

A CALM LOOK, LIGHT AND DARK
Every kind of run has its own colour, the same on Today, in the plan and in your paces. Today shows your run and your week at a glance, a circle for every day.

INTERVALS ON YOUR WRIST
On interval days your Apple Watch guides you through every rep: a tap and "get ready" just before it, "Go" with its distance and pace, and how many are done, each with its own tap you can tell apart without looking. Strides are guided too. Afterwards you see every rep against its target, the slower ones too, and the plan's paces follow how your reps really went.

RUN ON YOUR WRIST OR YOUR PHONE
Start today's run on Apple Watch with heart rate, or on iPhone with GPS. The run screens show time, distance, your pace and the target pace. The watch's own Auto-Pause holds your run at a traffic light, and a run on the watch shows on your iPhone's Lock Screen, where you can pause and finish it. Every run is saved to Apple Health.

YOUR PACES IN A MINUTE
The pace calculator turns one recent race into your VDOT, your five training paces, a race-day range and the plan endurancr would build, ready to start with one tap. It's in the app, and as an App Clip it opens without installing, right in Safari or from a link.

NOTHING HIDDEN
How it works explains every rule the plan follows, in plain words, with the books and studies behind it. endurancr is open source, so you can read every line that touches your data.

PRIVATE BY DESIGN
No account, no server, no analytics, no ads, no tracking. Your plan stays on your device, and your runs live in Apple Health.

FREE
No subscription and no in-app purchases.

endurancr is a training aid, not medical advice. Talk to a doctor before you start a new training plan.

### Build

1.4.0 (36).

### Screenshots

The iPhone run summary (`iphone-7-summary.png`) now shows an interval session with its
reps. Two new Apple Watch screenshots: `watch-4-intervals.png` (the card when a rep
starts) and `watch-5-reps.png` (the reps after the run). Everything is in
`releases/1.4.0/`. The App Preview and the App Clip card are unchanged from 1.3.0.

## Version 1.5.0

### Promotional text (170)

Feel like intervals today? Start another session offers them when they fit your fitness and your week, and tells you honestly why when they don't.

### What's New (4000)

Intervals when you feel like it
- Start another session: under Start run on Today, and on your Apple Watch a turn of the Crown below today's run.
- It lists what fits today: this week's own hard session moved to today (today's run takes its place, so nothing is done twice), an interval session of the plan's own size in a week with only one hard session, or strides at the end of today's easy run.
- Only what fits your fitness and your week, by Jack Tupper Daniels' rules: never two hard days side by side, at most two hard sessions a week, nothing hard the day after the long run, the day before it or in the last 10 days before the race, and easy runs only while you ease back in after a break or when your resting heart rate is up.
- When intervals don't fit, it tells you why, like "The day after the long run is for easy running."
- Started on the watch, the change reaches your iPhone's plan too.

### Description (4000)

endurancr builds a running plan around one goal, records your runs on Apple Watch or iPhone, and adapts the plan to what you really ran, like a running buddy who isn't pushy. No account, no feed, no ads.

SET ONE GOAL
Pick a race, from 5K to the marathon, and its date. endurancr builds a full plan with the VDOT method from Jack Tupper Daniels, paced to the fitness you have now. It uses a recent run from Apple Health, or a race result you type in. A short race shows your speed, not your endurance, so marathon pace starts a little easier until your long runs prove it.

TRAINING FROM THE BOOKS
Easy runs, threshold runs, intervals and marathon-pace runs, never more than two hard sessions a week. Strides keep your legs quick. Long runs build to 32 km for the marathon. A tune-up race six weeks out sets your paces. Race day tells you how to pace it and what to eat and drink, and after the race the plan brings you back with rest and easy runs. Based on Jack Tupper Daniels, Pete Pfitzinger, the Hansons and Hal Higdon.

A PLAN THAT FOLLOWS YOU
Every run counts, even one on a rest day. Missed kilometres are never piled onto the days after. Ran less than planned? The coming weeks build from what you actually ran, at most 10% more each week. Back from a break? Your paces ease a little and you start with easy runs. Strong runs nudge your paces up a little at a time. Drag days to swap them when life gets in the way.

THE WHOLE PLAN
See what you ran on each day, what you missed, what changed and why, your new paces next to the old ones, and what each week is for, all the way to race day.

AN HONEST OUTLOOK
Progress shows a finish-time range for today and for race day, and tells you whether your target is on track, within reach, a stretch or unlikely, and why. If it's out of reach, it suggests a realistic time. It only changes your target if you tap it.

A CALM LOOK, LIGHT AND DARK
Every kind of run has its own colour, the same on Today, in the plan and in your paces. Today shows your run and your week at a glance, a circle for every day.

INTERVALS ON YOUR WRIST
On interval days your Apple Watch guides you through every rep: a tap and "get ready" just before it, "Go" with its distance and pace, and how many are done, each with its own tap you can tell apart without looking. Strides are guided too. Afterwards you see every rep against its target, the slower ones too, and the plan's paces follow how your reps really went. Feel like intervals on another day? Start another session offers them when they fit your fitness and your week, and says why when they don't.

RUN ON YOUR WRIST OR YOUR PHONE
Start today's run on Apple Watch with heart rate, or on iPhone with GPS. The run screens show time, distance, your pace and the target pace. The watch's own Auto-Pause holds your run at a traffic light, and a run on the watch shows on your iPhone's Lock Screen, where you can pause and finish it. Every run is saved to Apple Health.

YOUR PACES IN A MINUTE
The pace calculator turns one recent race into your VDOT, your five training paces, a race-day range and the plan endurancr would build, ready to start with one tap. It's in the app, and as an App Clip it opens without installing, right in Safari or from a link.

NOTHING HIDDEN
How it works explains every rule the plan follows, in plain words, with the books and studies behind it. endurancr is open source, so you can read every line that touches your data.

PRIVATE BY DESIGN
No account, no server, no analytics, no ads, no tracking. Your plan stays on your device, and your runs live in Apple Health.

FREE
No subscription and no in-app purchases.

endurancr is a training aid, not medical advice. Talk to a doctor before you start a new training plan.

### Build

1.5.0 (41). Builds 38 to 40 were earlier 1.5.0 archives; use 41.

### Screenshots

New: `iphone-10-another.png` (Another session on iPhone, last in the order) and
`watch-6-another.png` (on the watch). Everything is in `releases/1.5.0/`. The App
Preview and the App Clip card are unchanged.

## Version 1.6.0

### Promotional text (170)

More on your wrist: a second run page with your averages, this km, climb and what is left, and a Finish you hold for a second, so no run ends by accident.

### What's New (4000)

More while you run
- On Apple Watch, turn the Crown during a run for a second page: average pace and heart rate, your last kilometre and the one you're in, metres climbed, and what's left with the time you'll be done.
- During intervals it shows the pace of the rep you're running, the one it's judged by.
- At the planned distance the watch taps once: Plan done. Run on and it shows how far beyond the plan you are.
- The climb is saved to Apple Health as the run's elevation gain.

Finish on purpose
- Hold Finish for a second to end a run, on the watch and the iPhone. A ring fills around it, and the run ends when it's full, so a brush of the wrist or a touch in your pocket doesn't end it.

Done today
- Once today's run is done, Today and the watch home screen say so, with what you ran against what was planned. Start stays there for a second run.

### Description (4000)

endurancr builds a running plan around one goal, records your runs on Apple Watch or iPhone, and adapts the plan to what you really ran, like a running buddy who isn't pushy. No account, no feed, no ads.

SET ONE GOAL
Pick a race, from 5K to the marathon, and its date. endurancr builds a full plan with the VDOT method from Jack Tupper Daniels, paced to the fitness you have now. It uses a recent run from Apple Health, or a race result you type in. A short race shows your speed, not your endurance, so marathon pace starts a little easier until your long runs prove it.

TRAINING FROM THE BOOKS
Easy runs, threshold runs, intervals and marathon-pace runs, never more than two hard sessions a week. Strides keep your legs quick. Long runs build to 32 km for the marathon. A tune-up race six weeks out sets your paces. Race day tells you how to pace it and what to eat and drink, and after the race the plan brings you back with rest and easy runs. Based on Jack Tupper Daniels, Pete Pfitzinger, the Hansons and Hal Higdon.

A PLAN THAT FOLLOWS YOU
Every run counts, even one on a rest day. Missed kilometres are never piled onto the days after. Ran less than planned? The coming weeks build from what you actually ran, at most 10% more each week. Back from a break? Your paces ease a little and you start with easy runs. Strong runs nudge your paces up a little at a time. Drag days to swap them when life gets in the way.

THE WHOLE PLAN
See what you ran on each day, what you missed, what changed and why, your new paces next to the old ones, and what each week is for, all the way to race day.

AN HONEST OUTLOOK
Progress shows a finish-time range for today and for race day, and tells you whether your target is on track, within reach, a stretch or unlikely, and why. If it's out of reach, it suggests a realistic time. It only changes your target if you tap it.

A CALM LOOK, LIGHT AND DARK
Every kind of run has its own colour, the same on Today, in the plan and in your paces. Today shows your run and your week at a glance, a circle for every day.

INTERVALS ON YOUR WRIST
On interval days your Apple Watch guides you through every rep: a tap and "get ready" just before it, "Go" with its distance and pace, and how many are done, each with its own tap you can tell apart without looking. Strides are guided too. Afterwards you see every rep against its target, the slower ones too, and the plan's paces follow how your reps really went. Feel like intervals on another day? Start another session offers them when they fit your fitness and your week, and says why when they don't.

RUN ON YOUR WRIST OR YOUR PHONE
Start today's run on Apple Watch with heart rate, or on iPhone with GPS. The run screens show time, distance, your pace and the target pace, and on the watch a second page adds your averages, this kilometre, climb and what is left. Finish is held for a second, so a run never ends by accident. The watch's own Auto-Pause holds your run at a traffic light, and a run on the watch shows on your iPhone's Lock Screen, where you can pause and finish it. Every run is saved to Apple Health.

YOUR PACES IN A MINUTE
The pace calculator turns one recent race into your VDOT, your five training paces, a race-day range and the plan endurancr would build, ready to start with one tap. It's in the app, and as an App Clip it opens without installing, right in Safari or from a link.

NOTHING HIDDEN
How it works explains every rule the plan follows, in plain words, with the books and studies behind it. endurancr is open source, so you can read every line that touches your data.

PRIVATE BY DESIGN
No account, no server, no analytics, no ads, no tracking. Your plan stays on your device, and your runs live in Apple Health.

FREE
No subscription and no in-app purchases.

endurancr is a training aid, not medical advice. Talk to a doctor before you start a new training plan.

### Build

1.6.0 (43). Build 42 was an earlier 1.6.0 archive with cadence in place of To go; use 43.

### Screenshots

The watch run video and screenshots now show the second page and Hold to finish. The
rest is unchanged from 1.5.0. Everything is in `releases/1.6.0/`.

## Version 1.7.0

### Promotional text (170)

Strides on the clock: two taps when they start, each 20 s burst counted down big on your wrist, and every one saved and shown with its time and pace.

### What's New (4000)

Strides, guided properly
- Strides now run on the clock, not on distance: 20 s is over before GPS has settled, so counting metres tapped your wrist after the burst instead of at it.
- While the easy part of the run is still going, the watch says how far it is until they start.
- Two taps, the only double tap in a run, say the strides are starting, and the screen says what to do first: "Easy 60 s, then 6 × 20 s quick and light".
- Each stride begins with that easy minute, counted down big on the screen, next to the pace the stride before it came out at.
- One tap when the burst starts: the screen turns green with which stride it is, the seconds left as large as the watch can show them, and the pace you're running next to the pace it's aimed at, green while you're near it and orange when you're well off.
- Another tap when it ends, a pip fills for each stride done, and after the sixth: "All 6 strides done, easy to the end".
- No card covers the countdown any more, so the seconds and the pace stay in front of you for the whole burst.

Taps only where they mean something
- Your wrist is tapped where an effort begins or ends, and nowhere else: a tap when a rep or a stride starts, a different one when it ends, two taps before the strides block, and the success tap after the last one.
- Easy running is silent now, warm-up, the jogs between reps and the cool-down included, and so is reaching the planned distance. Those moments are still shown on the screen, they just don't buzz.
- Auto-Pause has its own pair of taps, so the watch pausing you at a traffic light can never be mistaken for a step change.

A screen that fits the kind of run
- Easy and long runs are judged one way only: running them slower is never marked as off pace, which is what the plan always promised. Only going faster than your easy window shows as off.
- A threshold or marathon-pace run shows what's left of the block, and its own pace rather than the whole run's average, which the warm-up drags down. Mid-rep it says how much of the rep is left.
- The jog between reps counts the metres to the next one, with your heart rate and a pip for each rep done.
- Fixed: a run at one steady pace had lost its target pace and target distance on the watch's run screen.

Runs done so far, in plain words
- The count on Progress says what it means: "1 of 4 run days since you started", and when a run came in short of the plan it says so, instead of leaving two numbers that look wrong together.

See what your strides did
- Every stride is saved with the run in Apple Health, with its time, the distance it covered and your heart rate, as segments the Fitness app shows too.
- After the run, in Today and on that day in Plan, each stride shows with its pace: "All 6 strides done, 3:14 to 3:31/km".
- Strides are never marked off against a pace and never count as a hard session: they're run by feel, so nothing about them changes your plan.

### Description (4000)

endurancr builds a running plan around one goal, records your runs on Apple Watch or iPhone, and adapts the plan to what you really ran, like a running buddy who isn't pushy. No account, no feed, no ads.

SET ONE GOAL
Pick a race, from 5K to the marathon, and its date. endurancr builds a full plan with the VDOT method from Jack Tupper Daniels, paced to the fitness you have now. It uses a recent run from Apple Health, or a race result you type in. A short race shows your speed, not your endurance, so marathon pace starts a little easier until your long runs prove it.

TRAINING FROM THE BOOKS
Easy runs, threshold runs, intervals and marathon-pace runs, never more than two hard sessions a week. Strides keep your legs quick. Long runs build to 32 km for the marathon. A tune-up race six weeks out sets your paces. Race day tells you how to pace it and what to eat and drink, and after the race the plan brings you back with rest and easy runs. Based on Jack Tupper Daniels, Pete Pfitzinger, the Hansons and Hal Higdon.

A PLAN THAT FOLLOWS YOU
Every run counts, even one on a rest day. Missed kilometres are never piled onto the days after. Ran less than planned? The coming weeks build from what you actually ran, at most 10% more each week. Back from a break? Your paces ease a little and you start with easy runs. Strong runs nudge your paces up. Drag days to swap them when life gets in the way.

THE WHOLE PLAN
See what you ran on each day, what you missed, what changed and why, your new paces next to the old ones, and what each week is for, all the way to race day.

AN HONEST OUTLOOK
Progress shows a finish-time range for today and for race day, and tells you whether your target is on track, within reach, a stretch or unlikely, and why. If it's out of reach, it suggests a realistic time. It only changes your target if you tap it.

A CALM LOOK, LIGHT AND DARK
Every kind of run has its own colour, the same on Today, in the plan and in your paces. Today shows your run and your week at a glance, a circle for every day.

INTERVALS AND STRIDES ON YOUR WRIST
On interval days your Apple Watch guides you through every rep: "get ready" before it, then a tap and "Go" with its pace, and a tap when it is done. Only the start and end of an effort tap your wrist, so easy running is left in peace. Strides run on the clock: two taps when they start, then every 20 s burst counted down big on your wrist, with a tap at its start and end. Afterwards you see every rep against its target and every stride with its time and pace, and the plan follows how your reps really went. Feel like intervals on another day? Start another session offers them when they fit your week, and says why when they don't.

RUN ON YOUR WRIST OR YOUR PHONE
Start today's run on Apple Watch with heart rate, or on iPhone with GPS. The run screens show time, distance, your pace and the target, and on the watch a second page adds your averages, this kilometre, climb and what is left. Finish is held for a second, so a run never ends by accident. The watch's own Auto-Pause holds your run at a traffic light, and a run on the watch shows on your iPhone's Lock Screen, where you can pause and finish it. Every run is saved to Apple Health.

YOUR PACES IN A MINUTE
The pace calculator turns one recent race into your VDOT, your five training paces, a race-day range and the plan endurancr would build, ready to start with one tap. It's in the app, and as an App Clip it opens without installing, right in Safari or from a link.

NOTHING HIDDEN
How it works explains every rule the plan follows, in plain words, with the books behind it. endurancr is open source, so you can read every line that touches your data.

PRIVATE BY DESIGN
No account, no server, no analytics, no ads, no tracking. Your plan stays on your device, and your runs live in Apple Health.

FREE
No subscription and no in-app purchases.

endurancr is a training aid, not medical advice. Talk to a doctor before you start a new training plan.

### Build

1.7.0 (47). Builds 44 to 46 were earlier 1.7.0 archives, before the taps were cut
back to the start and end of an effort and before the run screen fitted itself to the
kind of run; use 47.

### Screenshots

New: `watch-7-strides.png` (the stride countdown on the watch) and its video through
the whole block, and `iphone-11-strides.png` (the strides in Today after the run). The
watch summary figure now also turns to its strides page, and the Progress figure has
the reworded "runs done so far". The App Preview was re-recorded: the one in 1.3.0 to
1.6.0 still showed Today without "Start another session", the run screen without Hold
to finish and the old Progress wording. Everything is in `releases/1.7.0/`.
