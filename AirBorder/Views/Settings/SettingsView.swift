import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var longHaulViewModel: LongHaulExperienceViewModel
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var crossDeviceReminders: CrossDeviceReminderCoordinator
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var showCloudConsent = false
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section("Traveler profile") {
                NavigationLink {
                    EntryCheckView()
                } label: {
                    LabeledContent(
                        "Nationality / residence",
                        value: "\(countryName(longHaulViewModel.travelerProfile.nationalityCountryCode)) / \(countryName(longHaulViewModel.travelerProfile.residenceCountryCode))"
                    )
                }
                LabeledContent("Passport type", value: longHaulViewModel.travelerProfile.passportType.rawValue.capitalized)
                Picker("Budget", selection: profileBinding(\.budget)) {
                    ForEach(BudgetPreference.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Recovery", selection: profileBinding(\.recoveryPreference)) {
                    ForEach(RecoveryPreference.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Walking pace", selection: profileBinding(\.walkingPace)) {
                    ForEach(WalkingPacePreference.allCases) { Text($0.title).tag($0) }
                }
                Text("Used to tailor walking-time suggestions.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Accessibility needs", text: profileBinding(\.accessibilityNeeds))
                Text("Only travel preferences are stored. Passport numbers, scans, payment details, and a document vault are intentionally excluded.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Route accessibility") {
                Toggle("Wheelchair routes", isOn: $preferences.accessibility.wheelchairRouting)
                Toggle("Avoid stairs", isOn: $preferences.accessibility.avoidStairs)
                Toggle("Prefer elevators", isOn: $preferences.accessibility.preferElevators)
                Toggle("Avoid escalators", isOn: $preferences.accessibility.avoidEscalators)
                Toggle("Reduce walking", isOn: $preferences.accessibility.reduceWalking)
                Toggle("Simplified directions", isOn: $preferences.accessibility.simplifiedDirections)
                Stepper("Extra boarding buffer: \(preferences.accessibility.extraBoardingBufferMinutes) min", value: $preferences.accessibility.extraBoardingBufferMinutes, in: 0...30)
                Text("We use these choices to suggest routes and plans that better fit your trip.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Guidance") {
                Toggle("Larger AR indicators", isOn: $preferences.accessibility.largerARIndicators)
                Toggle("Spoken navigation", isOn: $preferences.accessibility.spokenNavigation)
                Toggle("Haptic turns", isOn: $preferences.accessibility.hapticTurns)
                Toggle("High contrast overlays", isOn: $preferences.accessibility.highContrast)
                LabeledContent("System Reduce Motion", value: systemReduceMotion ? "On" : "Off")
            }

            Section("Cloud Vision Assist") {
                Toggle("Allow cloud sign recognition", isOn: Binding(
                    get: { preferences.cloudVisionOptIn },
                    set: { value in
                        if value { showCloudConsent = true }
                        else { preferences.cloudVisionOptIn = false }
                    }
                ))
                Text("Off by default. Sign reading works on your device. If you choose, you can send one photo of a sign for extra help reading it. Video is never shared.")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("Cloud proxy", value: container.configuration.cloudVisionProxyBaseURL == nil ? "Not configured" : "Configured")
            }

            Section("Notifications") {
                Toggle("Journey alerts", isOn: Binding(
                    get: { preferences.journeyAlertsEnabled },
                    set: { enabled in
                        Task { await container.setJourneyAlertsEnabled(enabled) }
                    }
                ))
                Toggle("Selected-place alerts", isOn: Binding(
                    get: { preferences.selectedPlaceAlertsEnabled },
                    set: { enabled in
                        preferences.selectedPlaceAlertsEnabled = enabled
                        Task { await container.refreshJourneyAlerts() }
                    }
                ))
                .disabled(!preferences.journeyAlertsEnabled)
                Toggle("Hide journey detail on Lock Screen", isOn: $preferences.privateNotificationContent)
                Text("Get a reminder before it is time to leave, plus alerts for places you selected on this journey.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Cross-device action alerts") {
                Toggle("Sync actions to Apple Calendar", isOn: Binding(
                    get: { crossDeviceReminders.isAppleCalendarEnabled },
                    set: { enabled in
                        Task {
                            if enabled {
                                await crossDeviceReminders.enableAppleCalendar(
                                    using: container.crossDeviceReminderPlanningInput()
                                )
                            } else {
                                await crossDeviceReminders.disableAppleCalendar()
                            }
                        }
                    }
                ))
                .disabled(
                    crossDeviceReminders.appleCalendarState.isBusy
                    || longHaulViewModel.launchContext.mode == .demo
                    || longHaulViewModel.launchContext.mode == .stochastic
                )
                .accessibilityIdentifier("appleCalendarReminderToggle")

                LabeledContent("Apple Calendar", value: crossDeviceReminders.appleCalendarState.title)
                    .accessibilityIdentifier("appleCalendarReminderStatus")
                if let detail = crossDeviceReminders.appleCalendarState.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if crossDeviceReminders.isAppleCalendarEnabled,
                   !crossDeviceReminders.appleCalendarState.isBusy {
                    Button("Sync Calendar actions now") {
                        Task {
                            await crossDeviceReminders.retry(
                                using: container.crossDeviceReminderPlanningInput()
                            )
                        }
                    }
                    .accessibilityIdentifier("syncAppleCalendarRemindersButton")
                }

                switch crossDeviceReminders.appleCalendarState {
                case .permissionDenied, .insufficientAccess:
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                default:
                    EmptyView()
                }

                Text("Off by default. When enabled, Airport XR can add and update gate and return reminders for confirmed trips.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Reminders update while the app is open. To receive them on other devices, use the same synced calendar account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LabeledContent("Google Tasks", value: "Not available in this build")
                    .accessibilityIdentifier("googleTasksReminderStatus")
                Button("Connect Google Tasks") {}
                    .disabled(true)
                    .accessibilityHint("Available after you connect your Google account.")
                    .accessibilityIdentifier("connectGoogleTasksButton")
                Text("Google Tasks connection has not been enabled. Apple Calendar remains available for time-specific reminders.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Data connection") {
                LabeledContent("Network", value: network.isOnline ? "Online" : "Offline")
                LabeledContent("Live travel updates", value: container.configuration.aviationProxyBaseURL == nil ? "Not connected" : "Connected")
                    .accessibilityIdentifier("liveTravelUpdatesStatus")
            }

            Section("On-device predictions") {
                Toggle("Learn from resolved journey data", isOn: Binding(
                    get: { preferences.personalizedPredictionsEnabled },
                    set: { container.setPredictionLearningEnabled($0) }
                ))
                Text("Airport XR can adapt estimates using your completed journeys and feedback. This stays on your device and never changes visa or entry rules.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Reset personal timing insights", role: .destructive) {
                    Task { await container.predictor.eraseLearnedModel() }
                }
                Text("Future version: you can optionally use Apple Health walking metrics to suggest a starting pace. Airport XR will always ask first and will keep the pace setting editable.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Optional trip sharing") {
                Toggle("Share anonymous traveler outcomes", isOn: profileBinding(\.anonymousSharingConsent))
                Text("Off by default and separate from your personal settings. Your travel outcomes stay on this device unless you choose to share them in a future version.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Privacy and offline data") {
                Button("Delete journey and offline data", role: .destructive) { showClearConfirmation = true }
                Text("Your camera text is processed on this device unless you choose Cloud Assist.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Terminal map", value: "Haneda Terminal 3")
                LabeledContent("Layover places", value: "Airport services and nearby search")
                LabeledContent("Trip setup", value: container.launchContext.badgeTitle)
                Text("Always follow official airport displays, signs, staff, and safety instructions.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Settings")
        .alert("Enable Cloud Vision Assist?", isPresented: $showCloudConsent) {
            Button("Not now", role: .cancel) { preferences.cloudVisionOptIn = false }
            Button("Enable") { preferences.cloudVisionOptIn = true }
        } message: {
            Text("Only the photo you approve is sent to Cloud Assist. You can continue even if it cannot be read.")
        }
        .confirmationDialog("Remove this trip and its saved information?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Delete data", role: .destructive) { Task { await container.clearAllAppData() } }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("settingsView")
    }

    private func profileBinding<Value>(_ keyPath: WritableKeyPath<TravelerProfile, Value>) -> Binding<Value> {
        Binding(
            get: { longHaulViewModel.travelerProfile[keyPath: keyPath] },
            set: { value in
                var profile = longHaulViewModel.travelerProfile
                profile[keyPath: keyPath] = value
                Task { await longHaulViewModel.updateTravelerProfile(profile) }
            }
        )
    }

    private func countryName(_ code: String) -> String {
        let name = CountryNameResolver.displayName(for: code)
        return name.isEmpty ? "Not added" : name
    }
}
