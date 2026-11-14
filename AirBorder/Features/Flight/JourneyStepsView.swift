import SwiftUI

/// Figma "Journey steps (Haneda connection)" (1041:16964): the step list behind the progress strip.
struct JourneyStepsView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let checklist = store.checklist
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Journey steps") { dismiss() }
            SectionLabel(text: (store.isAirportTransfer ? "Transfer to Narita · " : "Haneda connection · ") + (checklist.currentIndex.map { "Step \($0 + 1) of \(checklist.steps.count)" } ?? "All steps done"))
                .accessibilityIdentifier("stepCount")
            GroupedList {
                ForEach(Array(checklist.steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { RowDivider() }
                    row(step, number: index + 1, checklist: checklist)
                }
            }
        }
    }

    private func row(_ step: JourneyStep, number: Int, checklist: JourneyChecklist) -> some View {
        let isCurrent = checklist.canConfirm(step.id)
        return HStack(spacing: 14) {
            StepMarker(state: step.state, number: number, isCurrent: isCurrent, size: 28)
            if checklist.canSkip(step.id) {
                VStack(alignment: .leading, spacing: 10) {
                    stepLabel(step, status: checklist.status(of: step))
                    Text("Check with airport staff before skipping.")
                        .outfitText(13, .regular, AB.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            completeButton(step)
                            skipButton(step)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) {
                            completeButton(step)
                            skipButton(step)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                stepLabel(step, status: checklist.status(of: step), showStatus: isCurrent || step.state == .skipped)
                Spacer(minLength: 4)
                if isCurrent {
                    completeButton(step)
                } else if checklist.canUndo(step.id) {
                    CTAButton(title: "Undo", style: .plain, height: 44, fullWidth: false) {
                        store.undoStep()
                    }
                    .accessibilityIdentifier("undo-\(step.id)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isCurrent ? Color(hex: 0xFFF7DE) : .clear)
    }

    private func stepLabel(_ step: JourneyStep, status: String, showStatus: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(step.title).outfitText(16, .semibold)
            if showStatus {
                Text(status).outfitText(13, .regular, AB.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.title)
        .accessibilityValue(status)
        .accessibilityIdentifier("journey-step-\(step.id)")
    }

    private func completeButton(_ step: JourneyStep) -> some View {
        CTAButton(title: "Mark complete", height: 44, fullWidth: false) {
            store.confirmStep(step.id)
        }
        .accessibilityIdentifier("confirm-\(step.id)")
    }

    private func skipButton(_ step: JourneyStep) -> some View {
        CTAButton(title: "Skip this step", style: .outline, height: 44, fullWidth: false) {
            store.skipStep(step.id)
        }
        .accessibilityHint("Check with airport staff before skipping.")
        .accessibilityIdentifier("skip-\(step.id)")
    }
}

/// A checkmark records confirmation and a dash records a traveller-selected skip.
struct StepMarker: View {
    let state: StepState
    let number: Int
    let isCurrent: Bool
    let size: CGFloat

    var body: some View {
        let confirmed = state == .confirmed
        let side = isCurrent ? max(size, 28) : size
        Text(symbol)
            .outfitText(isCurrent ? 13 : 12, isCurrent ? .semibold : .bold, confirmed ? .white : (isCurrent ? AB.gateText : AB.primary))
            .frame(width: side, height: side)
            .background(confirmed ? AB.primary : (isCurrent ? AB.gateYellow : AB.chip), in: Circle())
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch state {
        case .confirmed: "✓"
        case .skipped: "–"
        case .pending: "\(number)"
        }
    }
}

/// Figma "Journey progress" (1060:17026): five checkpoints from arrival to the gate.
struct JourneyProgressStrip: View {
    let checklist: JourneyChecklist

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                let count = CGFloat(checklist.steps.count)
                let column = proxy.size.width / count
                let currentX = column * (CGFloat(checklist.currentIndex ?? checklist.steps.count - 1) + 0.5)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(AB.chip).frame(width: proxy.size.width - column, height: 2).offset(x: column / 2, y: 13)
                    Rectangle().fill(AB.primary).frame(width: max(currentX - column / 2, 0), height: 2).offset(x: column / 2, y: 13)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(checklist.steps.enumerated()), id: \.element.id) { index, step in
                    let isCurrent = checklist.currentIndex == index
                    VStack(spacing: 6) {
                        StepMarker(state: step.state, number: index + 1, isCurrent: isCurrent, size: 24)
                            .frame(width: 28, height: 28)
                        Text(step.shortTitle)
                            .outfitText(11, isCurrent ? .semibold : .regular, isCurrent ? AB.navy : AB.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: 300)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("journeyProgress")
    }

    private var accessibilityText: String {
        let progress = checklist.currentIndex.map { index in
            "Step \(index + 1) of \(checklist.steps.count), \(checklist.steps[index].title)"
        } ?? "All steps done"
        let skipped = checklist.steps.filter { $0.state == .skipped }.map(\.title)
        return skipped.isEmpty ? progress : "\(progress). Skipped: \(skipped.joined(separator: ", "))"
    }
}
