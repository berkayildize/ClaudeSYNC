import ClaudeSYNCCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    var isWideLayout: Bool = false

    @State private var draftNicknames: [String: String] = [:]
    @State private var savedNicknameKeys: Set<String> = []
    @State private var newProfileName: String = ""
    @State private var newProfilePath: String = "~/Library/Application Support/Claude-Account2"
    @State private var copyMcpConfig: Bool = true
    @State private var migrateExistingSessions: Bool = true

    private var l10n: L10n { viewModel.l10n }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                languageAndWizardSection
                menuBarControlSection
                nicknamesSection
                if !isWideLayout {
                    dualProfileSection
                }
                transferSafetySection
                systemSection
                aboutSection
            }
            .padding(.horizontal, isWideLayout ? 16 : BridgeTheme.hPad)
            .padding(.vertical, isWideLayout ? 16 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            syncDraftNicknames()
            if newProfileName.isEmpty {
                newProfileName = l10n.t("2. Profil", "Profile 2")
            }
        }
        .onChange(of: viewModel.accounts.count) { _, _ in
            syncDraftNicknames()
        }
    }

    private func syncDraftNicknames() {
        for acc in viewModel.accounts {
            if draftNicknames[acc.accountOrgKey] == nil {
                draftNicknames[acc.accountOrgKey] = viewModel.settings.accountNicknames[acc.accountOrgKey] ?? acc.displayName
            }
        }
    }

    // MARK: - 0. Language & First-Launch Setup Wizard

    private var languageAndWizardSection: some View {
        sectionCard(title: l10n.t("Dil & İlk Kurulum", "Language & Setup"), icon: "globe") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(l10n.t("Uygulama Dili", "App Language"))
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(
                            l10n.t(
                                "Türkçe, İngilizce veya macOS sistem dilini anında seçin.",
                                "Switch instantly between English, Turkish, or macOS System locale."
                            )
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    LiquidGlassSegmentedControl(
                        items: AppLanguage.allCases,
                        selection: Binding(
                            get: { viewModel.settings.language },
                            set: { viewModel.setLanguage($0) }
                        ),
                        title: { l10n.languageName($0) },
                        compact: true
                    )
                    .frame(width: 210)
                }

                Divider().opacity(0.4)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(l10n.t("İlk Kurulum Sihirbazı", "First-Launch Setup Wizard"))
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(
                            l10n.t(
                                "Sistem izinlerini, bildirimleri ve çift profil kurulumunu adım adım yeniden kontrol edin.",
                                "Re-run guided permission checks, notification setup, and dual-profile configuration."
                            )
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(l10n.t("Sihirbazı Aç", "Run Setup Wizard")) {
                        viewModel.reopenOnboarding()
                        viewModel.openMainWindow()
                    }
                    .nativeGlassButton()
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - 1. Menu Bar Toggle & Appearance

    private var menuBarControlSection: some View {
        sectionCard(title: l10n.t("Üst Bar (Menu Bar) Kontrolü", "Menu Bar Control"), icon: "menubar.rectangle") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(l10n.t("Üst Bar Simgesini Göster", "Show Menu Bar Icon"))
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(
                            l10n.t(
                                "Kapatıldığında yalnızca ana uygulama penceresi ve Dock ikonu ile çalışır.",
                                "When disabled, runs purely as a standard macOS app window in your Dock."
                            )
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { viewModel.showMenuBarExtra },
                            set: { viewModel.setShowMenuBarExtra($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if viewModel.showMenuBarExtra {
                    Divider().opacity(0.4)

                    Toggle(
                        l10n.t(
                            "Ana pencere kapatılınca üst barda çalışmaya devam et",
                            "Keep running in the Menu Bar when the main window closes"
                        ),
                        isOn: Binding(
                            get: { viewModel.settings.keepRunningInMenuBarOnClose },
                            set: { val in viewModel.updateSettings { $0.keepRunningInMenuBarOnClose = val } }
                        )
                    )
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(l10n.t("ÜST BAR GÖRÜNÜM STİLİ", "MENU BAR DISPLAY STYLE"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .tracking(0.6)

                        LiquidGlassSegmentedControl(
                            items: MenuBarDisplayMode.allCases,
                            selection: Binding(
                                get: { viewModel.settings.menuBarDisplayMode },
                                set: { val in viewModel.updateSettings { $0.menuBarDisplayMode = val } }
                            ),
                            title: { $0.title(isTurkish: l10n.isTurkish) },
                            compact: true
                        )
                    }
                }
            }
        }
    }

    // MARK: - 2. Account Nicknames

    private var nicknamesSection: some View {
        sectionCard(title: l10n.t("Hesap İsimleri", "Account Nicknames"), icon: "person.2.fill") {
            if viewModel.accounts.isEmpty {
                Text(l10n.t("Algılanmış hesap yok.", "No accounts detected."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.accounts) { acc in
                        let isSaved = savedNicknameKeys.contains(acc.accountOrgKey)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(acc.shortAccountTag)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(l10n.profileDisplayName(acc.profileName, isDefault: acc.isDefaultProfile))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(width: 82, alignment: .leading)

                            TextField(
                                l10n.t("Örn: Ultra 1", "e.g. Ultra 1"),
                                text: Binding(
                                    get: { draftNicknames[acc.accountOrgKey] ?? acc.displayName },
                                    set: { draftNicknames[acc.accountOrgKey] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))

                            Button {
                                let name = draftNicknames[acc.accountOrgKey] ?? ""
                                viewModel.updateNickname(for: acc, newName: name)
                                savedNicknameKeys.insert(acc.accountOrgKey)
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    savedNicknameKeys.remove(acc.accountOrgKey)
                                }
                            } label: {
                                Text(isSaved ? l10n.t("Kaydedildi ✓", "Saved ✓") : l10n.t("Kaydet", "Save"))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(isSaved ? Color(nsColor: .systemGreen) : .primary)
                            }
                            .nativeGlassButton()
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 3. Dual Profile (Compact Popover Only)

    private var dualProfileSection: some View {
        sectionCard(title: l10n.t("Çıkışsız Çift Profil (--user-data-dir)", "Zero-Logout Dual Profile (--user-data-dir)"), icon: "macwindow.on.rectangle") {
            VStack(alignment: .leading, spacing: 9) {
                Text(
                    l10n.t(
                        "Her iki Ultra hesabınızı ayrı Claude Desktop profillerinde kalıcı giriş yapılı tutun — limit dolduğunda çıkış/giriş yapmadan doğrudan diğer pencereye geçin.",
                        "Keep both accounts signed in simultaneously using isolated profiles — switch windows directly without logging out."
                    )
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if !viewModel.settings.secondaryProfiles.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(viewModel.settings.secondaryProfiles) { profile in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1.5) {
                                    Text(l10n.profileDisplayName(profile.name, isDefault: profile.isDefault))
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text(profile.dataDirPath)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button(l10n.t("Aç / Öne Al", "Open / Focus")) {
                                    viewModel.focusOrLaunchProfile(profile)
                                }
                                .nativeGlassButton()
                                .controlSize(.small)

                                Button {
                                    viewModel.removeSecondaryProfile(profile)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(nsColor: .systemRed))
                                }
                                .buttonStyle(.plain)
                                .help(l10n.t("Listeden kaldır (klasörünüz silinmez)", "Remove from list (disk folder stays intact)"))
                            }
                            .padding(8)
                            .liquidGlassCard(cornerRadius: 10)
                        }
                    }
                }

                Divider().opacity(0.45)

                VStack(alignment: .leading, spacing: 7) {
                    Text(l10n.t("Yeni Profil Oluştur / Başlat", "Create & Launch Profile"))
                        .font(.system(size: 11, weight: .semibold))

                    HStack(spacing: 6) {
                        TextField(l10n.t("Profil adı", "Profile name"), text: $newProfileName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .frame(width: 115)

                        TextField(l10n.t("Veri klasörü", "Data directory"), text: $newProfilePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10.5, design: .monospaced))
                    }

                    Toggle(
                        l10n.t("Yerel MCP ayarlarını (claude_desktop_config.json) kopyala", "Copy local MCP config (claude_desktop_config.json)"),
                        isOn: $copyMcpConfig
                    )
                    .font(.system(size: 10.5))
                    .toggleStyle(.checkbox)

                    Toggle(
                        l10n.t("2. hesabın mevcut oturum kartlarını yeni profile taşı", "Migrate 2nd account session cards to new profile"),
                        isOn: $migrateExistingSessions
                    )
                    .font(.system(size: 10.5))
                    .toggleStyle(.checkbox)

                    HStack {
                        Spacer()
                        Button {
                            let targetAcc = migrateExistingSessions ? (viewModel.targetAccount ?? viewModel.accounts.last) : nil
                            viewModel.setupAndLaunchSecondaryProfile(
                                name: newProfileName,
                                path: newProfilePath,
                                copyMcpConfig: copyMcpConfig,
                                migrateAccount: targetAcc
                            )
                            viewModel.activeTab = .sessions
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.app.fill")
                                    .font(.system(size: 11))
                                Text(l10n.t("2. Profili Oluştur ve Başlat", "Create & Launch Profile 2"))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(BridgeTheme.primaryAccent))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(TactileScaleButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - 4. Auto Card Sync & Safety

    private var transferSafetySection: some View {
        sectionCard(title: l10n.t("Otomatik Eşitleme & Güvenlik", "Auto Sync & Safety"), icon: "arrow.triangle.2.circlepath.circle.fill") {
            VStack(alignment: .leading, spacing: 7) {
                Toggle(
                    l10n.t("Tek Claude penceresinde otonom geçiş (2. uygulama açma)", "Single Claude window switching (never open a 2nd app)"),
                    isOn: Binding(
                        get: { viewModel.settings.singleWindowMode },
                        set: { val in viewModel.updateSettings { $0.singleWindowMode = val } }
                    )
                )
                .font(.system(size: 11, weight: .medium))

                Text(
                    l10n.t(
                        "Açıkken hesap değiştirildiğinde mevcut Claude güvenle kapanıp diğer hesap açılır. Dock'ta tek Claude kalır ve Gmail/Google ile ilk giriş sorunsuz çalışır.",
                        "When ON, switching closes the current Claude window and reopens directly in the other account — keeping 1 Dock icon and ensuring Google/Gmail OAuth works cleanly."
                    )
                )
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 3)

                Toggle(
                    l10n.t("Ortak oturum kartlarını arka planda otomatik eşitle", "Automatically mirror shared session cards in background"),
                    isOn: Binding(
                        get: { viewModel.settings.autoSyncSharedCards },
                        set: { val in viewModel.updateSettings { $0.autoSyncSharedCards = val } }
                    )
                )
                .font(.system(size: 11, weight: .medium))

                Text(
                    l10n.t(
                        "İki hesapta da bulunan bir oturumda çalıştığınızda diğer hesabın kartı (tur sayısı, başlık, sıra) arka planda sessizce güncellenir.",
                        "When you continue a shared session in Account B, turn counts, title, and ordering stay synced back to Account A."
                    )
                )
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 3)

                Toggle(
                    l10n.t("Bulut senkronizasyon ID'lerini (bridgeSessionIds) temizle", "Strip cloud bridgeSessionIds on cross-account transfer"),
                    isOn: Binding(
                        get: { viewModel.settings.clearBridgeIds },
                        set: { val in viewModel.updateSettings { $0.clearBridgeIds = val } }
                    )
                )
                .font(.system(size: 11))

                Toggle(
                    l10n.t("Hesaba bağlı uzak MCP connector kayıtlarını sıfırla", "Clear account-bound remote MCP connectors"),
                    isOn: Binding(
                        get: { viewModel.settings.clearRemoteMcp },
                        set: { val in viewModel.updateSettings { $0.clearRemoteMcp = val } }
                    )
                )
                .font(.system(size: 11))

                Toggle(
                    l10n.t("Aktarılan oturumu hedefte en üste taşı", "Pin transferred session to top of target sidebar"),
                    isOn: Binding(
                        get: { viewModel.settings.bumpLastFocusedAt },
                        set: { val in viewModel.updateSettings { $0.bumpLastFocusedAt = val } }
                    )
                )
                .font(.system(size: 11))

                Toggle(
                    l10n.t("Çift profilde worktree kayıtlarını (git-worktrees.json) birleştir", "Merge git-worktrees.json across isolated profiles"),
                    isOn: Binding(
                        get: { viewModel.settings.mergeWorktreeIfNeeded },
                        set: { val in viewModel.updateSettings { $0.mergeWorktreeIfNeeded = val } }
                    )
                )
                .font(.system(size: 11))

                HStack {
                    Text(l10n.t("Her aktarımdan önce hedef dosyalar otomatik yedeklenir.", "Automatic timestamped backups are created before every write."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(l10n.t("Yedekleri Aç", "Open Backups")) {
                        viewModel.openBackupsFolder()
                    }
                    .nativeGlassButton()
                    .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - 5. System

    private var systemSection: some View {
        sectionCard(title: l10n.t("Sistem", "System"), icon: "macbook") {
            Toggle(
                l10n.t("Mac açılışında otomatik başlat", "Launch automatically at login"),
                isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.toggleLaunchAtLogin($0) }
                )
            )
            .font(.system(size: 11))
        }
    }

    // MARK: - 6. About & Open Source Privacy

    private var appVersionString: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.3"
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ClaudeSyncHeaderIcon(size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.t("ClaudeSYNC · Açık Kaynak (MIT)", "ClaudeSYNC · Open Source (MIT)"))
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(
                        l10n.t(
                            "%100 Yerel · Sıfır Telemetri · Çerez/Token Okumaz",
                            "100% Local · Zero Telemetry · Never Reads Cookies or Tokens"
                        )
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let url = URL(string: "https://github.com/berkayildize/ClaudeSYNC/releases") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("v\(appVersionString) · \(l10n.t("Sürüm Notları", "Release Notes"))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }

            Text(
                l10n.t(
                    "• Tüm sohbet kayıtları (~/.claude/projects/*.jsonl) iki hesap arasında zaten ortaktır.\n• Farklı hesapta devam ederken eski hesabın imzalı thinking blokları güvenlik gereği atlanır; tüm mesajlar, kodlar ve araç çıktıları tam korunur.\n• Aynı oturuma iki farklı pencerede eşzamanlı mesaj göndermeyin.",
                    "• Conversation transcripts (~/.claude/projects/*.jsonl) are already shared locally across accounts.\n• When resuming under another org, prior signed thinking blocks are safely skipped while all messages, code edits, and tool outputs stay intact.\n• Avoid sending concurrent prompts to the same session from two open windows simultaneously."
                )
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 12)
    }

    // MARK: - Helper

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: BridgeTheme.cardRadius)
    }
}
