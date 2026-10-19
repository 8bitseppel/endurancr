import SwiftUI
import TrainingCore

/// Static, data-free explainer for the rules the training engine uses. The copy
/// mirrors the behavior implemented in `TrainingCore` (VDOTPlanGenerator,
/// PaceZones, the adaptation and fatigue steps) so what the athlete reads matches
/// what the app actually does.
struct HowItWorksView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("endurancr plans and adapts your training with a rule-based, deterministic engine built on Jack Tupper Daniels' VDOT method. Everything runs on your device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                topic(
                    "Your recent effort → VDOT",
                    icon: "speedometer",
                    detail: "You give one recent race or hard run: a distance and a time. Jack Tupper Daniels' formula turns that into a VDOT, a single number for your aerobic fitness (it's what predicts your finish time and sets every pace). A faster run for the same distance means a higher VDOT. This is the one input the whole plan is built from, so pick a genuine hard effort. You can also pull it straight from a real run in Apple Health. Record strong runs and the VDOT nudges up a little at a time. It is never lowered automatically: if your paces feel too hard, enter a more recent effort in your goal."
                )

                topic(
                    "Paces from VDOT",
                    icon: "gauge.with.dots.needle.67percent",
                    detail: "The five training paces are fixed fractions of your VDOT, easiest to hardest: easy (aerobic base, most of your volume), marathon (goal-race effort), threshold (comfortably hard, lifts your lactate ceiling), interval (top-end aerobic power), and repetition (speed & economy). Raise the VDOT and all five get quicker together. Marathon pace has one exception, explained next."
                )

                topic(
                    "Marathon pace needs endurance",
                    icon: "road.lanes",
                    detail: "An all-out 10 km or relay leg is a great measure of speed, but it doesn't show that you can hold a pace for much longer. Jack Tupper Daniels makes the same point: a marathon prediction from a shorter race assumes you have the endurance training behind it. So when your effort was much shorter than your goal race (a half marathon or longer), marathon pace and your projected finish use a VDOT up to 3 points lower. Easy, threshold and interval paces still come from your full VDOT. Long runs earn it back: from about 14 km on, each longer run in the last 8 weeks returns more, and a 25 km run, the plan's longest, returns all of it for a marathon (85% of the distance for shorter goals). Until then the plan is never a \"good to go\" maintenance plan: it builds up to those long runs even if your pace already meets your target. Progress shows both numbers."
                )

                topic(
                    "Why each run is that length",
                    icon: "ruler",
                    detail: "Each week has a total distance, and the run lengths come from splitting it. That weekly total starts around half your peak and climbs at most ~8% a week, with an easier cutback every 4th week (counted back from race day) and two taper weeks before the race. Peak weekly volume scales with your race (longer race → more km). Within a week, the long run is always the single longest run, a set share of the week's total, capped by race distance so it never overreaches (e.g. 16 km for a 10K). For a marathon it builds to 32 km, about 2 km a week: a 32 km run 5 weeks and again 3 weeks before race day with a shorter one between, then 19 km and 13 km in the taper, as in the plans of Hal Higdon and Hansons. A half marathon builds to 19 km the same way. The long run never takes more than half the week, so a short plan stops below the peak instead of jumping to it. The remaining distance is spread evenly across your other running days as easy or quality sessions, and no easy run is ever longer than the long run."
                )

                topic(
                    "Which days you run",
                    icon: "calendar",
                    detail: "The long run goes on Sunday, or Saturday if you keep Sundays free. The other runs are spread over the week as it repeats, so Sunday's long run counts as right before next Monday: as few runs back to back as your days per week allow, no long streaks, and a rest day after the long run whenever there's one to spare. With 5 days a week that's Tuesday, Wednesday, Thursday, Saturday and Sunday. Threshold runs and intervals never sit right before or after the long run, or next to each other."
                )

                topic(
                    "The harder sessions",
                    icon: "bolt.heart",
                    detail: "Base weeks are easy runs and a long run. From the build on there's a threshold run each week, and in the peak weeks intervals too, unless the long run finishes at marathon pace: never more than two harder sessions a week, as Jack Tupper Daniels plans them. Each one stays within his limits: the threshold part at most 10% of the week, intervals at most 8% or 10 km, marathon pace at most 20% or 29 km. What a limit takes off goes to the easy warm-up and cool-down, so the run keeps its length. One limit is set aside on purpose: Daniels keeps the long run to about 25 to 30% of the week, and the 32 km run is more than that for most runners."
                )

                topic(
                    "Marathon-pace runs",
                    icon: "metronome",
                    detail: "Every marathon book has them: Daniels' M-pace runs, Pfitzinger's long runs with a marathon-pace block, the Hansons' weekly goal-pace tempo, Hal Higdon's pace runs. In a marathon plan every other build week swaps the threshold run for one: 2 km easy, the rest at marathon pace, 1 km easy. Peak long runs finish at marathon pace: the last third, at most 16 km, as in Pfitzinger's plans. They count as one of the week's two harder sessions. The 32 km runs and the easier weeks stay easy. Marathon pace comes from your current fitness, like all paces."
                )

                topic(
                    "Strides",
                    icon: "hare",
                    detail: "Once a week in the base and taper and twice in the build and peak, an easy run ends with 6 × 20 seconds of strides: quick and light, not a sprint, about a minute easy between them. Daniels uses 4 to 6. They keep your legs quick without making you tired. They go on easy days that aren't right before the long run or a harder session whenever the week has such days."
                )

                topic(
                    "A tune-up race",
                    icon: "flag.2.crossed",
                    detail: "Daniels moves your paces up only when a race shows you're ready, and Pfitzinger puts tune-up races in the weeks before a marathon, the first one 6 weeks out. So the plan has one: a 10 km 6 weeks before race week for the marathon, 5 weeks before for the half, and a 5 km 4 weeks before a 10 km, in plans long enough for it. Run it all out, in a local race or on your own, with 2 km easy before and 1.5 km after. That week is about 10% lighter, with no other harder session. Your result counts in full: if it shows a higher VDOT, your paces follow it right away. Any other fast run counts by half, since it may not have been all out. Skipping the tune-up changes nothing."
                )

                topic(
                    "Race day",
                    icon: "flag.checkered",
                    detail: "Start at your race pace, not faster, and keep it even. In races of over an hour, take carbohydrate from early on: about 60 g an hour, and in races over about 2½ hours up to 90 g from drinks and gels with mixed sugars (Jeukendrup 2014). Your gut gets used to it with practice, so the marathon's peak long runs remind you to try your race-day drinks and gels on them."
                )

                topic(
                    "After the race",
                    icon: "bed.double",
                    detail: "Daniels gives an easy day for every 3 km raced: about 14 days after a marathon, 7 after a half, 3 after a 10 km. The plan goes on after race day with those days: full rest first (3 days after a marathon, as in Hal Higdon's post-marathon weeks), then short easy runs every other day, growing a little. They're only if your legs feel ready. They don't count toward your training weeks or progress."
                )

                topic(
                    "Adapting to your runs",
                    icon: "arrow.triangle.2.circlepath",
                    detail: "The plan works like a running buddy who isn't pushy: it paces the coming weeks to the training you actually do, and past weeks are never rewritten. Missed kilometres are never piled onto later days, as Pete Pfitzinger, the Hansons and Hal Higdon all advise. A long run you missed moves to a free day only within the next 3 days, and only while training goes about as planned. Hold a day in Plan and drag it onto another to swap them. Your Apple Watch shows the same adjusted days as your iPhone. The rules are below, with where they come from."
                )

                exampleSection

                topic(
                    "Reading the plan",
                    icon: "list.bullet.rectangle",
                    detail: "Plan opens around today. On top: the week you're in and a bar of the phases (base, build, peak, taper, race week) with today marked. Each week says what it's for, its long run, and how much of it you've run. The current week also says how training is going and, when your paces changed, why: faster after a run that showed you're fitter, slower when hard sessions came in slow, eased after a break. Every coming run then shows its new pace and what it was. Past days show what Apple Health recorded: done (at least 80% of the distance), shorter, or missed. A day the plan changed shows what it was, and the week says why once. The plan's longest runs (32 km for a marathon) and the start of the taper are marked, and it ends with your race and the outlook for it."
                )

                topic(
                    "When you run less than planned",
                    icon: "figure.walk",
                    detail: "The plan compares the kilometres you ran with the kilometres planned over the last two weeks (time off you added is left out). 90% or more is going really well (Pete Pfitzinger's benchmark), and the plan keeps building. 75 to 90%: this week stays at the level of your last full week (an easier cutback week doesn't count) instead of growing, and never more than 10% over what you ran. Under 75%: the coming week is about 10% more than you actually ran each week lately (at least half the plan), one hard session that week becomes an easy run, and from there each week grows by at most 10% until it meets the plan again. Runners who added more than 30% in two weeks had more injuries (Nielsen et al. 2014)."
                )

                topic(
                    "After a break",
                    icon: "leaf",
                    detail: "Up to 5 days without running changes nothing, as Jack Tupper Daniels writes. After a longer break your paces get a little easier by his table (for example 2% after 10 days, 5% after 3 weeks, 15% after 8 weeks) and you ease back in with easy runs only, at a share of the weekly distance you ran before: after 6 to 28 days off, half of it for the first half of the time you were away, then three quarters; after 4 to 8 weeks, a third, a half, then three quarters; after longer, five 3-week steps up to your full week. The welcome-back note on Today and Progress tells you when you're in this phase."
                )

                topic(
                    "No run much longer than your recent longest",
                    icon: "ruler",
                    detail: "A run more than 10% longer than your longest run of the last 30 days goes with more injuries, in a study of 5,205 runners (Frandsen et al. 2025). So no upcoming run is planned longer than that, counting the runs before it as done: if your longest recent run was 12 km, the next long run is at most 13.2 km, the one after at most 14.5 km. If you're behind, the 32 km peak comes later, or not before this race."
                )

                topic(
                    "Paces that follow your form",
                    icon: "speedometer",
                    detail: "A strong run (a race or a fast effort of 3 km or more) moves your VDOT halfway to what it shows, by at most 1 point for every 3 weeks of the plan, as Daniels advises not to raise it more often. When at least two of your hard sessions in the last 4 weeks, and most of them, come in more than 3% slower than planned (counting warm-up, cool-down and recoveries at easy pace), your VDOT drops by 1 so the paces fit again. Without any runs from Apple Health, the plan stays as it is. Running easy days slower than easy pace is never counted against you."
                )

                topic(
                    "An honest outlook",
                    icon: "binoculars",
                    detail: "Progress shows two finish-time ranges: if the race were today, and on race day if training goes on like the last two weeks. Fitness grows by at most 1 VDOT per 8 weeks of training (Daniels), less when fewer runs get done and none below 75% of the plan. Marathon predictions from shorter races run too fast for most recreational runners: about half finish 10 or more minutes slower, a quarter 20 or more, and weekly distance explains much of it (Vickers & Vertosick 2016). So under 80 km a week the marathon range gets slower. The verdict compares your target with race day: on track, within reach (at most 1 VDOT more), a stretch (up to 2) or unlikely. More than 20 days missed, or 10 to 20 with under 8 weeks left, makes it at least a stretch (Pfitzinger). A marathon plan of under 18 weeks started without a base of about 40 km a week and a long run near 16 km is unlikely. When it's a stretch or unlikely, it suggests a realistic time, or a later race for your target, and only changes your target if you tap it."
                )

                topic(
                    "Your target time and your paces",
                    icon: "speedometer",
                    detail: "Your training paces always come from your current fitness, never from your target time. Jack Tupper Daniels' rule is to train at the fitness you have: hard sessions at the pace of a goal you haven't reached yet are how runners get hurt. So changing the target doesn't change the training paces; your runs do, as they show you're fitter. The target sets the race-day pace, the outlook in Progress, and whether you get a maintenance plan."
                )

                topic(
                    "\"You're good to go\"",
                    icon: "checkmark.seal",
                    detail: "Every goal time implies a target VDOT, the fitness you'd need to run it. If your VDOT already meets that target, endurancr tells you you're good to go and switches to a maintenance plan that holds your fitness (steady volume, one weekly quality session and a long run) so you arrive at race day sharp instead of over-trained. When race day passes you can mark the goal achieved and keep a summary of what you did."
                )

                topic(
                    "Fatigue easing",
                    icon: "heart.text.square",
                    detail: "If your resting heart rate climbs or aerobic efficiency dips, the next hard session is automatically eased to an easy run so you recover instead of digging deeper."
                )

                topic(
                    "The rules you set",
                    icon: "slider.horizontal.3",
                    detail: "The weekdays you don't want to train repeat every week; vacation periods are one-off breaks. Both blank out training on those days, and the plan works around them. For a single day, like Christmas, drag the run to another day in the calendar."
                )

                topic(
                    "Recording on Apple Watch",
                    icon: "applewatch",
                    detail: "A run on Apple Watch also shows on your iPhone's Lock Screen as a Live Activity, through Apple's workout mirroring, with heart rate and Pause and Finish buttons that act on the watch. If the run starts while endurancr is closed on the iPhone, it appears the next time you open the app. Auto-pause is Apple's: turn on Auto-Pause in the watch's Workout settings and watchOS notices when you stop, at a traffic light for example, and when you move again. The run screen then shows Auto-paused and taps your wrist, and Apple Health keeps the pause with the workout. endurancr doesn't detect stops itself, so runs recorded on iPhone don't auto-pause. On the watch, double tap (pinch twice) to pause or resume."
                )

                sourcesSection

                Section {
                    Text("Rule-based and deterministic, not medical advice. Check with a professional before ramping up training.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("How it works")
        }
    }

    /// A concrete, end-to-end walk-through so the abstract rules land: one runner,
    /// real numbers, from a first 5K to "good to go". Every VDOT and pace here is
    /// what the engine's Daniels–Gilbert math actually produces for these inputs.
    private var exampleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Label("A worked example", systemImage: "figure.run.circle")
                    .font(.headline)
                Text("Say you run a 5K at a comfortable, moderate pace and set your sights on a faster 10K.")
                    .font(.subheadline).foregroundStyle(.secondary)

                exampleStep(
                    "Your starting point",
                    "A 5K in 30:00 (6:00/km) reads as a VDOT of about 31. At that fitness a 10K would take you roughly 62 minutes."
                )
                exampleStep(
                    "You set a goal",
                    "10K in 54:00. That target needs a VDOT of about 37, a bit above where you are, so endurancr builds a progressive plan to close the gap."
                )
                exampleStep(
                    "You train the paces",
                    "From VDOT 31 your easy pace is ~7:30/km and your threshold (\"comfortably hard\") work is ~6:16/km. You run those sessions, and the strong runs nudge the VDOT up, 31 → 33 → 35, with every pace quickening as it climbs (threshold moves 6:16 → 5:56 → 5:40/km)."
                )
                exampleStep(
                    "You're good to go",
                    "Around VDOT 37 your projected 10K reaches 54:00, and you've hit the target. endurancr flags you good to go and switches to a maintenance plan that holds that fitness right through to race day.",
                    highlighted: true
                )
            }
            .padding(.vertical, 2)
        } footer: {
            Text("Illustrative numbers from the same VDOT math the app uses. Your own plan is built from your real 5K and goal.")
        }
    }

    private func exampleStep(_ title: String, _ detail: String, highlighted: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: highlighted ? "checkmark.seal.fill" : "arrow.turn.down.right")
                .font(.subheadline)
                .foregroundStyle(highlighted ? .green : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(highlighted ? .green : .primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Primary sources behind the methodology, so the numbers can be verified and
    /// read up on. Nothing proprietary — it's all published running science.
    private var sourcesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Sources", systemImage: "books.vertical")
                    .font(.headline)
                Text("Every number here comes from published running science, nothing proprietary. Read the primary sources:")
                    .font(.subheadline).foregroundStyle(.secondary)

                source(
                    title: "Daniels' Running Formula (4th ed.)",
                    author: "Jack Tupper Daniels, PhD · Human Kinetics, 2021",
                    detail: "The training system: VDOT, the five pace zones, periodization, long-run guidance, the limits per session, strides, updating VDOT from races, and an easy day for every 3 km raced. The steps back after time off follow the 3rd edition (2014) and Daniels' VDOT adjustments for time off (news.vdoto2.com)."
                )
                source(
                    title: "Marathon and half marathon training plans",
                    author: "Hal Higdon (halhigdon.com) · Hansons Marathon Method",
                    detail: "When the longest long runs go: 32 km for the marathon and 19 km for the half, the last one about 3 weeks before race day. Goal-pace runs, and Higdon's post-marathon weeks that start with rest."
                )
                source(
                    title: "Advanced Marathoning and Faster Road Racing",
                    author: "Pete Pfitzinger and Scott Douglas · Human Kinetics",
                    detail: "Making up for lost time after missed training, the 90% benchmark, the base before a marathon plan, not cramming missed mileage, marathon-pace long runs and tune-up races."
                )
                source(
                    title: "A Step Towards Personalized Sports Nutrition: Carbohydrate Intake During Exercise (2014)",
                    author: "Asker Jeukendrup, Sports Medicine",
                    detail: "About 60 g of carbohydrate an hour in longer races, up to 90 g from mixed sugars past about 2½ hours, and training the gut."
                )
                source(
                    title: "How much running is too much? (BJSM, 2025)",
                    author: "Frandsen et al., 5,205 runners",
                    detail: "Single runs more than 10% longer than the longest of the last 30 days and injury risk."
                )
                source(
                    title: "An empirical study of race times in recreational endurance runners (2016)",
                    author: "Vickers & Vertosick, BMC Sports Science, Medicine and Rehabilitation",
                    detail: "Why predictions from shorter races run too fast for recreational marathoners, and how weekly distance matters."
                )
                source(
                    title: "Excessive progression in weekly running distance (JOSPT, 2014)",
                    author: "Nielsen et al.",
                    detail: "More injuries among novice runners who added more than 30% in two weeks."
                )
                source(
                    title: "Oxygen Power: Performance Tables for Distance Runners",
                    author: "J. Daniels & J. Gilbert, 1979",
                    detail: "The Daniels and Gilbert equations this app implements to turn a race time into a VDOT and to predict finish times."
                )

                Link(destination: URL(string: "https://en.wikipedia.org/wiki/Jack_Daniels_(coach)")!) {
                    Label("About Jack Tupper Daniels & VDOT (Wikipedia)", systemImage: "safari")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 2)
        } footer: {
            Text("The VDOT and pace math is implemented deterministically in the app's TrainingCore engine. The same inputs always produce the same plan, and you can check any pace against the published tables.")
        }
    }

    private func source(title: String, author: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(author).font(.caption).foregroundStyle(.secondary)
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func topic(_ title: String, icon: String, detail: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}
