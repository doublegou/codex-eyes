import SwiftUI
import Charts
import CodexEyesCore

struct UsageDetailsView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0
    @State private var activityAccountID: String?
    @State private var activityHeatmap = false
    @State private var overviewHeatmap = false
    init(model: AppModel, initialTab: Int = 0, initialHeatmap: Bool = false) {
        self.model = model; _tab = State(initialValue: initialTab)
        _activityHeatmap = State(initialValue: initialHeatmap)
        _overviewHeatmap = State(initialValue: initialHeatmap)
    }
    private var selection: Binding<String?> {
        Binding(get: {
            if tab == 3 { return activityAccountID ?? model.identity.viewedAccountID ?? model.orderedAccounts.first?.id }
            return tab == 1 ? "session" : "overview"
        }, set: { value in
            switch value {
            case "overview": tab = 0
            case "session": tab = 1
            case .some(let id): activityAccountID = id; tab = 3
            case nil: break
            }
        })
    }
    private var title: String {
        switch tab {
        case 1: return L("本机会话")
        case 3: return model.accounts.first { $0.id == selection.wrappedValue }.map(model.name) ?? L("账号活动")
        default: return L("用量总览")
        }
    }
    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    Label(L("用量总览"), systemImage: "chart.bar.xaxis").tag("overview")
                    Label(L("本机会话"), systemImage: "text.bubble").tag("session")
                }
                Section(L("账号")) {
                    ForEach(model.orderedAccounts) { account in
                        Label(model.name(account), systemImage: "person.crop.circle").lineLimit(1).tag(account.id)
                    }
                }
            }.listStyle(.sidebar)
                .navigationTitle(L("用量明细"))
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } detail: {
            Group {
                switch tab {
                case 1: session
                case 3: accountActivity
                default: overview
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await model.refresh() } } label: {
                            Label(L("刷新用量"), systemImage: "arrow.clockwise")
                        }.disabled(model.busy)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 500)
        .onChange(of: model.accounts.map(\.id)) { _, ids in
            if let id = activityAccountID, !ids.contains(id) { activityAccountID = nil; tab = 0 }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupBox {
                    HStack(spacing: 24) {
                        stat(L("本机今日"), model.local.daily(Date()))
                        Divider()
                        stat(L("累积用量"), model.activityTotals.total, partial: !model.activityTotals.complete)
                            .help(L("所列账号的官方累计之和，包含其他设备"))
                    }.padding(8)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(overviewHeatmap ? L("本机活动 · 全部记录") : L("本机近30天")).font(.headline)
                        Spacer()
                        Button { overviewHeatmap.toggle() } label: {
                            Label(overviewHeatmap ? L("切换为柱状图") : L("切换为热力图"),
                                  systemImage: overviewHeatmap ? "chart.bar" : "square.grid.3x3")
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.small)
                        .frame(width: 28, height: 22)
                        .help(overviewHeatmap ? L("切换为柱状图") : L("切换为热力图"))
                        .accessibilityValue(overviewHeatmap ? L("热力图") : L("柱状图"))
                    }.padding(.horizontal, 10)
                    let days = localActivityDays(all: overviewHeatmap)
                    if overviewHeatmap {
                        if days.isEmpty {
                            ContentUnavailableView(L("暂无每日记录"), systemImage: "chart.bar")
                        } else { AccountActivityHeatmapView(days: days) }
                    } else {
                        GroupBox { UsageActivityChart(days: days).padding(.top, 12) }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("会话用量排行")).font(.headline)
                    Table(Array(model.local.usageSessions.sorted { $0.totalOwned.total > $1.totalOwned.total }.prefix(20))) {
                        TableColumn(L("会话")) { item in
                            Text(model.preferences.privacy ? L("本机会话") : item.displayTitle).lineLimit(1)
                        }
                        TableColumn("Token") { item in
                            Text(compactNumber(item.totalOwned.total)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                        }.width(100)
                    }.tableStyle(.inset(alternatesRowBackgrounds: false)).frame(height: 240)
                }
            }.padding(24)
        }
    }

    private func localActivityDays(all: Bool) -> [AccountActivityDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let history = LocalUsageHeatmap(snapshot: model.local, range: all ? .all : .thirtyDays,
                                        calendar: calendar, coarsenLongHistory: false)
        return history.cells.map { cell in
            let parts = calendar.dateComponents([.year, .month, .day], from: cell.start)
            return AccountActivityDay(startDate: String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!), tokens: cell.tokens)
        }
    }

    private func stat(_ title: String, _ amount: Int?, partial: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(amount.map { (partial ? "≥" : "") + compactNumber($0) } ?? "—")
                    .font(.system(size: 26, weight: .medium)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
                if amount != nil { Text("Token").font(.caption).foregroundStyle(.secondary).fixedSize() }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var session: some View {
        Group {
            if let selected = model.selectedSession {
                Form {
                    Section {
                        Text(model.preferences.privacy ? L("本机会话") : selected.displayTitle).font(.headline)
                        LabeledContent(L("模型"), value: selected.model ?? L("未记录"))
                        LabeledContent(L("会话累计"), value: compactNumber(selected.totalOwned.total) + " Token")
                        LabeledContent(L("上下文压缩"), value: L("\(selected.compactions) 次"))
                    }
                    Section(L("最近请求")) {
                        row(L("输入"), selected.lastUsage.input)
                        row(L("其中缓存"), selected.lastUsage.cached)
                        row(L("输出"), selected.lastUsage.output)
                        row(L("其中推理"), selected.lastUsage.reasoning)
                        row(L("合计"), selected.lastUsage.total)
                    }
                }.formStyle(.grouped)
            } else {
                ContentUnavailableView(L("暂无会话"), systemImage: "text.bubble", description: Text(L("检测到本机记录后会显示用量")))
            }
        }
    }

    private var accountActivity: some View {
        let account = model.accounts.first { $0.id == selection.wrappedValue }
        let state = account.flatMap { model.activities[$0.id] }
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let account {
                    HStack(spacing: 12) {
                        AccountAvatar(name: model.name(account), size: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name(account)).font(.title2.weight(.semibold))
                            Text(account.plan ?? "Codex").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.busy { ProgressView().controlSize(.small) }
                    }
                }
                GroupBox {
                    HStack(spacing: 16) {
                        stat(L("累积用量"), state?.snapshot?.summary.lifetimeTokens)
                        Divider()
                        stat(L("单日最高"), state?.snapshot?.summary.peakDailyTokens)
                    }.padding(8)
                }
                if let error = state?.error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                if let snapshot = state?.snapshot {
                    if let days = snapshot.dailyUsageBuckets {
                        if days.isEmpty {
                            ContentUnavailableView(L("暂无每日记录"), systemImage: "chart.bar")
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(activityHeatmap ? L("每日活动 · 全部记录") : L("每日活动 · 最近30条记录"))
                                        .font(.headline)
                                    Spacer()
                                    Button { activityHeatmap.toggle() } label: {
                                        Label(activityHeatmap ? L("切换为柱状图") : L("切换为热力图"),
                                              systemImage: activityHeatmap ? "chart.bar" : "square.grid.3x3")
                                    }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.small)
                                    .frame(width: 28, height: 22)
                                    .help(activityHeatmap ? L("切换为柱状图") : L("切换为热力图"))
                                    .accessibilityValue(activityHeatmap ? L("热力图") : L("柱状图"))
                                }.padding(.horizontal, 10)
                                if activityHeatmap {
                                    AccountActivityHeatmapView(days: days).id(account?.id)
                                } else {
                                    GroupBox {
                                        UsageActivityChart(days: Array(days.suffix(30))).padding(.top, 12)
                                    }
                                }
                            }
                            DisclosureGroup(L("每日用量明细（\(days.count)天）")) {
                                Table(Array(days.reversed())) {
                                    TableColumn(L("日期")) { day in Text(day.startDate).monospacedDigit() }
                                    TableColumn("Token") { day in
                                        Text(compactNumber(day.tokens)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                                            .help(day.tokens.formatted())
                                    }.width(110)
                                }.tableStyle(.inset(alternatesRowBackgrounds: false)).frame(height: 240).padding(.top, 10)
                            }
                        }
                    } else { ContentUnavailableView(L("未提供每日记录"), systemImage: "chart.bar") }

                } else { ContentUnavailableView(model.busy ? L("正在读取") : L("暂无账号活动"), systemImage: "chart.bar") }
            }.padding(24)
        }
    }

    private func row(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(compactNumber(value)).monospacedDigit().textSelection(.enabled)
        }.font(.system(size: 12))
    }
}

