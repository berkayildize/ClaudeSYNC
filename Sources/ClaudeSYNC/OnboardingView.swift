import AppKit
import ClaudeSYNCCore
import SwiftUI

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case permissions = 1
    case dualProfile = 2
    case preferences = 3

    var id: Int { rawValue }

    func title(_ l10n: L10n) -> String {
        switch self {
        case .welcome: return l10n.t("Dil & Başlangıç", "Language & Start")
        case .permissions: return l10n.t("Sistem & İzinler", "System & Permissions")
        case .dualProfile: return l10n.t("Çift Profil", "Dual Profile")
        case .preferences: return l10n.t("Üst Bar & Otomasyon", "Menu Bar & Sync")
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "globe"
        case .permissions: return "checkmark.shield.fill"
        case .dualProfile: return "macwindow.on.rectangle"
        case .preferences: return "menubar.rectangle"
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var viewModel: AppViewModel
    var useNativeGlassBackdrop: Bool = true
    var includeTrafficLightInset: Bool = true
    @Environment(\.colorScheme) private var scheme

    @State private var newProfileName: String = ""
    @State private var newProfilePath: String = "~/Library/Application Support/Claude-Account2"
    @State private var copyMcpConfig: Bool = true
    @State private var migrateExistingSessions: Bool = true
    @State private var createdProfileInWizard: Bool = false

    private var l10n: L10n { viewModel.l10n }
    private var step: OnboardingStep { viewModel.onboardingStep }

    var body: some View {
        let isDark = (scheme == .dark)

        VStack(spacing: 0) {
            // Top Stepper Bar
            stepperHeader
                .padding(.top, includeTrafficLightInset ? 32 : 18)
                .padding(.bottom, 14)
                .padding(.horizontal, 28)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
                        .frame(height: 0.75)
                }

            // Centered Step Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    switch step {
                    case .welcome:
                        welcomeStepView
                    case .permissions:
                        permissionsStepView
                    case .dualProfile:
                        dualProfileStepView
                    case .preferences:
                        preferencesStepView
                    }
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom Action Bar
            footerBar
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.025))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
                        .frame(height: 0.75)
                }
        }
        .frame(minWidth: 800, idealWidth: 920, minHeight: 580, idealHeight: 650)
        .background {
            if useNativeGlassBackdrop {
                MacOSGlassBackdrop(material: .underWindowBackground, blendingMode: .behindWindow)
            }
        }
        .onAppear {
            if newProfileName.isEmpty {
                newProfileName = l10n.t("2. Profil", "Profile 2")
            }
            viewModel.refreshSetupDiagnostics()
        }
        .onChange(of: viewModel.settings.language) { _, _ in
            if newProfileName == "2. Profil" || newProfileName == "Profile 2" {
                newProfileName = l10n.t("2. Profil", "Profile 2")
            }
        }
    }

    // MARK: - Top Symmetric Stepper

    private var stepperHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ClaudeSyncHeaderIcon(size: 26)
                Text("ClaudeSYNC")
                    .font(.system(size: 13.5, weight: .bold))
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases) { item in
                    let isCurrent = (item == step)
                    let isCompleted = item.rawValue < step.rawValue

                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            viewModel.onboardingStep = item
                        }
                    } label: {
                        HStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(
                                        isCompleted
                                            ? Color(nsColor: .systemGreen)
                                            : (isCurrent ? BridgeTheme.primaryAccent : Color.primary.opacity(0.12))
                                    )
                                    .frame(width: 18, height: 18)

                                if isCompleted {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                } else {
                                    Text("\(item.rawValue + 1)")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(isCurrent ? .white : .secondary)
                                }
                            }

                            Text(item.title(l10n))
                                .font(.system(size: 11, weight: isCurrent ? .semibold : .medium))
                                .foregroundStyle(isCurrent ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(isCurrent ? Color.primary.opacity(0.08) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Step 1: Welcome & Language Selection

    private var welcomeStepView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                ClaudeSyncHeaderIcon(size: 62)

                Text(l10n.t("ClaudeSYNC'e Hoş Geldiniz", "Welcome to ClaudeSYNC"))
                    .font(.system(size: 24, weight: .bold))

                Text(
                    l10n.t(
                        "Claude Code Desktop hesaplarınız arasında çıkış yapmadan geçiş yapın, 5s/7g limitlerini üst barda izleyin ve oturum bağlamınızı asla kaybetmeyin.",
                        "Switch Claude Code Desktop accounts without logging out, track 5h/7d limits in the menu bar, and never lose your active session context."
                    )
                )
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 540)
            }

            // Language Picker
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.t("UYGULAMA DİLİ / APP LANGUAGE", "APP LANGUAGE / UYGULAMA DİLİ"))
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)

                HStack(spacing: 10) {
                    languageCard(
                        lang: .system,
                        title: l10n.t("Sistem (Otomatik)", "System (Auto)"),
                        subtitle: l10n.t("macOS diline uyar", "Matches macOS locale"),
                        badge: "AUTO"
                    )
                    languageCard(
                        lang: .turkish,
                        title: "Türkçe",
                        subtitle: "Tam Türkçe arayüz",
                        badge: "TR"
                    )
                    languageCard(
                        lang: .english,
                        title: "English",
                        subtitle: "Full English interface",
                        badge: "EN"
                    )
                }
            }

            // 3 Symmetric Core Pillars
            HStack(spacing: 10) {
                pillarCard(
                    icon: "arrow.left.arrow.right.circle.fill",
                    iconColor: BridgeTheme.primaryAccent,
                    title: l10n.t("Oturum Devamlılığı", "Session Continuity"),
                    desc: l10n.t(
                        "Yerel .jsonl geçmişini koruyarak kartları hesaplar arasında güvenle aktarır.",
                        "Transfers session cards safely across accounts while keeping full local .jsonl history."
                    )
                )
                pillarCard(
                    icon: "macwindow.on.rectangle",
                    iconColor: Color(nsColor: .systemGreen),
                    title: l10n.t("Çıkışsız Çift Profil", "Zero-Logout Profiles"),
                    desc: l10n.t(
                        "İki hesap aynı anda giriş yapılı kalır; 429 limitinde otomatik geçiş yapar.",
                        "Keep both accounts signed in simultaneously with automatic failover on 429."
                    )
                )
                pillarCard(
                    icon: "lock.shield.fill",
                    iconColor: Color(nsColor: .systemOrange),
                    title: l10n.t("%100 Yerel & Açık Kaynak", "100% Local & Open Source"),
                    desc: l10n.t(
                        "Sıfır ağ isteği. Çerez, Keychain veya OAuth token'larına asla dokunmaz.",
                        "Zero network calls. Never reads Cookies, Keychain, or OAuth tokens."
                    )
                )
            }
        }
    }

    private func languageCard(lang: AppLanguage, title: String, subtitle: String, badge: String) -> some View {
        let isSelected = (viewModel.settings.language == lang)
        return Button {
            viewModel.setLanguage(lang)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isSelected ? BridgeTheme.primaryAccent : Color.primary.opacity(0.09))
                        )
                        .foregroundStyle(isSelected ? .white : .secondary)

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? BridgeTheme.primaryAccent : .secondary.opacity(0.35))
                }

                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassCard(
                cornerRadius: 12,
                tint: isSelected ? BridgeTheme.primaryAccent : nil,
                strokeAccent: isSelected ? BridgeTheme.primaryAccent.opacity(0.55) : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pillarCard(icon: String, iconColor: Color, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(desc)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: 12)
    }

    // MARK: - Step 2: System Diagnostics & macOS Permissions

    private var permissionsStepView: some View {
        let diag = viewModel.setupDiagnostics

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("Sistem & İzin Kontrolü", "System & Permissions Check"))
                    .font(.system(size: 20, weight: .bold))
                Text(
                    l10n.t(
                        "ClaudeSYNC'in yerel Claude Desktop verilerinizi okuyabilmesi ve limit bildirimlerini gösterebilmesi için ortamınızı doğruluyoruz.",
                        "Let's verify your local Claude Desktop environment and enable optional notification permissions for automatic failover alerts."
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 9) {
                // 1. Claude Desktop App
                diagnosticRow(
                    icon: "app.badge.checkmark",
                    title: "Claude Desktop",
                    subtitle: "/Applications/Claude.app",
                    isReady: diag.claudeAppInstalled,
                    statusText: diag.claudeAppInstalled
                        ? l10n.t("Yüklü ✓", "Installed ✓")
                        : l10n.t("Bulunamadı", "Not Found")
                ) {
                    if !diag.claudeAppInstalled {
                        Button(l10n.t("İndir", "Download")) {
                            if let url = URL(string: "https://claude.ai/download") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .nativeGlassButton()
                        .controlSize(.small)
                    }
                }

                // 2. Local Session & Transcript Folder Access
                let storageReady = diag.claudeDataDirAccessible
                diagnosticRow(
                    icon: "folder.badge.gearshape",
                    title: l10n.t("Yerel Oturum Dizini Erişimi", "Local Session Storage Access"),
                    subtitle: diag.claudeProjectsAccessible
                        ? "~/Library/Application Support/Claude · ~/.claude/projects"
                        : "~/Library/Application Support/Claude",
                    isReady: storageReady,
                    statusText: storageReady
                        ? l10n.t(
                            "Erişilebilir (\(diag.detectedAccountCount) hesap)",
                            "Accessible (\(diag.detectedAccountCount) accounts)"
                        )
                        : l10n.t("Claude Desktop henüz açılmadı", "Open Claude Desktop once")
                ) {
                    Button(l10n.t("Tekrar Kontrol Et", "Re-check")) {
                        viewModel.refreshSetupDiagnostics()
                        viewModel.refresh(userInitiated: true)
                    }
                    .nativeGlassButton()
                    .controlSize(.small)
                }

                // 3. macOS Notifications Permission
                let notifGranted = (diag.notificationStatus == .authorized)
                diagnosticRow(
                    icon: "bell.badge.fill",
                    title: l10n.t("macOS Bildirim İzni", "macOS Notification Permission"),
                    subtitle: l10n.t(
                        "429 limiti dolduğunda ve otomatik hesap geçişi yapıldığında anlık uyarı gösterir.",
                        "Shows instant alerts when a 429 rate limit hits and auto-failover completes."
                    ),
                    isReady: notifGranted,
                    statusText: notificationStatusLabel(diag.notificationStatus)
                ) {
                    switch diag.notificationStatus {
                    case .authorized:
                        EmptyView()
                    case .notDetermined:
                        Button(l10n.t("İzin Ver", "Allow")) {
                            viewModel.requestNotificationsFromSetup()
                        }
                        .nativeGlassButton(prominent: true)
                        .controlSize(.small)
                    case .denied:
                        Button(l10n.t("Sistem Ayarları", "Open Settings")) {
                            NotificationHelper.shared.openSystemNotificationSettings()
                        }
                        .nativeGlassButton()
                        .controlSize(.small)
                    case .unavailable:
                        EmptyView()
                    }
                }

                // 4. Launch at Login (Optional)
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 34, height: 34)
                        Image(systemName: "power.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("Mac Açılışında Otomatik Başlat", "Launch Automatically at Login"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(
                            l10n.t(
                                "İsteğe bağlı: Limit barları ve otomatik geçiş arka planda her zaman hazır kalır.",
                                "Optional: Keeps menu bar limit gauges and auto-failover ready after reboot."
                            )
                        )
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle(
                        "",
                        isOn: Binding(
                            get: { viewModel.launchAtLogin },
                            set: { viewModel.toggleLaunchAtLogin($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(12)
                .liquidGlassCard(cornerRadius: 12)
            }

            // Transparent Zero-Extra-Permissions Guarantee
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: .systemGreen))
                Text(
                    l10n.t(
                        "Erişilebilirlik (Accessibility), Ekran Kaydı veya Keychain izni gerekmez. ClaudeSYNC yalnızca kendi yerel Claude klasörünüzdeki JSON oturum kartlarıyla çalışır.",
                        "No Accessibility, Screen Recording, or Keychain permissions needed. ClaudeSYNC strictly reads and writes local session JSON cards on your Mac."
                    )
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassCard(
                cornerRadius: 11,
                tint: Color(nsColor: .systemGreen),
                strokeAccent: Color(nsColor: .systemGreen).opacity(0.28)
            )
        }
    }

    private func notificationStatusLabel(_ state: NotificationPermissionState) -> String {
        switch state {
        case .authorized: return l10n.t("İzin Verildi ✓", "Granted ✓")
        case .notDetermined: return l10n.t("İzin Bekliyor", "Not Requested")
        case .denied: return l10n.t("Ayarlarda Kapalı", "Disabled")
        case .unavailable: return l10n.t("Paket Modunda Aktif", "Active in .app")
        }
    }

    private func diagnosticRow<Action: View>(
        icon: String,
        title: String,
        subtitle: String,
        isReady: Bool,
        statusText: String,
        @ViewBuilder trailing: () -> Action
    ) -> some View {
        let statusColor = isReady ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(statusColor.opacity(0.13))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(statusText)
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(statusColor.opacity(0.14)))
                        .foregroundStyle(statusColor)
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing()
        }
        .padding(12)
        .liquidGlassCard(
            cornerRadius: 12,
            strokeAccent: isReady ? Color(nsColor: .systemGreen).opacity(0.22) : nil
        )
    }

    // MARK: - Step 3: Zero-Logout Dual Profile Setup

    private var dualProfileStepView: some View {
        let hasSecondary = !viewModel.settings.secondaryProfiles.isEmpty || createdProfileInWizard

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("Çıkışsız Çift Profil Kurulumu", "Zero-Logout Dual Profile Setup"))
                    .font(.system(size: 20, weight: .bold))
                Text(
                    l10n.t(
                        "2. Claude hesabınız için izole bir --user-data-dir profili oluşturun. İki hesap aynı anda giriş yapılı kalır; limit dolduğunda çıkış/giriş yapmadan tek tıkla geçersiniz.",
                        "Create an isolated --user-data-dir profile for your second Claude account. Both accounts stay permanently logged in for instant switching when limits hit."
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            // Symmetric Visual: Profile 1 ⇄ Profile 2
            HStack(spacing: 12) {
                profileSummaryTile(
                    tag: l10n.t("1. PROFİL · VARSAYILAN", "PROFILE 1 · DEFAULT"),
                    title: l10n.t("Ana Profil", "Primary Profile"),
                    path: "~/Library/Application Support/Claude",
                    accent: Color(nsColor: .systemGreen),
                    status: l10n.t("Hazır ✓", "Ready ✓")
                )

                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)

                profileSummaryTile(
                    tag: l10n.t("2. PROFİL · İZOLE", "PROFILE 2 · ISOLATED"),
                    title: viewModel.settings.secondaryProfiles.first.map {
                        l10n.profileDisplayName($0.name, isDefault: false)
                    } ?? (newProfileName.isEmpty ? l10n.t("2. Profil", "Profile 2") : newProfileName),
                    path: viewModel.settings.secondaryProfiles.first?.dataDirPath ?? newProfilePath,
                    accent: Color(nsColor: .systemBlue),
                    status: hasSecondary
                        ? l10n.t("Yapılandırıldı ✓", "Configured ✓")
                        : l10n.t("İsteğe Bağlı", "Optional")
                )
            }

            if hasSecondary {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("İkinci izole profil hazır!", "Secondary isolated profile is ready!"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(
                            l10n.t(
                                "Açılan pencerede 2. hesabınızla bir kez giriş yapmanız yeterli. İstediğiniz zaman Profiller sekmesinden yönetebilirsiniz.",
                                "Sign in once with your second account in the launched window. You can manage or add more profiles anytime in the Profiles tab."
                            )
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let sec = viewModel.settings.secondaryProfiles.first {
                        Button(l10n.t("2. Profili Aç", "Open Profile 2")) {
                            viewModel.focusOrLaunchProfile(sec)
                        }
                        .nativeGlassButton()
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .liquidGlassCard(
                    cornerRadius: 12,
                    tint: Color(nsColor: .systemGreen),
                    strokeAccent: Color(nsColor: .systemGreen).opacity(0.30)
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField(l10n.t("Profil adı", "Profile name"), text: $newProfileName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                            .frame(width: 155)

                        TextField(l10n.t("Veri klasörü", "Data directory"), text: $newProfilePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }

                    Toggle(
                        l10n.t(
                            "Yerel MCP ayarlarını (claude_desktop_config.json) kopyala",
                            "Copy local MCP config (claude_desktop_config.json)"
                        ),
                        isOn: $copyMcpConfig
                    )
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)

                    Toggle(
                        l10n.t(
                            "2. hesabın mevcut oturum kartlarını yeni profile taşı",
                            "Migrate existing 2nd account session cards into the new profile"
                        ),
                        isOn: $migrateExistingSessions
                    )
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)

                    HStack {
                        Text(
                            l10n.t(
                                "İsterseniz bu adımı atlayıp daha sonra Profiller sekmesinden kurabilirsiniz.",
                                "You can also skip this step and set it up later in the Profiles tab."
                            )
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                        Spacer()

                        Button {
                            let targetAcc = migrateExistingSessions ? (viewModel.targetAccount ?? viewModel.accounts.last) : nil
                            viewModel.setupAndLaunchSecondaryProfile(
                                name: newProfileName,
                                path: newProfilePath,
                                copyMcpConfig: copyMcpConfig,
                                migrateAccount: targetAcc
                            )
                            createdProfileInWizard = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.app.fill")
                                    .font(.system(size: 11))
                                Text(l10n.t("2. Profili Oluştur ve Başlat", "Create & Launch Profile 2"))
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(BridgeTheme.primaryAccent))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(TactileScaleButtonStyle())
                    }
                    .padding(.top, 2)
                }
                .padding(14)
                .liquidGlassCard(cornerRadius: 12)
            }
        }
    }

    private func profileSummaryTile(tag: String, title: String, path: String, accent: Color, status: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tag)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.7)
                Spacer()
                Text(status)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(title)
                .font(.system(size: 13.5, weight: .bold))
            Text(path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 12, strokeAccent: accent.opacity(0.28))
    }

    // MARK: - Step 4: Menu Bar & Automation Preferences

    private var preferencesStepView: some View {
        let previewImg = MenuBarWidgetRenderer.shared.image(
            mode: viewModel.settings.menuBarDisplayMode,
            accounts: viewModel.accounts,
            activeAccount: viewModel.activeAccount,
            isSwitching: false,
            isTurkish: l10n.isTurkish,
            overrideDark: scheme == .dark
        )

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("Üst Bar & Otomasyon Tercihleri", "Menu Bar & Automation"))
                    .font(.system(size: 20, weight: .bold))
                Text(
                    l10n.t(
                        "Üst bar limit göstergelerini ve arka plan otomasyonlarını tercihinize göre ayarlayın. Her şeyi Ayarlar'dan istediğiniz an değiştirebilirsiniz.",
                        "Customize your macOS menu bar limit widget and background sync rules. Everything can be adjusted anytime in Settings."
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            // Live Menu Bar Preview Strip
            VStack(alignment: .leading, spacing: 7) {
                Text(l10n.t("CANLI ÜST BAR ÖNİZLEMESİ", "LIVE MENU BAR PREVIEW"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)

                HStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 12))
                        Text("Claude")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(l10n.t("Dosya", "File"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Text(l10n.t("Düzenle", "Edit"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.showMenuBarExtra {
                        Image(nsImage: previewImg)
                            .interpolation(.high)
                    } else {
                        Text(l10n.t("Üst bar simgesi gizli", "Menu bar icon hidden"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                    Text(l10n.t("Cum 12:48", "Fri 12:48"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(scheme == .dark ? Color(red: 0.14, green: 0.15, blue: 0.18) : Color(red: 0.90, green: 0.91, blue: 0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 0.75)
                )
            }

            // Clean Preference Toggles
            VStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n.t("macOS Üst Bar (Menu Bar) Simgesi", "Show macOS Menu Bar Widget"))
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(
                                l10n.t(
                                    "Canlı Retina limit barlarını ve hızlı açılır menüyü üst barda gösterir (⌘⇧M).",
                                    "Displays live Retina limit bars and quick popover in the top bar (⌘⇧M)."
                                )
                            )
                            .font(.system(size: 10.5))
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
                .padding(12)
                .liquidGlassCard(cornerRadius: 12)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("Otomatik Ortak Kart Eşitleme (Oto Kart)", "Auto Shared-Card Sync"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(
                            l10n.t(
                                "Paylaşılan bir oturumda çalışmaya devam ettiğinizde diğer hesaptaki kartı arka planda güncel tutar.",
                                "Silently mirrors updated turn counts and titles back to your other account for shared sessions."
                            )
                        )
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { viewModel.settings.autoSyncSharedCards },
                            set: { val in viewModel.updateSettings { $0.autoSyncSharedCards = val } }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(12)
                .liquidGlassCard(cornerRadius: 12)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("Limit Dolunca Otomatik Geçiş (429 Failover)", "Automatic Failover on Rate Limit"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(
                            l10n.t(
                                "Aktif hesapta 429 limiti dolduğunda canlı oturumları sağlıklı hesaba aktarıp pencereye geçer.",
                                "Transfers live sessions to your healthy account and switches profile automatically when 429 hits."
                            )
                        )
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { viewModel.settings.autoSwitchEnabled },
                            set: { val in viewModel.updateSettings { $0.autoSwitchEnabled = val } }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(12)
                .liquidGlassCard(cornerRadius: 12)
            }
        }
    }

    // MARK: - Footer Navigation Bar

    private var footerBar: some View {
        HStack {
            if step != .preferences {
                Button(l10n.t("Kurulumu Atla", "Skip Setup")) {
                    viewModel.completeOnboarding()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            } else {
                Text(l10n.t("Kurulum tamamlandı — başlamaya hazırsın.", "All set — ready to start."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if step.rawValue > 0 {
                    Button(l10n.t("Geri", "Back")) {
                        if let prev = OnboardingStep(rawValue: step.rawValue - 1) {
                            withAnimation(.snappy(duration: 0.18)) {
                                viewModel.onboardingStep = prev
                            }
                        }
                    }
                    .nativeGlassButton()
                    .controlSize(.regular)
                }

                if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            viewModel.onboardingStep = next
                        }
                        if next == .permissions {
                            viewModel.refreshSetupDiagnostics()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(l10n.t("Devam Et", "Continue"))
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(BridgeTheme.primaryAccent))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(TactileScaleButtonStyle())
                } else {
                    Button {
                        viewModel.completeOnboarding()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(l10n.t("ClaudeSYNC'i Başlat", "Start ClaudeSYNC"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(BridgeTheme.primaryAccent))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(TactileScaleButtonStyle())
                }
            }
        }
    }
}
