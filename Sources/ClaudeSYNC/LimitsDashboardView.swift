import ClaudeSYNCCore
import SwiftUI

struct LimitsDashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    var isWideLayout: Bool = false

    private var l10n: L10n { viewModel.l10n }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                autoSwitchControlCard

                if viewModel.accounts.isEmpty {
                    emptyLimitsCard
                } else if isWideLayout && viewModel.accounts.count >= 2 {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(viewModel.accounts.prefix(2)) { account in
                            accountLimitDetailCard(account)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if viewModel.accounts.count > 2 {
                        ForEach(viewModel.accounts.dropFirst(2)) { account in
                            accountLimitDetailCard(account)
                        }
                    }
                } else {
                    ForEach(viewModel.accounts) { account in
                        accountLimitDetailCard(account)
                    }
                }

                if !viewModel.autoSwitchHistory.isEmpty {
                    autoSwitchHistoryCard
                }
            }
            .padding(.horizontal, isWideLayout ? 16 : BridgeTheme.hPad)
            .padding(.vertical, isWideLayout ? 16 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Auto-Switch Control Card

    private var autoSwitchControlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 30, height: 30)
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(l10n.t("Otomatik Limit Geçişi", "Automatic Limit Failover"))
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(
                        l10n.t(
                            "Limit dolduğunda aktif oturumu diğer hesaba otomatik aktarır",
                            "Automatically transfers active sessions to your healthy account when a limit hits"
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

            if viewModel.settings.autoSwitchEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("TETİKLEME KOŞULU", "FAILOVER TRIGGER"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.7)

                    LiquidGlassSegmentedControl(
                        items: AutoSwitchTrigger.allCases,
                        selection: Binding(
                            get: { viewModel.settings.autoSwitchTrigger },
                            set: { val in viewModel.updateSettings { $0.autoSwitchTrigger = val } }
                        ),
                        title: { $0.title(isTurkish: l10n.isTurkish) },
                        compact: true
                    )

                    HStack(spacing: 16) {
                        Toggle(
                            l10n.t("Tüm canlı oturumları birlikte taşı", "Transfer all live sessions together"),
                            isOn: Binding(
                                get: { viewModel.settings.autoSwitchTransferAllLive },
                                set: { val in viewModel.updateSettings { $0.autoSwitchTransferAllLive = val } }
                            )
                        )
                        .font(.system(size: 11))
                        .toggleStyle(.checkbox)

                        Toggle(
                            l10n.t("Bildirim gönder", "Send notification"),
                            isOn: Binding(
                                get: { viewModel.settings.autoSwitchNotify },
                                set: { val in viewModel.updateSettings { $0.autoSwitchNotify = val } }
                            )
                        )
                        .font(.system(size: 11))
                        .toggleStyle(.checkbox)

                        Spacer()
                    }
                }
            }

            Divider().opacity(0.45)

            if viewModel.isCrossProfileMode {
                HStack(spacing: 8) {
                    PulseStatusDot(color: Color(nsColor: .systemGreen), size: 6, isPulsing: true)
                    Text(
                        l10n.t(
                            "Çıkışsız Çift Profil aktif — iki hesap kalıcı giriş yapılı.",
                            "Zero-Logout Dual Profile active — both accounts stay signed in."
                        )
                    )
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l10n.t("Çıkış yapmadan doğrudan pencere geçişi", "Direct window switching without logging out"))
                            .font(.system(size: 11, weight: .semibold))
                        Text(
                            l10n.t(
                                "2. profili bir kez açın; limit dolunca çıkış/girişsiz otomatik geçsin.",
                                "Launch Profile 2 once to unlock automatic zero-logout switching."
                            )
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.enableZeroLogoutDualProfileQuick()
                    } label: {
                        Text(l10n.t("2. Profili Aç", "Open Profile 2"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(BridgeTheme.primaryAccent))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(TactileScaleButtonStyle())
                }
            }
        }
        .padding(13)
        .liquidGlassCard(cornerRadius: BridgeTheme.cardRadius)
    }

    // MARK: - Per-Account Detailed Telemetry Card

    private func accountLimitDetailCard(_ account: AccountSlot) -> some View {
        let usage = account.usage
        let isExhausted = usage?.isExhausted == true

        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                PulseStatusDot(
                    color: isExhausted
                        ? Color(nsColor: .systemRed)
                        : (account.isActiveAccount ? Color(nsColor: .systemGreen) : Color(nsColor: .systemBlue)),
                    size: 6.5,
                    isPulsing: account.isActiveAccount
                )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(account.displayName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(l10n.profileDisplayName(account.profileName, isDefault: account.isDefaultProfile))
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        l10n.t(
                            "Org \(String(account.orgUuid.prefix(8))) · \(account.activeSessions.count) aktif oturum",
                            "Org \(String(account.orgUuid.prefix(8))) · \(account.activeSessions.count) active sessions"
                        )
                    )
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                statusBadge(isExhausted: isExhausted, isActive: account.isActiveAccount)
            }

            HStack(spacing: 14) {
                HStack(spacing: 12) {
                    AnimatedCircularGauge(
                        percent: usage?.fiveHourPercent,
                        title: l10n.t("5 Saat", "5 Hours"),
                        diameter: 54,
                        lineWidth: 5
                    )
                    AnimatedCircularGauge(
                        percent: usage?.sevenDayPercent,
                        title: l10n.t("7 Gün", "7 Days"),
                        diameter: 54,
                        lineWidth: 5
                    )
                }

                VStack(spacing: 8) {
                    LinearUsageBar(
                        label: l10n.t("5 Saatlik", "5-Hour Window"),
                        percent: usage?.fiveHourPercent,
                        subtitle: usage?.fiveHourPercent == nil && (usage?.sevenDayPercent ?? 0) >= 100
                            ? l10n.t("(7g dolu)", "(7d full)")
                            : nil,
                        isTurkish: l10n.isTurkish
                    )
                    LinearUsageBar(
                        label: l10n.t("7 Günlük", "7-Day Window"),
                        percent: usage?.sevenDayPercent,
                        isTurkish: l10n.isTurkish
                    )
                    if let xu = usage?.extraUsagePercent {
                        LinearUsageBar(
                            label: l10n.t("Ek Kullanım", "Extra Usage"),
                            percent: xu,
                            isTurkish: l10n.isTurkish
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if let hit = usage?.lastRateLimitHit {
                HStack(spacing: 8) {
                    Image(systemName: hit.isCurrentlyRejected ? "clock.badge.exclamationmark.fill" : "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(hit.isCurrentlyRejected ? Color(nsColor: .systemRed) : .secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(
                            "\(hit.rateLimitTypeLabel(isTurkish: l10n.isTurkish)) · \(hit.isCurrentlyRejected ? l10n.t("Aktif Kısıtlama", "Active Throttle") : l10n.t("Son Kayıt", "Last Event"))"
                        )
                        .font(.system(size: 10.5, weight: .semibold))
                        if let resetDate = hit.resetsAt {
                            Text(
                                l10n.t(
                                    "Yenilenme: \(l10n.shortClock(resetDate)) (\(l10n.countdown(until: resetDate)))",
                                    "Resets: \(l10n.shortClock(resetDate)) (\(l10n.countdown(until: resetDate)))"
                                )
                            )
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        } else {
                            Text(
                                l10n.t(
                                    "Kaydedildi: \(l10n.relativeDate(hit.timestamp))",
                                    "Recorded: \(l10n.relativeDate(hit.timestamp))"
                                )
                            )
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill((hit.isCurrentlyRejected ? Color(nsColor: .systemRed) : Color.secondary).opacity(0.10))
                )
            }

            if let history = usage?.history, !history.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(l10n.t("7 GÜNLÜK KULLANIM EĞRİSİ", "7-DAY USAGE TREND"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .tracking(0.6)
                        Spacer()
                        if let ts = usage?.updatedAt {
                            Text(
                                l10n.t(
                                    "Son güncelleme: \(l10n.relativeDate(ts))",
                                    "Updated \(l10n.relativeDate(ts))"
                                )
                            )
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                        }
                    }

                    UsageSparkline(
                        points: history,
                        metric: .sevenDay,
                        emptyLabel: l10n.t("Grafik için yeterli örnek birikmedi", "Not enough samples for chart yet")
                    )
                    .frame(height: 48)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }
        }
        .padding(13)
        .liquidGlassCard(
            cornerRadius: BridgeTheme.cardRadius,
            tint: nil,
            strokeAccent: isExhausted
                ? Color(nsColor: .systemRed).opacity(0.32)
                : (account.isActiveAccount ? Color(nsColor: .systemGreen).opacity(0.28) : nil)
        )
    }

    private func statusBadge(isExhausted: Bool, isActive: Bool) -> some View {
        let (text, color): (String, Color) = {
            if isExhausted { return (l10n.t("Limit Dolu", "Limit Hit"), Color(nsColor: .systemRed)) }
            if isActive { return (l10n.t("Aktif Hesap", "Active Account"), Color(nsColor: .systemGreen)) }
            return (l10n.t("Yedek Hazır", "Standby Ready"), Color(nsColor: .systemBlue))
        }()

        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Auto-Switch History

    private var autoSwitchHistoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(l10n.t("Otomatik Geçiş Kayıtları", "Auto-Failover History"), systemImage: "clock.arrow.2.circlepath")
                .font(.system(size: 11.5, weight: .semibold))

            ForEach(viewModel.autoSwitchHistory.prefix(5)) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.switchedWindow ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(
                            l10n.t(
                                "→ \(entry.targetName) (\(entry.transferredCount) oturum)",
                                "→ \(entry.targetName) (\(entry.transferredCount) sessions)"
                            )
                        )
                        .font(.system(size: 11, weight: .medium))
                        Text(entry.reason)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(l10n.relativeDate(entry.timestamp))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(13)
        .liquidGlassCard(cornerRadius: BridgeTheme.cardRadius)
    }

    private var emptyLimitsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(l10n.t("Henüz limit verisi okunamadı", "No usage telemetry found yet"))
                .font(.system(size: 12, weight: .semibold))
            Text(
                l10n.t(
                    "Claude Desktop açık olduğunda plan-usage-history.json ve oturum kayıtları otomatik izlenir.",
                    "When Claude Desktop runs, plan-usage-history.json and session logs are monitored automatically."
                )
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .liquidGlassCard(cornerRadius: BridgeTheme.cardRadius)
    }
}