private struct UsageActivityChart: View {
    let days: [AccountActivityDay]
    var body: some View {
        Chart(days) { day in
            BarMark(x: .value(L("日期"), day.startDate), y: .value("Token", day.tokens))
                .foregroundStyle(Color(nsColor: .systemBlue).gradient)
                .cornerRadius(2)
                .accessibilityLabel(day.startDate)
                .accessibilityValue(day.tokens.formatted() + " Token")
        }
        .chartXAxis {
            AxisMarks(values: days.enumerated().filter { $0.offset % 7 == 0 }.map { $0.element.startDate }) { value in
                AxisValueLabel { if let day = value.as(String.self) { Text(String(day.suffix(5))).fixedSize() } }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame, !days.isEmpty {
                    let plot = geometry[anchor]
                    let width = plot.width / CGFloat(days.count)
                    ChartToolTips(regions: days.compactMap { day in
                        proxy.position(forX: day.startDate).map { x in
                            ChartToolTipRegion(rect: CGRect(x: plot.minX + x - width / 2, y: plot.minY,
                                                           width: width, height: plot.height),
                                               text: day.startDate + " · " + day.tokens.formatted() + " Token")
                        }
                    })
                }
            }
        }
        .chartXScale(range: .plotDimension(padding: 10))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel { if let amount = value.as(Int.self) { Text(compactNumber(amount)) } }
            }
        }
        .frame(height: 150).padding(8)
    }
}
