import SwiftUI
import Combine

/// The whole app is this one screen: a live SpriteKit world with SwiftUI
/// chrome floating on top (§15). Other features (Contracts, Codex, Profile,
/// Settings) present as sheets so the world keeps running underneath rather
/// than being replaced by a menu screen.
struct RootView: View {
    @State private var session = GameSession()
    @State private var dragState = ConstructionDragState()
    @State private var presentedSheet: SheetKind?
    @State private var toastEvent: GameEvent?
    @State private var offlineSummary: OfflineSimulationResult?
    @Environment(\.scenePhase) private var scenePhase

    enum SheetKind: String, Identifiable {
        case contracts, codex, profile, settings, worldProject
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            CityView(session: session, dragState: dragState)
                .ignoresSafeArea()
                .zIndex(0)

            VStack(spacing: 0) {
                ResourceBarView(resources: session.world.player.resources, level: session.world.player.level)
                    .padding(.top, 8)

                if showWelcomeBanner {
                    BlockoraBrandBannerView()
                        .padding(.top, 10)
                } else if !session.isConstructionModeActive {
                    Image("BlockoraLogoBadge")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 48)
                        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 5)
                        .padding(.top, 4)
                }

                Spacer()

                if session.isConstructionModeActive, let buildingID = session.activeBuildingID {
                    ConstructionView(session: session, dragState: dragState, buildingID: buildingID)
                        .transition(.move(edge: .bottom))
                } else {
                    if let step = session.activeOnboardingStep, !OnboardingStep.constructionSteps.contains(step) {
                        OnboardingHintBanner(step: step)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }
                    bottomTabBar
                }
            }
            .zIndex(1)

            if let toastEvent {
                VStack {
                    SynergyToastView(event: toastEvent)
                        .padding(.top, 60)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }

            if session.pendingPlotSelectionID != nil {
                PlotSelectionOverlay(session: session)
                    .zIndex(20)
            }

            if let plotID = session.pendingPlotUnlockID,
               let plot = session.world.plots.first(where: { $0.id == plotID }) {
                PlotUnlockOverlay(session: session, plot: plot)
                    .zIndex(20)
            }

            if let day = session.pendingDailyBonusDay {
                DailyBonusOverlay(session: session, day: day)
                    .zIndex(25)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session.isConstructionModeActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: toastEvent?.id)
        .animation(.easeInOut(duration: 0.25), value: session.activeOnboardingStep)
        .task { await session.loadGame() }
        .onChange(of: session.pendingOfflineSummary?.elapsedSeconds) {
            offlineSummary = session.consumeOfflineSummary()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // The most important save point: resource accrual and construction
            // progress only otherwise flush periodically (§GameSession
            // autosaveInterval) or on a discrete action, so a kill right after
            // backgrounding could lose up to that whole interval without this.
            if newPhase != .active { session.persist() }
        }
        .sheet(item: $presentedSheet) { sheet in
            sheetView(for: sheet)
        }
        .sheet(item: $offlineSummary) { summary in
            OfflineSummarySheet(summary: summary) { offlineSummary = nil }
        }
        .onReceive(Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()) { _ in
            if let next = session.consumeToastEvents().first {
                toastEvent = next
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                    if toastEvent?.id == next.id { toastEvent = nil }
                }
            }
        }
    }

    private var showWelcomeBanner: Bool {
        session.world.buildings.isEmpty && !session.isConstructionModeActive
    }

    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            tabButton(.contracts, icon: "doc.text.fill", title: "Contracts", accent: BlockoraPalette.craneOrange)
            tabButton(.codex, icon: "book.closed.fill", title: "Codex", accent: BlockoraPalette.water)
            tabButton(.worldProject, icon: "building.columns.fill", title: "Project", accent: BlockoraPalette.island)
            tabButton(.profile, icon: "person.fill", title: "Profile", accent: BlockoraPalette.coinGold)
            tabButton(.settings, icon: "gearshape.fill", title: "Settings", accent: BlockoraPalette.roadGray)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(BlockoraPalette.panelBackground.opacity(0.74))
        .overlay(Rectangle().stroke(BlockoraPalette.panelBorder, lineWidth: 1))
    }

    private func tabButton(_ sheet: SheetKind, icon: String, title: String, accent: Color) -> some View {
        // Deliberately no BlockoraGameButtonStyle here: its pill texture has
        // fixed ~90pt cap insets meant for full-size CTAs (Done/Accept). Forced
        // into a ~77pt-wide tab slot it can't shrink to fit, so it rendered
        // wider than its slot and stole taps from the neighboring tab.
        Button {
            session.acknowledgeTabExplored()
            presentedSheet = sheet
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1.5))
                    .shadow(color: accent.opacity(0.5), radius: 4, y: 2)
                    .frame(width: 38, height: 38)
                    .overlay(Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
                Text(title).font(.caption2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sheetView(for sheet: SheetKind) -> some View {
        switch sheet {
        case .contracts: ContractsView(session: session)
        case .codex: BlueprintCodexView(session: session)
        case .profile: ProfileView(session: session)
        case .settings: SettingsView(session: session)
        case .worldProject: WorldProjectView(session: session)
        }
    }

}

private struct PlotSelectionOverlay: View {
    let session: GameSession

    var body: some View {
        overlayShell {
            Text("Choose Build")
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
            VStack(spacing: 10) {
                ForEach(session.unlockedBuildingClasses, id: \.self) { buildingClass in
                    Button(buildingClass.displayName) {
                        if let plotID = session.pendingPlotSelectionID {
                            session.chooseBuildingClass(buildingClass, for: plotID)
                        }
                    }
                    .buttonStyle(BlockoraGameButtonStyle())
                }
                Button("Cancel") { session.pendingPlotSelectionID = nil }
                    .buttonStyle(BlockoraGameButtonStyle())
                    .opacity(0.72)
            }
        }
    }
}

private struct PlotUnlockOverlay: View {
    let session: GameSession
    let plot: Plot

    var body: some View {
        overlayShell {
            Text("Unlock Plot")
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
            Text("Costs \(Int(plot.unlockCost[.coins] ?? 0)) coins.")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 12) {
                Button("Cancel") { session.pendingPlotUnlockID = nil }
                    .buttonStyle(BlockoraGameButtonStyle())
                    .opacity(0.72)
                Button("Unlock") { session.confirmUnlockPlot(plot.id) }
                    .buttonStyle(BlockoraGameButtonStyle())
            }
        }
    }
}

