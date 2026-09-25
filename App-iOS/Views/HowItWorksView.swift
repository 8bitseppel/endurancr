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
                    detail: "Each week has a total distance, and the run lengths come from splitting it. That weekly total starts around half your peak and climbs at most ~8% a week, with an easier cutback every 4th week and two taper weeks before the race. Peak weekly volume scales with your race (longer race → more km). Within a week, the long run is always the single longest run, a set share of the week's total, capped by race distance so it never overreaches (e.g. 32 km for a marathon, 16 km for a 10K). The remaining distance is spread evenly across your other running days as easy or quality sessions, and no easy run is ever longer than the long run."
                )

                topic(
                    "Adapting to your runs",
                    icon: "arrow.triangle.2.circlepath",
                    detail: "Strong recent runs nudge your VDOT up (gently, at most a couple of points at a time) and re-pace only your upcoming workouts. A missed long run is rescheduled onto your next open day; past weeks are never rewritten. If you are behind on the current week, the missing km move onto the week's remaining easy runs: each grows by at most half and never past the long run, and the long run and hard sessions keep their distance. Hold a day in Plan and drag it onto another to swap them. Your Apple Watch shows the same adjusted days as your iPhone."
                )

                exampleSection

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
                    detail: "The weekdays you don't want to train repeat every week; vacation periods are one-off breaks. You can also skip the year-end holidays (Christmas Eve to Boxing Day and New Year's Eve to New Year's Day) with one toggle. All of them blank out training on those days, and the plan works around them."
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
                    detail: "The training system: VDOT, the five pace zones, periodization, and long-run guidance."
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
