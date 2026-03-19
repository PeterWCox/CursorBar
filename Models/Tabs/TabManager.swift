import Foundation
import Combine

class TabManager: ObservableObject {
    private static let autosaveDelay: TimeInterval = 0.35

    private struct LinkedTaskStatusSignature: Equatable {
        let linkedTaskID: UUID
        let isRunning: Bool
        let lastTurnState: ConversationTurnDisplayState?
    }

    @Published private(set) var projects: [ProjectState] = []
    @Published var tabs: [AgentTab] = []
    @Published var terminalTabs: [TerminalTab] = []
    @Published var selectedTabID: UUID?
    @Published var selectedTerminalID: UUID?
    @Published var selectedTasksViewPath: String?
    @Published var selectedDashboardViewPath: String?
    @Published var selectedAddProjectView: Bool = false
    @Published var selectedProjectPath: String?
    @Published private(set) var recentlyClosedTabs: [SavedAgentTab] = []
    private static let maxRecentlyClosedTabs = 20
    @Published private(set) var runningAgentCount: Int = 0
    /// Fires when any observed tab’s state changes (e.g. isRunning, turns), so subscribers can refresh derived state like tasks-in-review count.
    let tabStateDidChange = PassthroughSubject<Void, Never>()
    private var tabSubscriptions: [UUID: AnyCancellable] = [:]
    private var linkedTaskStatusSignatures: [UUID: LinkedTaskStatusSignature] = [:]
    private var persistenceSubscriptions = Set<AnyCancellable>()
    private var pendingAutosaveWorkItem: DispatchWorkItem?
    let terminalHostStore = TerminalHostStore()

    init(loadedState: SavedTabState? = nil) {
        if let saved = loadedState {
            let restoredTabs = saved.tabs
                .filter { $0.linkedTaskID != nil }
                .map { AgentTab(from: $0) }
            let filteredTabs = restoredTabs.filter { TabManager.workspacePathExists($0.workspacePath) }
            let restoredRecentlyClosedTabs = saved.recentlyClosedTabs
                .filter { $0.linkedTaskID != nil }
                .filter { TabManager.workspacePathExists($0.workspacePath) }
            let restoredProjects = saved.projects
                .filter { $0.source == .manual }
                .map { ProjectState(path: $0.path, source: $0.source) }
                .filter { TabManager.workspacePathExists($0.path) }
            let tabProjects = filteredTabs.map { ProjectState(path: $0.workspacePath, source: .manual) }

            tabs = filteredTabs
            recentlyClosedTabs = restoredRecentlyClosedTabs
            projects = Self.mergeProjects(savedProjects: restoredProjects, tabProjects: tabProjects)
            selectedTabID = saved.selectedTabID
            selectedProjectPath = saved.selectedProjectPath
            selectedAddProjectView = saved.selectedAddProjectView
        }
        reconcileSelection()
        bindTabChanges()
        configurePersistenceObservers()
        updateRunningAgentCount()
    }

    private static func workspacePathExists(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let expanded = (path as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) && isDir.boolValue
    }

    func saveState() {
        let state = SavedTabState(
            tabs: tabs
                .filter { $0.linkedTaskID != nil }
                .map { $0.toSaved() },
            recentlyClosedTabs: recentlyClosedTabs
                .filter { $0.linkedTaskID != nil && Self.workspacePathExists($0.workspacePath) },
            selectedTabID: selectedTabID,
            projects: projects
                .filter { $0.source == .manual }
                .map { SavedProject(path: $0.path, source: $0.source) },
            selectedProjectPath: selectedProjectPath,
            selectedAddProjectView: selectedAddProjectView
        )
        TabManagerPersistence.save(state)
    }

    private func configurePersistenceObservers() {
        $projects
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSaveState()
            }
            .store(in: &persistenceSubscriptions)

