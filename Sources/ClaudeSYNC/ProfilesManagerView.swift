import ClaudeSYNCCore
import SwiftUI

struct ProfilesManagerView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var newProfileName: String = ""
    @State private var newProfilePath: String = "~/Library/Application Support/Claude-Account2"
    @State private var copyMcpConfig: Bool = true
    @State private var migrateExistingSessions: Bool = true

    private var l10n: L10n { viewModel.l10n }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                headerExplanationCard

                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("YAPILANDIRILMIŞ PROFİLLER", "CONFIGURED PROFILES"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.7)

                    ForEach(viewModel.settings.allProfiles) { profile in
                        profileRowCard(profile)
                    }
                }

                createSecondaryProfileCard
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if newProfileName.isEmpty {
                newProfileName = l10n.t("2. Profil", "Profile 2")
            }
        }
        .onChange(of: viewModel.settings.language) { _, _ in
            if newProfileName == "2. Profil" || newProfileName == "Profile 2" {
                newProfileName = l10n.t("2. Profil", "Profile 2")
            }
        }
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
                Text(l10n.t("Çıkışsız Çift Profil Mimarisi", "Zero-Logout Dual Profile Architecture"))
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    l10n.t(
                        "Her profil Claude Desktop'ı kendi --user-data-dir klasörüyle izole çalıştırır. İki Ultra hesabınız da sürekli giriş yapılı kalır; limit dolunca çıkış yapmadan anında geçebilirsiniz.",
                        "Each profile runs Claude Desktop isolated with its own --user-data-dir folder. Stay permanently signed into both accounts and switch instantly when limits hit."
                    )
                )
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

                    Text(l10n.profileDisplayName(profile.name, isDefault: profile.isDefault))
                        .font(.system(size: 13, weight: .semibold))

                    if profile.isDefault {
                        Text(l10n.t("Varsayılan", "Default"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.09)))
                            .foregroundStyle(.secondary)
                    }

                    if let proc = running {
                        Text(l10n.t("Çalışıyor · PID \(String(proc.pid))", "Running · PID \(String(proc.pid))"))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(nsColor: .systemGreen).opacity(0.14)))
                            .foregroundStyle(Color(nsColor: .systemGreen))
                    } else {
                        Text(
                            existsOnDisk
                                ? l10n.t("Kapalı", "Stopped")
                                : l10n.t("Henüz Oluşturulmadı", "Not Created Yet")
                        )
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
                            Text(
                                l10n.t(
                                    "\(acc.displayName) · \(acc.activeSessions.count) aktif oturum",
                                    "\(acc.displayName) · \(acc.activeSessions.count) active sessions"
                                )
                            )
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(running != nil ? l10n.t("Öne Al", "Focus") : l10n.t("Başlat", "Launch")) {
                    viewModel.focusOrLaunchProfile(profile)
                }
                .nativeGlassButton(prominent: running == nil)
                .controlSize(.small)
                .disabled(viewModel.isBusy)

                Button(l10n.t("Yenile", "Reload")) {
                    viewModel.reloadProfile(profile)
                }
                .nativeGlassButton()
                .controlSize(.small)
                .disabled(viewModel.isBusy)
                .help(
                    l10n.t(
                        "Profili güvenle kapatıp yeniden açar (kenar çubuğunu yeniler)",
                        "Gracefully restarts this profile to refresh the sidebar"
                    )
                )

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
                    .help(
                        l10n.t(
                            "Listeden kaldır (diskteki profil klasörünüz silinmez)",
                            "Remove from list (your folder on disk is kept intact)"
                        )
                    )
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
            Label(l10n.t("Yeni İzole Profil Oluştur", "Create New Isolated Profile"), systemImage: "plus.rectangle.on.rectangle")
                .font(.system(size: 12.5, weight: .semibold))

            HStack(spacing: 8) {
                TextField(l10n.t("Profil adı", "Profile name"), text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .frame(width: 150)

                TextField(l10n.t("Veri klasörü", "Data directory"), text: $newProfilePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }

            HStack(spacing: 16) {
                Toggle(
                    l10n.t(
                        "Yerel MCP ayarlarını (claude_desktop_config.json) kopyala",
                        "Copy local MCP config (claude_desktop_config.json)"
                    ),
                    isOn: $copyMcpConfig
                )
                .font(.system(size: 11))
                .toggleStyle(.checkbox)

                Spacer()
            }

            HStack(spacing: 16) {
                Toggle(
                    l10n.t(
                        "2. hesabın mevcut oturum kartlarını yeni profile taşı",
                        "Migrate existing 2nd account session cards to the new profile"
                    ),
                    isOn: $migrateExistingSessions
                )
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
                        Text(l10n.t("Profili Oluştur ve Başlat", "Create & Launch Profile"))
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
