import ClaudeSYNCCore
import SwiftUI

struct LimitsDashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    var isWideLayout: Bool = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                autoSwitchControlCard

                if viewModel.accounts.isEmpty {
                    emptyLimitsCard
                } else if isWideLayout && viewModel.accounts.count >= 2 {
                    // Clean symmetric 2-column grid in the full Desktop App window
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
                    Text("Otomatik Limit Geçişi")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Limit dolduğunda aktif oturumu diğer hesaba otomatik aktarır")
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
                    Text("TETİKLEME KOŞULU")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.7)

                    LiquidGlassSegmentedControl(
                        items: AutoSwitchTrigger.allCases,
                        selection: Binding(
                            get: { viewModel.settings.autoSwitchTrigger },
                            set: { val in viewModel.updateSettings { $0.autoSwitchTrigger = val } }
                        ),
                        title: { $0.title },
                        compact: true
                    )

                    HStack(spacing: 16) {
                        Toggle(
                            "Tüm canlı oturumları birlikte taşı",
                            isOn: Binding(
                                get: { viewModel.settings.autoSwitchTransferAllLive },
                                set: { val in viewModel.updateSettings { $0.autoSwitchTransferAllLive = val } }
                            )
                        )
                        .font(.system(size: 11))
                        .toggleStyle(.checkbox)

                        Toggle(
                            "Bildirim gönder",
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
                    Text("Çıkışsız Çift Profil aktif — iki hesap kalıcı giriş yapılı.")
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
                        Text("Çıkış yapmadan doğrudan pencere geçişi")
                            .font(.system(size: 11, weight: .semibold))
                        Text("2. profili bir kez açın; limit dolunca çıkış/girişsiz otomatik geçsin.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.enableZeroLogoutDualProfileQuick()
                    } label: {
                        Text("2. Profili Aç")
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
                        Text(account.profileName)
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .foregroundStyle(.secondary)
                    }
                    Text("Org \(String(account.orgUuid.prefix(8))) · \(account.activeSessions.count) aktif oturum")
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
                        title: "5 Saat",
                        diameter: 54,
                        lineWidth: 5
                    )
                    AnimatedCircularGauge(
                        percent: usage?.sevenDayPercent,
                        title: "7 Gün",
                        diameter: 54,
                        lineWidth: 5
                    )
                }

                VStack(spacing: 8) {
                    LinearUsageBar(
                        label: "5 Saatlik",
                        percent: usage?.fiveHourPercent,
                        subtitle: usage?.fiveHourPercent == nil && (usage?.sevenDayPercent ?? 0) >= 100 ? "(7g dolu)" : nil
                    )
                    LinearUsageBar(
                        label: "7 Günlük",
                        percent: usage?.sevenDayPercent
                    )
                    if let xu = usage?.extraUsagePercent {
                        LinearUsageBar(label: "Ek Kullanım", percent: xu)
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
                        Text("\(hit.rateLimitTypeLabel) · \(hit.isCurrentlyRejected ? "Aktif Kısıtlama" : "Son Kayıt")")
                            .font(.system(size: 10.5, weight: .semibold))
                        if let resetDate = hit.resetsAt {
                            Text("Yenilenme: \(TurkishDateFormatter.shortClockTime(resetDate)) (\(TurkishDateFormatter.countdownString(until: resetDate)))")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Kaydedildi: \(TurkishDateFormatter.relativeString(from: hit.timestamp))")
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
                        Text("7 GÜNLÜK KULLANIM EĞRİSİ")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .tracking(0.6)
                        Spacer()
                        if let ts = usage?.updatedAt {
                            Text("Son güncelleme: \(TurkishDateFormatter.relativeString(from: ts))")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    UsageSparkline(points: history, metric: .sevenDay)
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
            if isExhausted { return ("Limit Dolu", Color(nsColor: .systemRed)) }
            if isActive { return ("Aktif Hesap", Color(nsColor: .systemGreen)) }
            return ("Yedek Hazır", Color(nsColor: .systemBlue))
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
            Label("Otomatik Geçiş Kayıtları", systemImage: "clock.arrow.2.circlepath")
                .font(.system(size: 11.5, weight: .semibold))

            ForEach(viewModel.autoSwitchHistory.prefix(5)) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.switchedWindow ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("→ \(entry.targetName) (\(entry.transferredCount) oturum)")
                            .font(.system(size: 11, weight: .medium))
                        Text(entry.reason)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(TurkishDateFormatter.relativeString(from: entry.timestamp))
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
            Text("Henüz limit verisi okunamadı")
                .font(.system(size: 12, weight: .semibold))
            Text("Claude Desktop açık olduğunda plan-usage-history.json ve oturum kayıtları otomatik izlenir.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .liquidGlassCard(cornerRadius: BridgeTheme.cardRadius)
    }
}
