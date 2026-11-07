import SwiftUI

struct PhoneSignInView: View {
    @EnvironmentObject private var model: AppModel
    @State private var phone = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AppTheme.coral)
            VStack(alignment: .leading, spacing: 8) {
                Text("Your PT routine, remembered")
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.navy)
                Text("Use your phone number to securely access your prescribed exercises and history.")
                    .foregroundStyle(.secondary)
            }
            TextField("+1 212 555 0123", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .font(.title3)
                .padding()
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
            Button {
                Task { await model.requestCode(phone: normalizedPhone) }
            } label: {
                Group {
                    if model.isLoading { ProgressView().tint(.white) }
                    else { Text("Text me a code") }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(normalizedPhone.count < 8 || model.isLoading)
            Spacer()
            Text("Message and data rates may apply.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(AppTheme.background.ignoresSafeArea())
    }

    private var normalizedPhone: String {
        let digits = phone.filter(\.isNumber)
        if phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") { return "+\(digits)" }
        return digits.count == 10 ? "+1\(digits)" : "+\(digits)"
    }
}

struct CodeVerificationView: View {
    @EnvironmentObject private var model: AppModel
    let phone: String
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("Enter your code")
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.navy)
            Text("We sent a six-digit code to \(phone).")
                .foregroundStyle(.secondary)
            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .tracking(12)
                .multilineTextAlignment(.center)
                .padding()
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .onChange(of: code) { _, value in
                    code = String(value.filter(\.isNumber).prefix(6))
                }
            Button("Continue") {
                Task { await model.verifyCode(code, phone: phone) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(code.count != 6 || model.isLoading)
            Button("Use a different number") { model.authStep = .phone }
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(24)
        .background(AppTheme.background.ignoresSafeArea())
    }
}
