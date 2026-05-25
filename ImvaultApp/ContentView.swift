import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("imvault")
                .font(.largeTitle)
            Text("macOS GUI — scaffold")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }
}

#Preview {
    ContentView()
}
