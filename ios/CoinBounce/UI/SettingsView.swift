import SwiftUI

// MARK: - 设置页
struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore = .shared
    @ObservedObject var ads: AdsManager = .shared
    @Environment(\.dismiss) private var dismiss

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Sound & Vibration") {
                    Toggle(isOn: $settingsStore.settings.soundEnabled) {
                        Label("Sound Effects", systemImage: "speaker.wave.2.fill")
                    }
                    Toggle(isOn: $settingsStore.settings.musicEnabled) {
                        Label("Music", systemImage: "music.note")
                    }
                    Toggle(isOn: $settingsStore.settings.hapticsEnabled) {
                        Label("Vibration", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }

                Section("Help & Privacy") {
                    Link(destination: AppConfig.supportURL) {
                        Label("Support", systemImage: "questionmark.circle.fill")
                    }
                    Link(destination: AppConfig.privacyPolicyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                    if ads.privacyOptionsRequired {
                        Button {
                            ads.presentPrivacyOptions()
                        } label: {
                            Label("Ad Privacy Options", systemImage: "slider.horizontal.3")
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionText).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color(red: 0.85, green: 0.6, blue: 0.1))
    }
}

// MARK: - 设置按钮
struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            AudioManager.shared.play(.buttonTap)
            action()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .overlay(Circle().stroke(Color.arcadeGold.opacity(0.8), lineWidth: 1))
        }
        .accessibilityLabel("Settings")
    }
}
