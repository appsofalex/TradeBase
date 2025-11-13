//
//  RolePickerView.swift
//  TradeBase
//

import SwiftUI

struct RolePickerView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer(minLength: 40)
                Text("Welcome to TradeBase")
                    .font(.largeTitle.bold())
                    .foregroundStyle(TBTheme.offWhite)

                Text("Choose how you’d like to use the app:")
                    .foregroundStyle(TBTheme.offWhiteSecondary)

                VStack(spacing: 16) {
                    roleButton(
                        title: "I’m a tradesperson",
                        subtitle: "Win more work, stay organised, grow faster",
                        systemImage: "wrench.and.screwdriver.fill"
                    ) {
                        state.selectedRole = .tradesperson
                    }

                    roleButton(
                        title: "I need a tradesperson",
                        subtitle: "Describe the job, get quotes, hire fast",
                        systemImage: "person.fill.questionmark"
                    ) {
                        state.selectedRole = .customer
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
    }

    private func roleButton(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(TBTheme.brand)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(TBTheme.brand.opacity(0.15)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(TBTheme.title)
                    Text(subtitle).font(.subheadline).foregroundStyle(TBTheme.subtext)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(TBTheme.subtext)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

