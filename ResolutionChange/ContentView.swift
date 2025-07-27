import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("このアプリはメニューバーに常駐します。")
                .padding()
        }
        .frame(width: 300, height: 100)
    }
}

#Preview {
    ContentView()
}
