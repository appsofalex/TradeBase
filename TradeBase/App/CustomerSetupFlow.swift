// CustomerSetupFlow.swift
import SwiftUI

struct CustomerSetupFlow: View {
    @Environment(\.appState) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 0
    @State private var name: String = ""
    @State private var city: String = ""
    @State private var bio: String = ""
    @State private var hasAvatar: Bool = false

    // Direction for step-to-step animations
    @State private var stepDirection: AppState.NavDirection = .forward

    private var canContinue: Bool {
        switch step {
        case 0:
            let validName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return validName
        case 1:
            return !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2:
            return true // bio optional
        case 3:
            // Avatar is required on final step
            return hasAvatar
        default:
            return false
        }
    }

    private var stepTransition: AnyTransition {
        switch stepDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .back:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { idx in
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

                ZStack {
                    if step == 0 {
                        nameStep
                            .transition(stepTransition)
                            .id(0)
                    }
                    if step == 1 {
                        cityStep
                            .transition(stepTransition)
                            .id(1)
                    }
                    if step == 2 {
                        bioStep
                            .transition(stepTransition)
                            .id(2)
                    }
                    if step == 3 {
                        avatarStep
                            .transition(stepTransition)
                            .id(3)
                    }
                }
                .padding(.horizontal, 24)
                .animation(.easeInOut(duration: 0.28), value: step)

                Spacer()

                HStack(spacing: 12) {
                    if step > 0 {
                        PillButton(title: "Back", style: .light) {
                            stepDirection = .back
                            withAnimation(.easeInOut(duration: 0.28)) { step -= 1 }
                        }
                    }
                    PillButton(title: step == 3 ? "Finish" : "Continue", style: .brand) {
                        Task { await continueTapped() }
                    }
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.6)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            name = ""
            city = state.profile.city ?? ""
            bio = ""
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

    private var nameStep: some View {
        VStack(spacing: 16) {
            PillTextField(
                systemImage: "person",
                placeholder: "Your name",
                text: $name
            )
            .textInputAutocapitalization(.words)

            Text("This appears on your requests and messages.")
                .font(.footnote)
                .foregroundStyle(TBTheme.offWhiteSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var cityStep: some View {
        VStack(spacing: 16) {
            PillTextField(systemImage: "mappin.and.ellipse", placeholder: "Your city (e.g. London)", text: $city)
                .textInputAutocapitalization(.words)
            Text("We’ll use this to show you nearby tradespeople.")
                .font(.footnote)
                .foregroundStyle(TBTheme.offWhiteSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
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

    private var titleForStep: String {
        switch step {
        case 0: return "Let’s set you up"
        case 1: return "Where are you?"
        case 2: return "Your bio"
        case 3: return "Add your photo"
        default: return ""
        }
    }

    private var subtitleForStep: String {
        switch step {
        case 0: return "Tell us your name so tradespeople know who they’re chatting with."
        case 1: return "Add your city to match with local tradespeople."
        case 2: return "Add a short intro to help tradespeople get to know you."
        case 3: return "Add a clear profile photo. You can change it later."
        default: return ""
        }
    }

    private func finish() {
        state.navigationDirection = .forward

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)

        state.profile.name = trimmedName
        state.profile.city = trimmedCity.isEmpty ? nil : trimmedCity
        state.profile.bio = String(trimmedBio.prefix(80))
        state.profile.username = nil // usernames not used for customers

        state.saveProfile()

        state.completeCustomerSetup()
        dismiss()
    }

    // MARK: - Continue action

    private func continueTapped() async {
        switch step {
        case 0, 1, 2:
            await MainActor.run {
                stepDirection = .forward
                withAnimation(.easeInOut(duration: 0.28)) { step += 1 }
            }
        case 3:
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