        $tabs
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSaveState()
                self?.updateRunningAgentCount()
            }
            .store(in: &persistenceSubscriptions)

        $selectedTabID
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSaveState()
            }
            .store(in: &persistenceSubscriptions)

        $selectedProjectPath
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSaveState()
            }
            .store(in: &persistenceSubscriptions)

        $selectedAddProjectView
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSaveState()
            }
            .store(in: &persistenceSubscriptions)
    }

    private func scheduleSaveState() {
        pendingAutosaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveState()
        }
        pendingAutosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autosaveDelay, execute: workItem)
    }

    var activeTab: AgentTab? {
        guard selectedTerminalID == nil, selectedTasksViewPath == nil, let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    var activeTerminalTab: TerminalTab? {
        guard selectedTasksViewPath == nil, let selectedTerminalID else { return nil }
        return terminalTabs.first { $0.id == selectedTerminalID }
    }

    var activeProjectPath: String? {
        activeTerminalTab?.workspacePath ?? activeTab?.workspacePath ?? selectedProjectPath ?? projects.first?.path
    }

    var openProjectCount: Int {
        projects.count
    }

    func setDiscoveredProjectsFromPaths(_ paths: [String]) {
        let normalized = paths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { Self.workspacePathExists($0) }
        let discoveredProjects = normalized.map { ProjectState(path: $0, source: .discovered) }
        let manualProjects = projects.filter { $0.source == .manual && Self.workspacePathExists($0.path) }
        let tabProjects = tabs.map { ProjectState(path: $0.workspacePath, source: .manual) }
        projects = Self.mergeProjects(savedProjects: manualProjects + discoveredProjects, tabProjects: tabProjects)
        let validPaths = Set(projects.map(\.path))
        if let current = selectedProjectPath, !validPaths.contains(current) {
            selectedProjectPath = projects.first?.path
        }
        reconcileSelection(preferredProjectPath: selectedProjectPath)
    }

    func addProject(path: String, select: Bool = true) {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.workspacePathExists(normalizedPath) else { return }
        if let index = projects.firstIndex(where: { $0.path == normalizedPath }) {
            if projects[index].source != .manual {
                projects[index].source = .manual
            }
        } else {
            projects.append(ProjectState(path: normalizedPath, source: .manual))
        }
        if select {
            selectedProjectPath = normalizedPath
            selectedAddProjectView = false
            if let existingTab = activeTab, existingTab.workspacePath == normalizedPath {
                selectedTabID = existingTab.id
                selectedTerminalID = nil
            } else if let existingTerminal = activeTerminalTab, existingTerminal.workspacePath == normalizedPath {
                selectedTerminalID = existingTerminal.id
                selectedTabID = nil
            } else if !tabs.contains(where: { $0.id == selectedTabID && $0.workspacePath == normalizedPath }),
                      !terminalTabs.contains(where: { $0.id == selectedTerminalID && $0.workspacePath == normalizedPath }) {
                selectedTabID = nil
                selectedTerminalID = nil
            }
        }
        reconcileSelection(preferredProjectPath: normalizedPath)
    }

    func selectProject(_ path: String) {
        guard projects.contains(where: { $0.path == path }) else { return }
        selectedProjectPath = path
        selectedAddProjectView = false
        if selectedDashboardViewPath != path {
            selectedDashboardViewPath = nil
        }
        if let selectedTab = activeTab, selectedTab.workspacePath == path { return }
        if let selectedTerminal = activeTerminalTab, selectedTerminal.workspacePath == path { return }
        if selectedTasksViewPath == path { return }
        if let firstTab = tabs.first(where: { $0.workspacePath == path }) {
            selectedTabID = firstTab.id
            selectedTerminalID = nil
            selectedTasksViewPath = nil
        } else if let firstTerminal = terminalTabs.first(where: { $0.workspacePath == path }) {
            selectedTerminalID = firstTerminal.id
            selectedTabID = nil
            selectedTasksViewPath = nil
        } else {
            selectedTabID = nil
            selectedTerminalID = nil
            selectedTasksViewPath = path
        }
    }

    func showTasksView(workspacePath path: String) {
        let resolved = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard projects.contains(where: { $0.path == resolved }) else { return }
        selectedProjectPath = resolved
        selectedAddProjectView = false
        selectedTasksViewPath = resolved
        selectedDashboardViewPath = nil
        selectedTabID = nil
        selectedTerminalID = nil
    }

    func showDashboardView(workspacePath path: String) {
        let resolved = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard projects.contains(where: { $0.path == resolved }) else { return }
        addProject(path: resolved, select: false)
        selectedProjectPath = resolved
        selectedAddProjectView = false
        selectedTasksViewPath = nil
        selectedDashboardViewPath = resolved
        selectedTabID = nil
        if let first = dashboardTabs(for: resolved).first {
            selectedTerminalID = first.id
        } else {
            selectedTerminalID = nil
        }
    }

    func showAddProjectView() {
        selectedAddProjectView = true
        selectedTabID = nil
        selectedTerminalID = nil
        selectedTasksViewPath = nil
        selectedDashboardViewPath = nil
    }

    @discardableResult
    func selectAgentTab(id: UUID) -> Bool {
        guard let tab = tabs.first(where: { $0.id == id }) else { return false }
        selectedAddProjectView = false
        selectedTabID = tab.id
        selectedTerminalID = nil
        selectedTasksViewPath = nil
        selectedDashboardViewPath = nil
        selectedProjectPath = tab.workspacePath
        return true
    }

    func hideTasksView() {
        selectedTasksViewPath = nil
        reconcileSelection(preferredProjectPath: selectedProjectPath)
    }

    @discardableResult
    func addTab(initialPrompt: String? = nil, workspacePath: String? = nil, modelId: String? = nil, providerID: AgentProviderID = .cursor, select: Bool = true) -> AgentTab? {
        let path = workspacePath ?? activeProjectPath ?? activeTab?.workspacePath ?? ""
        let resolved = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.workspacePathExists(resolved) else { return nil }

        addProject(path: resolved, select: select)

        let tab = AgentTab(title: "Agent \(tabs.count + 1)", workspacePath: resolved, providerID: providerID)
        if let prompt = initialPrompt, !prompt.isEmpty {
            tab.prompt = prompt
        }
        if let modelId = modelId {
            tab.modelId = modelId
        }
        tabs.append(tab)
        observe(tab)
        if select {
            selectedTabID = tab.id
            selectedTerminalID = nil
            selectedTasksViewPath = nil
            selectedAddProjectView = false
            selectedProjectPath = resolved
        }
        return tab
    }

    @discardableResult
    func addTerminalTab(workspacePath path: String? = nil) -> TerminalTab? {
        let resolved = (path ?? activeProjectPath ?? activeTab?.workspacePath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.workspacePathExists(resolved) else { return nil }
        addProject(path: resolved, select: true)
        let count = terminalTabs.filter { $0.workspacePath == resolved }.count + 1
        let tab = TerminalTab(title: "Terminal \(count)", workspacePath: resolved)
        terminalTabs.append(tab)
        selectedTerminalID = tab.id
        selectedTabID = nil
        selectedTasksViewPath = nil
        selectedDashboardViewPath = nil
        selectedAddProjectView = false
        selectedProjectPath = resolved
        return tab
    }

    func closeTerminalTab(_ id: UUID) {
        guard let index = terminalTabs.firstIndex(where: { $0.id == id }) else { return }
        let tabToClose = terminalTabs[index]
        let wasSelected = selectedTerminalID == id
        let closedPath = tabToClose.workspacePath
        terminalTabs.remove(at: index)
        if wasSelected {
            if let replacement = terminalTabs.first(where: { $0.workspacePath == closedPath }) {
                selectedTerminalID = replacement.id
                selectedTasksViewPath = nil
                selectedDashboardViewPath = tabToClose.isDashboardTab ? closedPath : (replacement.isDashboardTab ? closedPath : nil)
                selectedAddProjectView = false
            } else if let firstAgent = tabs.first(where: { $0.workspacePath == closedPath }) {
                selectedTerminalID = nil
                selectedTabID = firstAgent.id
                selectedTasksViewPath = nil
                selectedDashboardViewPath = nil
                selectedAddProjectView = false
            } else {
                selectedTerminalID = nil
                selectedTasksViewPath = (selectedTasksViewPath == closedPath ? closedPath : selectedTasksViewPath)
                selectedDashboardViewPath = tabToClose.isDashboardTab ? closedPath : nil
            }
            selectedProjectPath = closedPath
        }
    }

    func dashboardTabs(for workspacePath: String) -> [TerminalTab] {
        terminalTabs.filter { $0.workspacePath == workspacePath && $0.isDashboardTab }
    }

    @discardableResult
    func addDashboardTabs(workspacePath path: String, scripts: [String], labels: [String]) -> Bool {
        let resolved = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.workspacePathExists(resolved), !scripts.isEmpty, scripts.count == labels.count else { return false }
        addProject(path: resolved, select: false)
        for (index, script) in scripts.enumerated() {
            let command = startupCommandForScript(script: script, workspacePath: resolved)
            let title = labels[index]
            let tab = TerminalTab(
                title: title,
                workspacePath: resolved,
                initialCommand: command,
                isDashboardTab: true
            )
            terminalTabs.append(tab)
        }
        selectedDashboardViewPath = resolved
        if let first = terminalTabs.first(where: { $0.workspacePath == resolved && $0.isDashboardTab }) {
            selectedTerminalID = first.id
            selectedTabID = nil
            selectedTasksViewPath = nil
            selectedAddProjectView = false
            selectedProjectPath = resolved
        }
        return true
    }

    func closeDashboardTabs(workspacePath path: String) {
        let idsToClose = terminalTabs.filter { $0.workspacePath == path && $0.isDashboardTab }.map(\.id)
        for id in idsToClose {
            closeTerminalTab(id)
        }
    }

    func closeTab(_ id: UUID) {
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            let tabToClose = tabs[index]
            if let taskID = tabToClose.linkedTaskID {
                let linkedTask = ProjectTasksStorage.task(workspacePath: tabToClose.workspacePath, id: taskID)
                if linkedTask?.taskState != .completed {
                    ProjectTasksStorage.clearAgentTab(workspacePath: tabToClose.workspacePath, taskID: taskID)
                }
            }
            recentlyClosedTabs.append(tabToClose.toSaved())
            if recentlyClosedTabs.count > Self.maxRecentlyClosedTabs {
                recentlyClosedTabs.removeFirst()
            }
            let wasSelected = selectedTabID == id
            let closedProjectPath = tabToClose.workspacePath
            tabs.remove(at: index)
            tabSubscriptions[id] = nil
            linkedTaskStatusSignatures[id] = nil
            if wasSelected {
                if let replacement = tabs.first(where: { $0.workspacePath == closedProjectPath }) {
                    selectedTabID = replacement.id
                    selectedTerminalID = nil
                    selectedTasksViewPath = nil
                    selectedProjectPath = replacement.workspacePath
                    selectedAddProjectView = false
                } else if let firstTerminal = terminalTabs.first(where: { $0.workspacePath == closedProjectPath }) {
                    selectedTabID = nil
                    selectedTerminalID = firstTerminal.id
                    selectedTasksViewPath = nil
                    selectedProjectPath = closedProjectPath
                    selectedAddProjectView = false
                } else {
                    selectedTabID = nil
                    selectedTerminalID = nil
                    selectedTasksViewPath = (selectedTasksViewPath == closedProjectPath ? closedProjectPath : selectedTasksViewPath)
                    selectedProjectPath = closedProjectPath
                }
            }
            reconcileSelection(preferredProjectPath: closedProjectPath)
        }
    }

    func removeProject(_ path: String) {
        let toClose = tabs.filter { $0.workspacePath == path }
        for tab in toClose {
            if let taskID = tab.linkedTaskID {
                let linkedTask = ProjectTasksStorage.task(workspacePath: path, id: taskID)
                if linkedTask?.taskState != .completed {
                    ProjectTasksStorage.clearAgentTab(workspacePath: path, taskID: taskID)
                }
            }
            recentlyClosedTabs.append(tab.toSaved())
            if recentlyClosedTabs.count > Self.maxRecentlyClosedTabs {
                recentlyClosedTabs.removeFirst()
            }
            tabSubscriptions[tab.id] = nil
            linkedTaskStatusSignatures[tab.id] = nil
        }
        let selectedProjectWasRemoved = selectedProjectPath == path
        tabs.removeAll { $0.workspacePath == path }
        terminalTabs.removeAll { $0.workspacePath == path }
        projects.removeAll { $0.path == path }

        if selectedProjectWasRemoved {
            selectedProjectPath = nil
        }
        if selectedDashboardViewPath == path {
            selectedDashboardViewPath = nil
        }
        if selectedTasksViewPath == path {
            selectedTasksViewPath = nil
        }
        if let activeTab, activeTab.workspacePath == path {
            selectedTabID = nil
        }
        if let activeTerminal = activeTerminalTab, activeTerminal.workspacePath == path {
            selectedTerminalID = nil
        }
        reconcileSelection()
    }

    func reopenLastClosedTab() -> Bool {
        guard let saved = recentlyClosedTabs.popLast() else { return false }
        guard saved.linkedTaskID != nil else { return false }
        guard Self.workspacePathExists(saved.workspacePath) else { return false }
        addProject(path: saved.workspacePath, select: true)
        let tab = AgentTab(from: saved)
        tabs.append(tab)
        observe(tab)
        if let taskID = tab.linkedTaskID {
            ProjectTasksStorage.assignAgentTab(workspacePath: tab.workspacePath, taskID: taskID, agentTabID: tab.id)
        }
        return selectAgentTab(id: tab.id)
    }

    func reopenLinkedTaskTab(workspacePath: String, taskID: UUID, preferredTabID: UUID? = nil) -> Bool {
        let matchIndex = recentlyClosedTabs.indices.reversed().first { index in
            let saved = recentlyClosedTabs[index]
            guard saved.workspacePath == workspacePath, saved.linkedTaskID == taskID else { return false }
            return preferredTabID == nil || saved.id == preferredTabID
        }
        guard let matchIndex else { return false }

        let saved = recentlyClosedTabs.remove(at: matchIndex)
        guard Self.workspacePathExists(saved.workspacePath) else { return false }
        addProject(path: saved.workspacePath, select: true)
        let tab = AgentTab(from: saved)
        tabs.append(tab)
        observe(tab)
        ProjectTasksStorage.assignAgentTab(workspacePath: saved.workspacePath, taskID: taskID, agentTabID: tab.id)
        return selectAgentTab(id: tab.id)
    }

    private func bindTabChanges() {
        tabs.forEach(observe)
    }

    private func updateRunningAgentCount() {
        let count = tabs.filter(\.isRunning).count
        if runningAgentCount != count {
            runningAgentCount = count
        }
    }

    private func observe(_ tab: AgentTab) {
        guard tabSubscriptions[tab.id] == nil else { return }
        linkedTaskStatusSignatures[tab.id] = linkedTaskStatusSignature(for: tab)
        tabSubscriptions[tab.id] = tab.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleSaveState()
                self.updateRunningAgentCount()
                self.tabStateDidChange.send()
                let previousStatus = self.linkedTaskStatusSignatures[tab.id]
                let currentStatus = self.linkedTaskStatusSignature(for: tab)
                self.linkedTaskStatusSignatures[tab.id] = currentStatus
                if self.selectedTasksViewPath == tab.workspacePath,
                   previousStatus != currentStatus,
                   currentStatus != nil {
                    self.objectWillChange.send()
                }
            }
    }

    private func linkedTaskStatusSignature(for tab: AgentTab) -> LinkedTaskStatusSignature? {
        guard let linkedTaskID = tab.linkedTaskID else { return nil }
        return LinkedTaskStatusSignature(
            linkedTaskID: linkedTaskID,
            isRunning: tab.isRunning,
            lastTurnState: tab.turns.last?.displayState
        )
    }

    private func reconcileSelection(preferredProjectPath: String? = nil) {
        let validProjectPaths = Set(projects.map(\.path))
        let validTabIDs = Set(tabs.map(\.id))
        let validTerminalIDs = Set(terminalTabs.map(\.id))

        if let selectedTabID, !validTabIDs.contains(selectedTabID) {
            self.selectedTabID = nil
        }
        if let selectedTerminalID, !validTerminalIDs.contains(selectedTerminalID) {
            self.selectedTerminalID = nil
        }
        if let selectedProjectPath, !validProjectPaths.contains(selectedProjectPath) {
            self.selectedProjectPath = nil
        }

        if let activeTab {
            selectedProjectPath = activeTab.workspacePath
            return
        }
        if let activeTerminalTab {
            selectedProjectPath = activeTerminalTab.workspacePath
            return
        }

        if let preferredProjectPath, validProjectPaths.contains(preferredProjectPath) {
            selectedProjectPath = preferredProjectPath
            if activeTab == nil, activeTerminalTab == nil, selectedTasksViewPath != preferredProjectPath {
                selectedTasksViewPath = preferredProjectPath
            }
            return
        }

        if selectedProjectPath == nil {
            selectedProjectPath = projects.first?.path
        }

        if let path = selectedProjectPath, activeTab == nil, activeTerminalTab == nil, selectedTasksViewPath != path {
            selectedTasksViewPath = path
        }
    }

    private static func mergeProjects(savedProjects: [ProjectState], tabProjects: [ProjectState]) -> [ProjectState] {
        var merged: [ProjectState] = []
        for project in savedProjects + tabProjects where !project.path.isEmpty {
            if let existingIndex = merged.firstIndex(where: { $0.path == project.path }) {
                if merged[existingIndex].source == .discovered && project.source == .manual {
                    merged[existingIndex] = project
                }
            } else {
                merged.append(project)
            }
        }
        return merged
    }

}
