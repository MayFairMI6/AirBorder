import SafariServices
import SwiftUI

struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct InAppBrowserLink<Label: View>: View {
    let url: URL
    @ViewBuilder let label: () -> Label
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .sheet(isPresented: $isPresented) {
            InAppSafariView(url: url)
                .ignoresSafeArea()
        }
    }
}
