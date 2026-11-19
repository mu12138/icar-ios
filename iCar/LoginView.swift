import SwiftUI

struct LoginView: View {
    @EnvironmentObject var app: AppModel
    @State private var phone = ""
    @State private var code = ""
    @State private var countdown = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Backdrop()

            VStack(spacing: 22) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("岁岁长安")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.white)
                    Text("登录长安车主账号")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }

                GlassCard(padding: 18) {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "phone.fill")
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 20)
                            TextField("手机号", text: $phone)
                                .keyboardType(.numberPad)
                                .textContentType(.telephoneNumber)
                                .foregroundStyle(.white)
                        }
                        Divider().overlay(Color.white.opacity(0.12))

                        HStack(spacing: 10) {
                            Image(systemName: "number")
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 20)
                            TextField("验证码", text: $code)
                                .keyboardType(.numberPad)
                                .foregroundStyle(.white)
                            Button(countdown > 0 ? "\(countdown)s" : "获取") {
                                sendCode()
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(countdown > 0 ? .white.opacity(0.35) : Theme.accent)
                            .disabled(countdown > 0 || phone.count < 6)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Button {
                    Task { await app.login(phone: phone, code: code) }
                } label: {
                    Text("登 录")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(colors: [Theme.accent, Theme.accent2],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .disabled(app.busy || phone.isEmpty || code.isEmpty)
                .opacity(app.busy ? 0.6 : 1)

                Text("登录态只保存在这台手机上")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.35))

                Spacer()
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sendCode() {
        Task { await app.sendCode(phone) }
        countdown = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if countdown > 0 { countdown -= 1 } else { timer?.invalidate() }
            }
        }
    }
}
