import SwiftUI

@main
struct PaymentsMotionApp: App {
    private let inlinePayment: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard
        let key = "inlinePaymentVariant"
        if arguments.contains("--inline-payment") {
            defaults.set(true, forKey: key)
        } else if arguments.contains("--card-payment") {
            defaults.set(false, forKey: key)
        }
        inlinePayment = defaults.bool(forKey: key)
    }

    @ViewBuilder
    private var paymentScreen: some View {
        if inlinePayment {
            InlinePaymentsView().accessibilityElement(children: .contain).accessibilityIdentifier("inlinePaymentScreen")
        } else {
            PaymentsView().accessibilityElement(children: .contain).accessibilityIdentifier("cardPaymentScreen")
        }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--figma-reference-size") {
                // 375 × 812 Figma canvas, excluding its 44 pt status and 34 pt home areas.
                paymentScreen.preferredColorScheme(.light)
                    .frame(width: 375, height: 734).clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                paymentScreen.preferredColorScheme(.light)
            }
            #else
            paymentScreen.preferredColorScheme(.light)
            #endif
        }
    }
}
