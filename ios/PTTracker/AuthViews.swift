import SwiftUI

struct PhoneSignInView: View {
    @EnvironmentObject private var model: AppModel
    @State private var phone = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("MotionLog.")
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    SignPill(text: "PT")
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 16) {
                    DisplayTitle(text: "Your PT routine, remembered.", size: 48)
                    Text("Sign in with your phone number to see today's exercises and everything you've logged.")
                        .font(.system(size: 16))
                        .lineSpacing(3)
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.top, 72)

                VStack(alignment: .leading, spacing: 10) {
                    SignLabel("Phone number")
                    TextField("", text: $phone, prompt: Text("+1 212 555 0123").foregroundStyle(AppTheme.disabled))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                        .focused($isFocused)
                        .signField()
                        .accessibilityLabel("Phone number")
                }
                .padding(.top, 36)

                Button {
                    isFocused = false
                    Task { await model.requestCode(phone: normalizedPhone) }
                } label: {
                    if model.isLoading { ProgressView().tint(AppTheme.ink) } else { Text("Text me a code") }
                }
                .buttonStyle(SignButtonStyle())
                .disabled(normalizedPhone.count < 8 || model.isLoading)
                .padding(.top, 20)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Text("Message and data rates may apply.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .background(AppTheme.paper.ignoresSafeArea())
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
    @State private var resendRemaining = 30
    @FocusState private var isFocused: Bool

    private let codeLength = 6
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    model.authStep = .phone
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .heavy))
                        Text("BACK").font(.system(size: 14, weight: .heavy)).tracking(1.1)
                    }
                    .foregroundStyle(AppTheme.ink)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Sent to \(phone)")
                    DisplayTitle(text: "Enter your code.")
                }
                .padding(.top, 28)

                if let hint = model.testCodeHint(for: phone) {
                    Text("Development test code: \(hint)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.top, 12)
                }

                codeBoxes
                    .padding(.top, 32)

                Button {
                    isFocused = false
                    Task { await model.verifyCode(code, phone: phone) }
                } label: {
                    if model.isLoading { ProgressView().tint(AppTheme.ink) } else { Text("Continue") }
                }
                .buttonStyle(SignButtonStyle())
                .disabled(code.count != codeLength || model.isLoading)
                .padding(.top, 28)

                HStack {
                    Button("Use a different number") { model.authStep = .phone }
                        .font(.system(size: 15, weight: .bold))
                        .underline(true, color: AppTheme.sign)
                        .foregroundStyle(AppTheme.ink)
                        .buttonStyle(.plain)
                    Spacer()
                    if resendRemaining > 0 {
                        Text("Resend in 0:\(String(format: "%02d", resendRemaining))")
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(AppTheme.muted)
                    } else {
                        Button("Resend code") {
                            resendRemaining = 30
                            Task { await model.requestCode(phone: phone) }
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 24)
        }
        .background(AppTheme.paper.ignoresSafeArea())
        .onAppear { isFocused = true }
        .onReceive(ticker) { _ in
            if resendRemaining > 0 { resendRemaining -= 1 }
        }
    }

    private var codeBoxes: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(width: 1, height: 1)
                .opacity(0.02)
                .onChange(of: code) { _, value in
                    let cleaned = String(value.filter(\.isNumber).prefix(codeLength))
                    if cleaned != value { code = cleaned }
                }
                .accessibilityLabel("Six-digit code")

            HStack(spacing: 8) {
                ForEach(0..<codeLength, id: \.self) { index in
                    box(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
            .accessibilityHidden(true)
        }
    }

    private func box(at index: Int) -> some View {
        let digits = Array(code)
        let isActive = isFocused && index == min(digits.count, codeLength - 1) && digits.count < codeLength
        let isFilled = index < digits.count
        return ZStack {
            if isFilled {
                Text(String(digits[index]))
                    .font(.system(size: 28, weight: .heavy).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
            } else if isActive {
                Rectangle().fill(AppTheme.ink).frame(width: 2, height: 28)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(isActive ? AppTheme.sign : AppTheme.paper, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isFilled || isActive ? AppTheme.ink : Color(red: 0.788, green: 0.804, blue: 0.839), lineWidth: 2)
        )
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isActive ? AppTheme.ink : .clear)
                .offset(x: 3, y: 3)
        )
    }
}
