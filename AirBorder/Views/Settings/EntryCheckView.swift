import PhotosUI
import SwiftUI

struct EntryCheckView: View {
    @EnvironmentObject private var viewModel: LongHaulExperienceViewModel
    @State private var draft = TravelerProfile.incomplete
    @State private var nationalityInput = ""
    @State private var residenceInput = ""
    @State private var saved = false
    @State private var selectedDocument: PhotosPickerItem?
    @State private var isReadingDocument = false
    @State private var documentMessage: String?

    var body: some View {
        Form {
            Section {
                if let assessment = viewModel.entryAssessment {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(assessment.status.title).font(.headline)
                            Text(assessment.summary).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if !assessment.isCurrent(at: Date()) {
                        Text("Review travel rules before leaving the airport.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    ForEach(assessment.officialVerificationURLs, id: \.absoluteString) { url in
                        InAppBrowserLink(url: url) {
                            Label("View travel rules", systemImage: "arrow.up.right.square")
                        }
                    }
                }
            } header: {
                Text("Personalized entry check")
            }

            Section("Traveler facts") {
                TextField("Nationality (for example, Japan)", text: $nationalityInput)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                TextField("Country of residence (for example, Canada)", text: $residenceInput)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Picker("Passport type", selection: $draft.passportType) {
                    ForEach(PassportType.allCases) { Text(title($0.rawValue)).tag($0) }
                }
                Picker("Purpose", selection: $draft.purpose) {
                    ForEach(TravelPurpose.allCases) { Text(title($0.rawValue)).tag($0) }
                }
                Picker("Luggage", selection: $draft.luggage) {
                    ForEach(LuggagePlan.allCases) { Text(title($0.rawValue)).tag($0) }
                }
                Text("Only the details needed for travel planning are saved.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Add a document") {
                PhotosPicker(selection: $selectedDocument, matching: .images) {
                    Label(isReadingDocument ? "Reading document…" : "Choose document photo", systemImage: "doc.text.viewfinder")
                }
                .disabled(isReadingDocument)
                Text("Text is read on this device to prefill your profile. Review every field before saving; the photo is not stored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let documentMessage {
                    Text(documentMessage)
                        .font(.footnote)
                        .foregroundStyle(documentMessage.hasPrefix("Couldn") ? .orange : .teal)
                }
            }

            Section("Declared visas or permits") {
                if draft.declaredAuthorizations.isEmpty {
                    Text("None declared").foregroundStyle(.secondary)
                }
                ForEach($draft.declaredAuthorizations) { $authorization in
                    HStack {
                        TextField("Country (for example, Japan)", text: $authorization.countryCode)
                            .textInputAutocapitalization(.words)
                        TextField("Type", text: $authorization.kind)
                    }
                }
                .onDelete { draft.declaredAuthorizations.remove(atOffsets: $0) }
                Button {
                    draft.declaredAuthorizations.append(
                        DeclaredTravelAuthorization(countryCode: "", kind: "")
                    )
                } label: {
                    Label("Add declared authorization", systemImage: "plus")
                }
            }

            Section("Official confirmation") {
                Toggle("I reviewed current official rules", isOn: $draft.hasConfirmedOfficialEntryRules)
                Text("Keep your travel details up to date before you leave the airport.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task {
                        guard let nationality = CountryNameResolver.countryCode(for: nationalityInput),
                              let residence = CountryNameResolver.countryCode(for: residenceInput),
                              let authorizations = normalizedAuthorizations(draft.declaredAuthorizations) else {
                            documentMessage = "Enter a country name such as Japan, Canada, or United Kingdom."
                            return
                        }
                        draft.nationalityCountryCode = nationality
                        draft.residenceCountryCode = residence
                        draft.declaredAuthorizations = authorizations
                        await viewModel.updateTravelerProfile(draft)
                        saved = true
                    }
                } label: {
                    Label(saved ? "Saved" : "Save and reassess", systemImage: saved ? "checkmark.circle.fill" : "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .accessibilityIdentifier("saveTravelerProfileButton")
            }
        }
        .navigationTitle("Entry Check")
        .onAppear {
            draft = viewModel.travelerProfile
            nationalityInput = CountryNameResolver.displayName(for: draft.nationalityCountryCode)
            residenceInput = CountryNameResolver.displayName(for: draft.residenceCountryCode)
            draft.declaredAuthorizations = draft.declaredAuthorizations.map { authorization in
                var updated = authorization
                updated.countryCode = CountryNameResolver.displayName(for: authorization.countryCode)
                return updated
            }
        }
        .onChange(of: selectedDocument) { _, item in
            guard let item else { return }
            Task { await prefill(from: item) }
        }
        .onChange(of: draft) { _, _ in saved = false }
        .accessibilityIdentifier("entryCheckView")
    }

    private func title(_ raw: String) -> String {
        raw.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }

    private func normalizedAuthorizations(
        _ authorizations: [DeclaredTravelAuthorization]
    ) -> [DeclaredTravelAuthorization]? {
        var results: [DeclaredTravelAuthorization] = []
        for authorization in authorizations {
            var updated = authorization
            guard let countryCode = CountryNameResolver.countryCode(for: authorization.countryCode) else {
                return nil
            }
            updated.countryCode = countryCode
            results.append(updated)
        }
        return results
    }

    @MainActor
    private func prefill(from item: PhotosPickerItem) async {
        isReadingDocument = true
        defer {
            isReadingDocument = false
            selectedDocument = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw TravelerDocumentPrefillError.unreadableImage
            }
            let result = try await TravelerDocumentPrefillService().prefill(from: data)
            if let nationality = result.nationalityCountryCode {
                draft.nationalityCountryCode = nationality
                nationalityInput = CountryNameResolver.displayName(for: nationality)
            }
            if let residence = result.residenceCountryCode {
                draft.residenceCountryCode = residence
                residenceInput = CountryNameResolver.displayName(for: residence)
            }
            if let passportType = result.passportType { draft.passportType = passportType }
            documentMessage = "Details filled in. Review them, then save."
        } catch {
            documentMessage = "Couldn’t read that document. Enter the details manually instead."
        }
    }
}