private struct DailyBonusOverlay: View {
    let session: GameSession
    let day: Int

    private var reward: ResourceBag { DailyBonusEngine.reward(forDay: day) }

    var body: some View {
        overlayShell {
            Text("Daily Bonus")
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
            Text("Day \(day) of \(DailyBonusEngine.cycleLength)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 6) {
                ForEach(1...DailyBonusEngine.cycleLength, id: \.self) { streakDay in
                    Circle()
                        .fill(streakDay == day ? BlockoraPalette.coinGold : Color.white.opacity(0.18))
                        .overlay(streakDay == day ? Circle().stroke(.white, lineWidth: 2) : nil)
                        .frame(width: streakDay == day ? 16 : 10, height: streakDay == day ? 16 : 10)
                }
            }
            .padding(.vertical, 2)

            HStack(spacing: 16) {
                ForEach(Array(reward.keys), id: \.self) { resource in
                    VStack(spacing: 4) {
                        Image(systemName: resource.symbolName)
                            .font(.title2)
                            .foregroundStyle(resource == .coins ? BlockoraPalette.coinGold : .white)
                        Text("+\(Int(reward[resource] ?? 0))")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.vertical, 4)

            Button("Claim") { session.claimDailyBonus() }
                .buttonStyle(BlockoraGameButtonStyle())
        }
    }
}

private func overlayShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ZStack {
        Color.black.opacity(0.35).ignoresSafeArea()
        BlockoraPanel {
            VStack(spacing: 14) { content() }
        }
        .padding(.horizontal, 34)
    }
}

private struct OfflineSummarySheet: View {
    let summary: OfflineSimulationResult
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            BlockoraSheetBackground()
            VStack(spacing: 20) {
                Text("While You Were Away")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                Text(durationText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))

                BlockoraPanel {
                    VStack(spacing: 10) {
                        ForEach(Array(summary.resourceDeltas.keys), id: \.self) { resource in
                            HStack {
                                Image(systemName: resource.symbolName)
                                Text(resource.displayName)
                                Spacer()
                                let amount = summary.resourceDeltas[resource] ?? 0
                                Text("\(amount >= 0 ? "+" : "")\(Int(amount))")
                                    .foregroundStyle(amount >= 0 ? BlockoraPalette.safe : BlockoraPalette.danger)
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        }
                    }
                }

                Button("Collect") { onDismiss() }
                    .controlSize(.large)
                    .buttonStyle(BlockoraGameButtonStyle())
            }
            .padding(24)
        }
        .presentationDetents([.medium])
    }

    private var durationText: String {
        let minutes = Int(summary.elapsedSeconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

extension OfflineSimulationResult: Identifiable {
    var id: TimeInterval { elapsedSeconds }
}
