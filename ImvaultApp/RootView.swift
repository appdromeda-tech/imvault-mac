import Contacts
import SwiftUI

struct RootView: View {
    @State private var fdaStatus: FDAStatus?
    @State private var contactsStatus: CNAuthorizationStatus = .notDetermined

    var body: some View {
        Group {
            switch fdaStatus {
            case .none:
                ProgressView("Checking permissions…")
                    .frame(minWidth: 600, minHeight: 400)
            case .missing:
                FDAOnboardingView(onRecheck: refresh)
            case .granted:
                ContentView(contactsStatus: contactsStatus)
            }
        }
        .task {
            refresh()
            // Prompt for Contacts on first launch (no-op if already decided).
            if contactsStatus == .notDetermined {
                contactsStatus = await Permissions.requestContacts()
            }
        }
    }

    private func refresh() {
        fdaStatus = Permissions.checkFullDiskAccess()
        contactsStatus = Permissions.contactsStatus()
    }
}

#Preview {
    RootView()
}
