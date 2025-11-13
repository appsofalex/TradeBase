// TradespersonSetupFlow.swift
import SwiftUI

struct TradespersonSetupFlow: View {
    @Environment(\.appState) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 0
    @State private var name: String = ""
    @State private var bio: String = ""
    @State private var primaryTrade: TradeType = .electrician
    @State private var selectedSkills: Set<String> = []
    @State private var newSkill: String = ""
    @State private var hasAvatar: Bool = false

    // Direction for step-to-step animations
    @State private var stepDirection: AppState.NavDirection = .forward

    private var catalogSkills: [String] {
        SkillsCatalog.skills(for: primaryTrade)
    }
    private var customSkills: [String] {
        selectedSkills.filter { !catalogSkills.contains($0) }.sorted()
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            let validName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return validName
        case 1:
            return true // trade is always selected
        case 2:
            return true // skills optional
        case 3:
            return true // bio optional
        case 4:
            return hasAvatar // avatar required
        default:
            return false
        }
    }

    private var stepTransition: AnyTransition {
        switch stepDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .back:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()
            VStack(spacing: 20) {
                // Step dots (5 steps)
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { idx in
                        Circle()
                            .fill(idx <= step ? TBTheme.brand : Color.white.opacity(0.25))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 12)

                Text(titleForStep)
                    .font(.largeTitle.bold())
                    .foregroundStyle(TBTheme.offWhite)
                    .padding(.top, 8)

                Text(subtitleForStep)
                    .foregroundStyle(TBTheme.offWhiteSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Only render the active step view
                Group {
                    switch step {
                    case 0: nameStep
                    case 1: tradeStep
                    case 2: skillsStep
                    case 3: bioStep
                    case 4: avatarStep
                    default: EmptyView()
                    }
                }
                .transition(stepTransition)
                .animation(.easeInOut(duration: 0.28), value: step)
                .padding(.horizontal, horizontalPaddingForStep)

                Spacer()

                HStack(spacing: 12) {
                    if step > 0 {
                        PillButton(title: "Back", style: .light) {
                            stepDirection = .back
                            withAnimation(.easeInOut(duration: 0.28)) { step -= 1 }
                        }
                    }
                    PillButton(title: step == 4 ? "Finish" : "Continue", style: .brand) {
                        Task { await continueTapped() }
                    }
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.6)
                    .zIndex(2)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            // Prefill from any existing profile data — but avoid generic placeholder.
            let existing = state.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let isGenericPlaceholder = existing.caseInsensitiveCompare("Your Name") == .orderedSame
            name = isGenericPlaceholder ? "" : existing

            bio = state.profile.bio
            primaryTrade = state.profile.tradeTypes.first ?? .electrician
            selectedSkills = Set(state.profile.skills)
            hasAvatar = currentHasAvatar()
        }
        .interactiveDismissDisabled(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        state.signOut()
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
        }
        .onChange(of: state.profile.avatarURL) { _, _ in
            hasAvatar = currentHasAvatar()
        }
    }

    // MARK: - Steps

    private var nameStep: some View {
        VStack(spacing: 16) {
            PillTextField(
                systemImage: "person",
                placeholder: "Your name",
                text: $name
            )
            .textInputAutocapitalization(.words)

            Text("This is shown to customers in chats and on your profile.")
                .font(.footnote)
                .foregroundStyle(TBTheme.offWhiteSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var tradeStep: some View {
        VStack(spacing: 12) {
            Text("Industry")
                .font(.headline)
                .foregroundStyle(TBTheme.offWhite)
                .frame(maxWidth: .infinity, alignment: .leading)

            RoundedCard {
                HStack {
                    Text("Primary trade")
                        .foregroundStyle(TBTheme.title)
                    Spacer()
                    Menu {
                        ForEach(TradeType.allCases) { trade in
                            Button(trade.displayName) { primaryTrade = trade }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(primaryTrade.displayName)
                                .fontWeight(.semibold)
                                .foregroundStyle(TBTheme.brand)
                            Image(systemName: "chevron.down")
                                .foregroundStyle(TBTheme.brand)
                        }
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.automatic)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
            }
        }
    }

    private var skillsStep: some View {
        Form {
            Section {
                if catalogSkills.isEmpty {
                    Text("No predefined skills yet. Add your own below.")
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(catalogSkills, id: \.self) { skill in
                        Toggle(skill, isOn: Binding(
                            get: { selectedSkills.contains(skill) },
                            set: { isOn in
                                if isOn { selectedSkills.insert(skill) } else { selectedSkills.remove(skill) }
                            }
                        ))
                        .listRowBackground(Color.clear)
                    }
                }
            } header: {
                Text("Recommended skills").foregroundStyle(TBTheme.offWhite)
            }

            Section {
                if customSkills.isEmpty {
                    Text("Add any services you offer that aren’t listed above.")
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(customSkills, id: \.self) { skill in
                        Toggle(skill, isOn: Binding(
                            get: { selectedSkills.contains(skill) },
                            set: { isOn in
                                if isOn { selectedSkills.insert(skill) } else { selectedSkills.remove(skill) }
                            }
                        ))
                        .swipeActions {
                            Button(role: .destructive) {
                                selectedSkills.remove(skill)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                HStack {
                    TextField("Add custom skill", text: $newSkill)
                        .textInputAutocapitalization(.words)
                    Button {
                        addCustomSkill()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(TBTheme.brand)
                    }
                    .disabled(newSkill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .listRowBackground(Color.clear)
            } header: {
                Text("Custom skills").foregroundStyle(TBTheme.offWhite)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(TBTheme.gradient.ignoresSafeArea())
        // Ensure every row uses a transparent background to avoid seams
        .onAppear {
            UITableView.appearance().backgroundColor = .clear
        }
        .onDisappear {
            // Optionally reset for other screens if needed
            UITableView.appearance().backgroundColor = nil
        }
        .onChange(of: primaryTrade) { _, _ in
            // Keep custom skills; recommended selection persists
        }
        // Remove negative top padding to avoid revealing a header seam
        // .padding(.top, -8)  // removed
    }

    private var bioStep: some View {
        VStack(spacing: 8) {
            PillTextField(
                systemImage: "text.alignleft",
                placeholder: "Short bio (optional)",
                text: $bio
            )
            .textInputAutocapitalization(.sentences)
            .onChange(of: bio) { _, newValue in
                if newValue.count > 80 {
                    bio = String(newValue.prefix(80))
                }
            }

            HStack {
                Spacer()
                Text("\(bio.count)/80")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(TBTheme.offWhiteSecondary)
            }

            Text("You can edit your bio anytime from your Profile.")
                .font(.footnote)
                .foregroundStyle(TBTheme.offWhiteSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var avatarStep: some View {
        AvatarSetupStep(hasAvatar: $hasAvatar)
    }

    // MARK: - Titles

    private var titleForStep: String {
        switch step {
        case 0: return "Let’s set up your profile"
        case 1: return "Your main trade"
        case 2: return "Your skills"
        case 3: return "Your bio"
        case 4: return "Add your photo"
        default: return ""
        }
    }

    private var subtitleForStep: String {
        switch step {
        case 0: return "Start with your name or business name."
        case 1: return "Pick the trade you primarily work in."
        case 2: return "Choose services you offer. Add your own if needed."
        case 3: return "Add a short intro to help customers get to know you."
        case 4: return "Add a clear profile photo. You can change it later."
        default: return ""
        }
    }

    private var horizontalPaddingForStep: CGFloat {
        step == 2 ? 0 : 24
    }

    // MARK: - Actions

    private func addCustomSkill() {
        let trimmed = newSkill.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedSkills.insert(trimmed)
        newSkill = ""
    }

    private func finish() {
        state.navigationDirection = .forward
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)

        state.completeTradespersonSetup(
            name: trimmedName,
            primaryTrade: primaryTrade,
            skills: Array(selectedSkills),
            bio: String(trimmedBio.prefix(80))
        )
        dismiss()
    }

    private func continueTapped() async {
        switch step {
        case 0, 1, 2, 3:
            await MainActor.run {
                stepDirection = .forward
                withAnimation(.easeInOut(duration: 0.28)) { step += 1 }
            }
        case 4:
            guard hasAvatar else { return }
            await MainActor.run { finish() }
        default:
            break
        }
    }

    // MARK: - Avatar presence

    private func currentHasAvatar() -> Bool {
        guard let url = state.profile.avatarURL else { return false }
        if url.isFileURL {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return true
    }
}

// MARK: - Lightweight visual helpers used in setup

private struct RoundedCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct RoundedListCard<Rows: View>: View {
    @ViewBuilder var rows: Rows
    var body: some View {
        rows
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
