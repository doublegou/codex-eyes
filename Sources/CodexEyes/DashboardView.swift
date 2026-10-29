import SwiftUI
import CodexEyesCore

enum EyesTheme {
    static let accent = Color(nsColor: .controlAccentColor)
    static let mint = Color(red: 0.20, green: 0.83, blue: 0.60)
    static let warning = Color(red: 1, green: 0.65, blue: 0.22)
    static func status(_ availability: Availability) -> Color {
        switch availability {
        case .available: return mint
        case .limited: return warning
        case .loginRequired: return Color(red: 0.95, green: 0.30, blue: 0.30)
        case .unknown: return Color(white: 0.55)
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var historyRange = UsageHistoryRange.sevenDays
    private var ink: Color { scheme == .dark ? .white : .black }
    private var secondaryInk: Color { ink.opacity(0.56) }
    private var tertiaryInk: Color { ink.opacity(0.36) }
    private var reduced: Bool { model.preferences.reducedMotion || systemReduceMotion }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
            VStack(spacing: 0) {
                if let account = model.viewed {
                    HStack(alignment: .top, spacing: 64) {
                        if let windows = account.usage?.displayWindows, !windows.isEmpty {
                            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                                quota(window, fallback: window.localizedLabel, palette: window.windowMinutes >= 10080 ? .blue : .mint)
                            }
                        } else {
                            quota(nil, fallback: L("5小时"), palette: .mint)
                            quota(nil, fallback: L("每周"), palette: .blue)
                        }
                    }.frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 20)
                } else {
                    Button(L("添加 Codex 账号")) { model.onSettings?() }
                        .buttonStyle(.bordered).frame(height: 130)
                }
                session.padding(12)
                    .background(ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                usage.padding(16).padding(.top, 2)
                    .background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 12)
                if let message = model.message {
                    Text(message).font(.system(size: 10)).foregroundStyle(secondaryInk)
                        .lineLimit(2).padding(.top, 8)
                }
            }.padding(.horizontal, 20).padding(.bottom, 18)
        }
        .frame(width: PanelLayout.size.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in
            Color.clear.onAppear { model.onPanelHeight?(geometry.size.height) }
                .onChange(of: geometry.size.height) { _, height in model.onPanelHeight?(height) }
        })
        .foregroundStyle(ink)

    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                LoginAccountMenu(model: model)
                    .fixedSize()
                Spacer()
                if model.busy { ProgressView().controlSize(.mini).frame(width: 14, height: 14) }
                else {
                    Button { Task { await model.refresh() } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    }.buttonStyle(.plain).help(L("刷新所有账号"))
                }
                Menu {
                    Button(L("管理账号"), systemImage: "person.crop.circle") { model.onSettings?() }
                    Button(model.pinned ? L("取消固定") : L("固定面板"), systemImage: model.pinned ? "pin.slash" : "pin") { model.onPin?() }
                    if model.preferences.allowSwitching, let account = model.viewed, account.id != model.identity.configuredAccountID {
                        Button(L("切换到此账号登录"), systemImage: "arrow.left.arrow.right") {
                            model.requestSwitch(account.id)
                        }.disabled(model.busy)
                    }
                    Divider()
                    if let account = model.viewed, let checked = account.lastConfirmedAt {
                        Text(L("更新于 \(checked.formatted(.dateTime.hour().minute().locale(L10n.locale)))"))
                    }
                    Button(L("退出 Codex Eyes")) { model.onQuit?() }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: 17, height: 17)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(ink).help(L("更多"))
            }.frame(height: 26)
            if model.orderedAccounts.isEmpty {
                Button(L("添加账号")) { model.onSettings?() }.buttonStyle(.plain).font(.system(size: 12)).frame(height: 43)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.orderedAccounts) { account in
                            accountCard(account)
                        }
                    }
                }.frame(height: 48)
            }
        }
    }

    private func accountCard(_ account: Account) -> some View {
        let selected = account.id == model.viewed?.id
        return Button { model.view(account.id) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(model.name(account)).font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(ink).lineLimit(1)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(secondaryInk)
                    }
                }
                HStack(spacing: 4) {
                    Circle().fill(EyesTheme.status(account.availability())).frame(width: 4, height: 4)
                    Text(account.availabilitySummary()).font(.system(size: 9)).foregroundStyle(secondaryInk).lineLimit(1)
                    Spacer(minLength: 0)
                    if account.availability() == .available, let plan = account.plan {
                        Text(plan == "prolite" ? "Pro Lite" : plan.capitalized)
                            .font(.system(size: 8)).foregroundStyle(tertiaryInk).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(width: (PanelLayout.size.width - 48) / 2, height: 48)
            .background(selected ? ink.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .help(L("\(model.name(account)) · \(account.availability().text)\n点击查看，不更换登录"))
        .contextMenu {
            Button(L("查看额度")) { model.view(account.id) }
            if model.preferences.allowSwitching, account.id != model.identity.configuredAccountID {
                Button(L("切换登录")) { model.requestSwitch(account.id) }.disabled(model.busy)
            }
            Button(L("管理账号")) { model.onSettings?() }
        }
    }

    private func quota(_ window: QuotaWindow?, fallback: String, palette: ActivityRing.Palette) -> some View {
        VStack(spacing: 7) {
            ActivityRing(remaining: window?.remaining, palette: palette, reducedMotion: reduced)
            Text(window?.localizedLabel ?? fallback).font(.system(size: 11, weight: .medium))
            Text(resetLabel(window)).font(.system(size: 10)).foregroundStyle(secondaryInk).lineLimit(1).help(L("额度重置倒计时"))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window?.localizedLabel ?? fallback)，\(window.map { L("剩余 \(Int($0.remaining))%") } ?? L("未知"))，\(resetLabel(window))")
    }

    private var session: some View {
        VStack(spacing: 10) {
            if let selected = model.selectedSession {
                HStack(spacing: 8) {
                    Text(L("会话")).font(.system(size: 10)).foregroundStyle(secondaryInk)
                    Menu {
                        ForEach(model.local.usageSessions.prefix(50)) { item in
                            Button(model.preferences.privacy ? L("任务 \(item.id.prefix(6))") : item.menuTitle) {
                                model.selectedSessionID = item.id; model.preferences.pinnedSession = nil
                            }.help(model.preferences.privacy ? L("本机会话") : item.displayTitle)
                        }
                        Divider().opacity(0.14)
                        Button(model.preferences.pinnedSession == selected.id ? L("取消固定") : L("固定此会话")) {
                            model.preferences.pinnedSession = model.preferences.pinnedSession == selected.id ? nil : selected.id
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.preferences.privacy ? L("本机会话") : selected.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            if model.preferences.pinnedSession == selected.id { Image(systemName: "pin.fill").font(.system(size: 8)) }
                            Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(secondaryInk)
                        }
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).tint(ink)
                    Spacer(minLength: 0)
                    Text(compactNumber(selected.totalOwned.total) + " Token")
                        .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(secondaryInk)
                        .fixedSize().layoutPriority(1).help(L("此会话已记录的累计 Token"))
                }
                HStack(spacing: 10) {
                    Text(L("上下文")).foregroundStyle(secondaryInk)
                    GeometryReader { geometry in
                        Capsule().fill(ink.opacity(0.08))
                            .overlay(alignment: .leading) {
                                if let ratio = selected.contextRatio {
                                    Capsule().fill(ratio >= 0.85 ? Color.orange : ink.opacity(0.36)).frame(width: geometry.size.width * ratio)
                                }
                            }
                    }.frame(height: 3)
                    Text(selected.contextRatio.map { "\(Int($0 * 100))%" } ?? "—").monospacedDigit()
                }.font(.system(size: 10)).help(L("最近记录的上下文占用"))
                if let waiting = model.local.sessions.first(where: { $0.status == .permission && $0.id != selected.id }) {
                    Button {
                        model.selectedSessionID = waiting.id; model.preferences.pinnedSession = nil
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "hand.raised.fill").font(.system(size: 9)).foregroundStyle(EyesTheme.warning)
                            Text(model.preferences.privacy ? L("另一个任务等待授权") : L("\(waiting.displayTitle) 等待授权")).lineLimit(1).foregroundStyle(ink.opacity(0.8))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 8))
                        }.font(.system(size: 10)).foregroundStyle(secondaryInk)
                    }.buttonStyle(.plain).disabled(!waiting.hasUsageRecord)
                        .help(waiting.hasUsageRecord ? waiting.displayTitle : L("此会话尚无用量记录"))
                }
            } else {
                HStack { Text(L("暂无本机会话")); Spacer() }.font(.system(size: 11)).foregroundStyle(secondaryInk)
            }
        }
    }

    private var usage: some View {
        let today = DailyTokenComposition(snapshot: model.local)
        let lifetime = model.activityTotals
        return VStack(alignment: .leading, spacing: 15) {
            VStack(spacing: 8) {
                HStack {
                    Text(L("今日用量")).font(.system(size: 11)).foregroundStyle(secondaryInk)
                    Spacer()
                    Button { model.onDetails?() } label: {
                        HStack(spacing: 5) {
                            Text(L("用量明细"))
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .medium))
                        }.font(.system(size: 10)).foregroundStyle(secondaryInk)
                    }.buttonStyle(.plain)
                }
                HStack(alignment: .center, spacing: 24) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(compactNumber(today.total))
                            .font(.system(size: 29, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text("Token").font(.system(size: 9)).foregroundStyle(tertiaryInk)
                    }.frame(width: 150, alignment: .leading)
                    VStack(spacing: 6) {
                        shareRow(L("输入"), amount: today.input, fraction: today.fraction(today.input),
                                 color: Color(nsColor: .systemBlue), unknownLabel: L("未记录"))
                            .help(L("本机今日输入 Token，包含缓存输入；与左侧总量使用相同的日期范围。"))
                        shareRow(L("输出"), amount: today.output, fraction: today.fraction(today.output),
                                 color: EyesTheme.mint, unknownLabel: L("未记录"))
                            .help(L("本机今日输出 Token，包含推理输出。"))
                    }.frame(maxWidth: .infinity)
                }
            }
            rule
            trend
            rule
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    Text(L("累积用量")).font(.system(size: 11))
                    if lifetime.cached { Text(L("缓存")).font(.system(size: 8)) }
                    Spacer()
                }.foregroundStyle(secondaryInk)
                HStack(alignment: .center, spacing: 24) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(lifetime.total.map { (lifetime.complete ? "" : "≥") + compactNumber($0) } ?? "—")
                            .font(.system(size: 24, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        Text("Token").font(.system(size: 9)).foregroundStyle(tertiaryInk)
                    }.frame(width: 150, alignment: .leading)
                    officialAccountShares(lifetime)
                }
            }
        }
    }

    private var rule: some View { Rectangle().fill(ink.opacity(0.07)).frame(height: 0.5) }

    private func accountColor(_ id: String) -> Color {
        let sorted = model.accounts.map(\.id).sorted()
        let palette: [Color] = [EyesTheme.mint, Color(red: 0.55, green: 0.55, blue: 1), .orange, .pink]
        return palette[(sorted.firstIndex(of: id) ?? 0) % palette.count]
    }

    private func officialAccountShares(_ summary: AccountActivityTotals) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 6) {
                ForEach(model.orderedAccounts) { account in
                    let state = model.activities[account.id]
                    shareRow(model.name(account), amount: summary.amounts[account.id], fraction: summary.fraction(for: account.id),
                             color: accountColor(account.id),
                             unknownLabel: state?.error != nil ? L("读取失败") : (model.busy ? L("读取中") : L("未提供")))
                        .help(state?.error ?? L("官方账号累计，包含此账号在其他设备的用量。占比以所列账号累计之和计算。"))
                }
            }
        }.frame(maxWidth: .infinity).frame(height: CGFloat(min(3, max(1, model.accounts.count))) * 26)
        .help(L("官方账号累计，不限定当前电脑。缺少任一账号累计时暂不计算占比。"))
    }

    private func shareRow(_ name: String, amount: Int?, fraction: Double?, color: Color,
                          unknownLabel: String = L("未提供")) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 3, height: 3)
            Text(name).lineLimit(1).help(name).foregroundStyle(secondaryInk)
            Spacer(minLength: 0)
            Text(amount.map(compactNumber) ?? "—")
                .fontWeight(.medium).layoutPriority(1)
            Text(amount == nil ? unknownLabel : fraction.map { String(format: "%.1f%%", $0 * 100) } ?? "—")
                .foregroundStyle(secondaryInk).frame(width: 42, alignment: .trailing)
        }.font(.system(size: 10.5)).monospacedDigit().frame(height: 22)
        .accessibilityElement(children: .combine)
    }

    private var trend: some View {
        let history = LocalUsageHeatmap(snapshot: model.local, range: historyRange)
        return VStack(spacing: 10) {
            HStack {
                Text(L("用量活动")).font(.system(size: 10)).foregroundStyle(secondaryInk)
                    .help(historyHelp(history))
                Spacer()
                HStack(spacing: 3) {
                    ForEach(UsageHistoryRange.allCases, id: \.self) { period in
                        Button { historyRange = period } label: {
                            Text(period.label).font(.system(size: 9, weight: historyRange == period ? .medium : .regular))
                                .foregroundStyle(historyRange == period ? ink : secondaryInk)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(historyRange == period ? ink.opacity(0.09) : .clear, in: Capsule())
                        }.buttonStyle(.plain)
                        .accessibilityLabel(L("用量活动，") + period.label)
                        .accessibilityValue(historyRange == period ? L("已选中") : L("未选中"))
                    }
                }
            }.frame(height: 14)
            GeometryReader { geometry in
                if history.cells.isEmpty {
                    Text(L("暂无用量记录")).font(.system(size: 10)).foregroundStyle(tertiaryInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if historyRange == .sevenDays {
                    HStack(spacing: 0) {
                        ForEach(history.cells) { cell in
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(Color(nsColor: .systemBlue).opacity(Calendar.current.isDateInToday(cell.start) ? 1 : 0.65))
                                    .frame(width: 10, height: cell.tokens == 0 ? 1 : max(3, 33 * CGFloat(cell.tokens) / CGFloat(max(1, history.peak))))
                                    .frame(height: 33, alignment: .bottom)
                                    .accessibilityLabel(heatmapHelp(cell, unit: history.unit))
                                Text(Calendar.current.isDateInToday(cell.start) ? L("今天") : cell.start.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).locale(L10n.locale)))
                                    .font(.system(size: 8)).foregroundStyle(tertiaryInk)
                            }.frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(heatmapHelp(cell, unit: history.unit))
                        }
                    }.frame(height: 52)
                } else {
                    let layout = heatmapLayout(count: history.cells.count, width: geometry.size.width, height: 52)
                    VStack(spacing: 2) {
                        ForEach(0..<layout.rows, id: \.self) { row in
                            HStack(spacing: 2) {
                                ForEach(0..<layout.columns, id: \.self) { column in
                                    let index = row * layout.columns + column
                                    if history.cells.indices.contains(index) {
                                        let cell = history.cells[index]
                                        heatmapTile(cell, history: history, side: layout.side)
                                    } else {
                                        Color.clear.frame(width: layout.side, height: layout.side).accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                    }.frame(width: geometry.size.width, height: 52)
                }
                ChartToolTips(regions: chartToolTipRegions(history, width: geometry.size.width))
                    .accessibilityHidden(true)
            }.frame(height: 52)
        }
    }

    private func chartToolTipRegions(_ history: LocalUsageHeatmap, width: CGFloat) -> [ChartToolTipRegion] {
        guard !history.cells.isEmpty, width > 0 else { return [] }
        if historyRange == .sevenDays {
            let columnWidth = width / CGFloat(history.cells.count)
            return history.cells.enumerated().map { index, cell in
                ChartToolTipRegion(rect: CGRect(x: CGFloat(index) * columnWidth, y: 0, width: columnWidth, height: 52),
                                   text: heatmapHelp(cell, unit: history.unit))
            }
        }
        let layout = heatmapLayout(count: history.cells.count, width: width, height: 52)
        let pitch = layout.side + 2
        let originX = (width - (CGFloat(layout.columns) * pitch - 2)) / 2
        let originY = (52 - (CGFloat(layout.rows) * pitch - 2)) / 2
        return history.cells.enumerated().map { index, cell in
            ChartToolTipRegion(rect: CGRect(x: originX + CGFloat(index % layout.columns) * pitch - 1,
                                            y: originY + CGFloat(index / layout.columns) * pitch - 1,
                                            width: pitch, height: pitch),
                               text: heatmapHelp(cell, unit: history.unit))
        }
    }

    private func historyHelp(_ history: LocalUsageHeatmap) -> String {
        let unit: String
        switch history.unit { case .day: unit = L("天"); case .week: unit = L("周"); case .month: unit = L("月"); case .year: unit = L("年") }
        let scale = historyRange == .sevenDays ? L("每天一根柱") : L("每格一\(unit)，共 \(history.cells.count) 格；灰色表示没有用量记录")
        return L("本机日志 · \(scale)。合计 \(history.total.formatted()) Token。")
    }

    private func heatmapTile(_ cell: UsageHeatmapCell, history: LocalUsageHeatmap, side: CGFloat) -> some View {
        let level = history.level(for: cell)
        return RoundedRectangle(cornerRadius: min(3, side / 4))
            .fill(level == 0 ? ink.opacity(0.065) : Color(nsColor: .systemBlue).opacity([0, 0.25, 0.45, 0.7, 1][level]))
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .accessibilityLabel(heatmapHelp(cell, unit: history.unit))
    }

    private func heatmapLayout(count: Int, width: CGFloat, height: CGFloat) -> (rows: Int, columns: Int, side: CGFloat) {
        var best = (rows: 1, columns: count, side: CGFloat(0))
        for rows in 1...min(14, count) {
            let columns = (count + rows - 1) / rows
            let side = min(16, (width - CGFloat(columns - 1) * 2) / CGFloat(columns),
                           (height - CGFloat(rows - 1) * 2) / CGFloat(rows))
            if side > best.side { best = (rows, columns, side) }
        }
        return best
    }

    private func heatmapHelp(_ cell: UsageHeatmapCell, unit: LocalUsageHeatmap.Unit) -> String {
        var date = cell.start.formatted(.dateTime.year().month(.abbreviated).day().locale(L10n.locale))
        if unit != .day { date += " — " + cell.end.addingTimeInterval(-1).formatted(.dateTime.year().month(.abbreviated).day().locale(L10n.locale)) }
        return date + "：" + compactNumber(cell.tokens) + " Token"
    }

    private func resetLabel(_ window: QuotaWindow?) -> String {
        guard let reset = window?.resetsAt else { return "—" }
        if reset <= Date().timeIntervalSince1970 { return L("更新中") }
        return L("\(CompactTime.localizedRemaining(until: Date(timeIntervalSince1970: reset)))后重置")
    }
}

private struct ActivityRing: View {
    enum Palette { case mint, blue }
    let remaining: Double?
    let palette: Palette
    let reducedMotion: Bool
    private let diameter: CGFloat = 82
    private let thickness: CGFloat = 8
    private var base: Color { palette == .mint ? Color(red: 0.11, green: 0.76, blue: 0.48) : Color(red: 0.35, green: 0.39, blue: 0.94) }
    private var highlight: Color { palette == .mint ? Color(red: 0.61, green: 1, blue: 0.71) : Color(red: 0.66, green: 0.76, blue: 1) }
    private var fraction: Double { max(0, min(1, (remaining ?? 0) / 100)) }
    private var angle: Double { (fraction * 360 - 90) * .pi / 180 }

    var body: some View {
        ZStack {
            Circle().inset(by: thickness / 2).stroke(base.opacity(0.13), lineWidth: thickness)
            if remaining != nil {
                Circle().inset(by: thickness / 2).trim(from: 0, to: fraction)
                    .stroke(AngularGradient(colors: [base, base, highlight], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(max(1, fraction * 360))),
                            style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: base.opacity(0.12), radius: 3, y: 1)
                if fraction > 0.015 {
                    Circle().fill(LinearGradient(colors: [highlight, base], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.4))
                        .frame(width: thickness, height: thickness)
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                        .offset(x: cos(angle) * (diameter - thickness) / 2, y: sin(angle) * (diameter - thickness) / 2)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(remaining.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                if remaining != nil { Text("%").font(.system(size: 10, weight: .medium)).opacity(0.56) }
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(reducedMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: fraction)
    }
}
