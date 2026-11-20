import ClaudeSYNCCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    var isWideLayout: Bool = false

    @State private var draftNicknames: [String: String] = [:]
    @State private var savedNicknameKeys: Set<String> = []
    @State private var newProfileName: String = "2. Profil"
    @State private var newProfilePath: String = "~/Library/Application Support/Claude-Account2"
    @State private var copyMcpConfig: Bool = true
    @State private var migrateExistingSessions: Bool = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
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

    // MARK: - 1. Menu Bar Toggle & Appearance

    private var menuBarControlSection: some View {
        sectionCard(title: "Üst Bar (Menu Bar) Kontrolü", icon: "menubar.rectangle") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text("Üst Bar Simgesini Göster")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("Kapatıldığında yalnızca ana uygulama penceresi ve Dock ikonu ile çalışır.")
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
                        "Ana pencere kapatılınca üst barda çalışmaya devam et",
                        isOn: Binding(
                            get: { viewModel.settings.keepRunningInMenuBarOnClose },
                            set: { val in viewModel.updateSettings { $0.keepRunningInMenuBarOnClose = val } }
                        )
                    )
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("ÜST BAR GÖRÜNÜM STİLİ")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .tracking(0.6)

                        LiquidGlassSegmentedControl(
                            items: MenuBarDisplayMode.allCases,
                            selection: Binding(
                                get: { viewModel.settings.menuBarDisplayMode },
                                set: { val in viewModel.updateSettings { $0.menuBarDisplayMode = val } }
                            ),
                            title: { mode in
                                switch mode {
                                case .iconAndBothAccounts: return "İki Hesap Bar"
                                case .iconAndActiveUsage: return "Aktif 5s/7g"
                                case .iconOnly: return "Sadece İkon"
                                }
                            },
                            compact: true
                        )
                    }
                }
            }
        }
    }

    // MARK: - 2. Account Nicknames

    private var nicknamesSection: some View {
        sectionCard(title: "Hesap İsimleri", icon: "person.2.fill") {
            if viewModel.accounts.isEmpty {
                Text("Algılanmış hesap yok.")
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
                                Text(acc.profileName)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(width: 74, alignment: .leading)

                            TextField(
                                "Örn: Ultra 1",
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
                                Text(isSaved ? "Kaydedildi ✓" : "Kaydet")
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

    // MARK: - 3. Dual Profile (Compact Popover Only — Full Window has Dedicated Profiles Tab)

    private var dualProfileSection: some View {
        sectionCard(title: "Çıkışsız Çift Profil (--user-data-dir)", icon: "macwindow.on.rectangle") {
            VStack(alignment: .leading, spacing: 9) {
                Text("Her iki Ultra hesabınızı ayrı Claude Desktop profillerinde kalıcı giriş yapılı tutun — limit dolduğunda çıkış/giriş yapmadan doğrudan diğer pencereye geçin.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !viewModel.settings.secondaryProfiles.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(viewModel.settings.secondaryProfiles) { profile in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1.5) {
                                    Text(profile.name)
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text(profile.dataDirPath)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Aç / Öne Al") {
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
                                .help("Listeden kaldır (klasörünüz silinmez)")
                            }
                            .padding(8)
                            .liquidGlassCard(cornerRadius: 10)
                        }
                    }
                }

                Divider().opacity(0.45)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Yeni Profil Oluştur / Başlat")
                        .font(.system(size: 11, weight: .semibold))

                    HStack(spacing: 6) {
                        TextField("Profil adı", text: $newProfileName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .frame(width: 115)

                        TextField("Veri klasörü", text: $newProfilePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10.5, design: .monospaced))
                    }

                    Toggle("Yerel MCP ayarlarını (claude_desktop_config.json) kopyala", isOn: $copyMcpConfig)
                        .font(.system(size: 10.5))
                        .toggleStyle(.checkbox)

                    Toggle("2. hesabın mevcut oturum kartlarını yeni profile taşı", isOn: $migrateExistingSessions)
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
                                Text("2. Profili Oluştur ve Başlat")
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
        sectionCard(title: "Otomatik Eşitleme & Güvenlik", icon: "arrow.triangle.2.circlepath.circle.fill") {
            VStack(alignment: .leading, spacing: 7) {
                Toggle(
                    "Ortak oturum kartlarını arka planda otomatik eşitle",
                    isOn: Binding(
                        get: { viewModel.settings.autoSyncSharedCards },
                        set: { val in viewModel.updateSettings { $0.autoSyncSharedCards = val } }
                    )
                )
                .font(.system(size: 11, weight: .medium))

                Text("İki hesapta da bulunan bir oturumda çalıştığınızda diğer hesabın kartı (tur sayısı, başlık, sıra) arka planda sessizce güncellenir.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 3)

                Toggle(
                    "Bulut senkronizasyon ID'lerini (bridgeSessionIds) temizle",
                    isOn: Binding(
                        get: { viewModel.settings.clearBridgeIds },
                        set: { val in viewModel.updateSettings { $0.clearBridgeIds = val } }
                    )
                )
                .font(.system(size: 11))

                Toggle(
                    "Hesaba bağlı uzak MCP connector kayıtlarını sıfırla",
                    isOn: Binding(
                        get: { viewModel.settings.clearRemoteMcp },
                        set: { val in viewModel.updateSettings { $0.clearRemoteMcp = val } }
                    )
                )
                .font(.system(size: 11))

                Toggle(
                    "Aktarılan oturumu hedefte en üste taşı",
                    isOn: Binding(
                        get: { viewModel.settings.bumpLastFocusedAt },
                        set: { val in viewModel.updateSettings { $0.bumpLastFocusedAt = val } }
                    )
                )
                .font(.system(size: 11))

                Toggle(
                    "Çift profilde worktree kayıtlarını (git-worktrees.json) birleştir",
                    isOn: Binding(
                        get: { viewModel.settings.mergeWorktreeIfNeeded },
                        set: { val in viewModel.updateSettings { $0.mergeWorktreeIfNeeded = val } }
                    )
                )
                .font(.system(size: 11))

                HStack {
                    Text("Her aktarımdan önce hedef dosyalar otomatik yedeklenir.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Yedekleri Aç") {
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
        sectionCard(title: "Sistem", icon: "macbook") {
            Toggle(
                "Mac açılışında otomatik başlat",
                isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.toggleLaunchAtLogin($0) }
                )
            )
            .font(.system(size: 11))
        }
    }

    // MARK: - 6. About & Open Source Privacy

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ClaudeSyncHeaderIcon(size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ClaudeSYNC · Açık Kaynak (MIT)")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("%100 Yerel · Sıfır Telemetri · Çerez/Token Okumaz")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("v1.0.0")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text("• Tüm sohbet kayıtları (~/.claude/projects/*.jsonl) iki hesap arasında zaten ortaktır.\n• Farklı hesapta devam ederken eski hesabın imzalı thinking blokları güvenlik gereği atlanır; tüm mesajlar, kodlar ve araç çıktıları tam korunur.\n• Aynı oturuma iki farklı pencerede eşzamanlı mesaj göndermeyin.")
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
