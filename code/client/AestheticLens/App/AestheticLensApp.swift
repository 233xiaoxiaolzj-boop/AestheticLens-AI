import SwiftUI

@main
struct AestheticLensApp: App {
    var body: some Scene {
        WindowGroup {
            CameraView()
                .preferredColorScheme(.dark)
        }
    }
}
