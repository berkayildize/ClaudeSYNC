import ClaudeSYNCCore
import SwiftUI

struct ProfilesManagerView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var newProfileName: String = "2. Profil"
    @State private var newProfilePath: String = "~/Library/Application Support/Claude-Account2"
    @State private var copyMcpConfig: Bool = true
    @State private var migrateExistingSessions: Bool = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                headerExplanationCard

                // Configured Profiles Grid
                VStack(alignment: .leading, spacing: 8) {
                    Text("YAPILANDIRILMIŞ PROFİLLER")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.7)

                    ForEach(viewModel.settings.allProfiles) { profile in
                        profileRowCard(profile)
                    }
                }

                // Create / Add Secondary Profile Card
                createSecondaryProfileCard
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerExplanationCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Çıkışsız Çift Profil Mimarisi")
                    .font(.system(size: 13, weight: .semibold))
                Text("Her profil Claude Desktop'ı kendi --user-data-dir klasörüyle izole çalıştırır. İki Ultra hesabınız da sürekli giriş yapılı kalır; limit dolunca çıkış yapmadan anında geçebilirsiniz.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: BridgeTheme.cardRadius)
    }

    private func profileRowCard(_ profile: ProfileConfig) -> some View {
        let running = viewModel.runningInstance(for: profile)
        let matchingAccounts = viewModel.accounts.filter {
            $0.profileDataDir.standardizedFileURL.path == profile.expandedURL.standardizedFileURL.path
        }
        let existsOnDisk = FileManager.default.fileExists(atPath: profile.expandedURL.path)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    PulseStatusDot(
                        color: running != nil ? Color(nsColor: .systemGreen) : .secondary.opacity(0.4),
                        size: 6,
                        isPulsing: running != nil
                    )

                    Text(profile.name)
                        .font(.system(size: 13, weight: .semibold))

                    if profile.isDefault {
                        Text("Varsayılan")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.09)))
                            .foregroundStyle(.secondary)
                    }

                    if let proc = running {
                        Text("Çalışıyor · PID \(String(proc.pid))")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(nsColor: .systemGreen).opacity(0.14)))
                            .foregroundStyle(Color(nsColor: .systemGreen))
                    } else {
                        Text(existsOnDisk ? "Kapalı" : "Henüz Oluşturulmadı")
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(profile.dataDirPath)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !matchingAccounts.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(matchingAccounts) { acc in
                            Text("\(acc.displayName) · \(acc.activeSessions.count) aktif oturum")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(running != nil ? "Öne Al" : "Başlat") {
                    viewModel.focusOrLaunchProfile(profile)
                }
                .nativeGlassButton(prominent: running == nil)
                .controlSize(.small)
                .disabled(viewModel.isBusy)

                Button("Yenile") {
                    viewModel.reloadProfile(profile)
                }
                .nativeGlassButton()
                .controlSize(.small)
                .disabled(viewModel.isBusy)
                .help("Profili güvenle kapatıp yeniden açar (kenar çubuğunu yeniler)")

                if !profile.isDefault {
                    Button {
                        viewModel.removeSecondaryProfile(profile)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(nsColor: .systemRed))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                    .help("Listeden kaldır (diskteki profil klasörünüz silinmez)")
                }
            }
        }
        .padding(14)
        .liquidGlassCard(
            cornerRadius: BridgeTheme.cardRadius,
            strokeAccent: running != nil ? Color(nsColor: .systemGreen).opacity(0.24) : nil
        )
    }

    private var createSecondaryProfileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Yeni İzole Profil Oluştur", systemImage: "plus.rectangle.on.rectangle")
                .font(.system(size: 12.5, weight: .semibold))

            HStack(spacing: 8) {
                TextField("Profil adı", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .frame(width: 150)

                TextField("Veri klasörü", text: $newProfilePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }

            HStack(spacing: 16) {
                Toggle("Yerel MCP ayarlarını (claude_desktop_config.json) kopyala", isOn: $copyMcpConfig)
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)

                Spacer()
            }

            HStack(spacing: 16) {
                Toggle("2. hesabın mevcut oturum kartlarını yeni profile taşı", isOn: $migrateExistingSessions)
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)

                Spacer()

                Button {
                    let targetAcc = migrateExistingSessions ? (viewModel.targetAccount ?? viewModel.accounts.last) : nil
                    viewModel.setupAndLaunchSecondaryProfile(
                        name: newProfileName,
                        path: newProfilePath,
                        copyMcpConfig: copyMcpConfig,
                        migrateAccount: targetAcc
                    )
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.app.fill")
                            .font(.system(size: 11))
                        Text("Profili Oluştur ve Başlat")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(BridgeTheme.primaryAccent))
                    .foregroundStyle(.white)
                }
                .buttonStyle(TactileScaleButtonStyle())
                .disabled(viewModel.isBusy)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: BridgeTheme.cardRadius)
    }
}
