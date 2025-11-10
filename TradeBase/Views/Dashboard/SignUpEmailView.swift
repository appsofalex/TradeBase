//
//  SignUpEmailView.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct SignUpEmailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()

            // Main content
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 24)
                    Text("Create your account")
                        .font(.largeTitle.bold())
                        .foregroundStyle(TBTheme.offWhite)
                        .padding(.top, 12)

                    Text("Join TradeBase to find work, manage jobs, and get paid.")
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(spacing: 14) {
                        PillTextField(systemImage: "person", placeholder: "Name", text: $name)
                        PillTextField(systemImage: "envelope", placeholder: "Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        PillSecureField(systemImage: "key", placeholder: "Password", text: $password)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                    if let error {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }

                    PillButton(title: "Create account", style: .light) {
                        Task { await submit() }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    // Guest option from email sign-up screen
                    Button {
                        Task {
                            isLoading = true
                            await state.continueAsGuest()
                            isLoading = false
                            dismiss()
                        }
                    } label: {
                        Text("Skip sign up for now")
                            .foregroundStyle(TBTheme.offWhite)
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 6)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 24)

                    VStack(spacing: 8) {
                        Text("Already have an account?")
                            .foregroundStyle(TBTheme.offWhiteSecondary)
                        Button("Log in") { dismiss() }
                            .foregroundStyle(TBTheme.offWhite)
                            .font(.headline)
                    }
                    .padding(.bottom, 24)
                }
            }
            .overlay { if isLoading { ProgressView().controlSize(.large) } }

            // Top-right close button
            .overlay(alignment: .topTrailing) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(TBTheme.offWhite)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.28))
                                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
            }
        }
        // Ensure no system back button/title appears if embedded in a NavigationStack
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EmptyView() }
            ToolbarItem(placement: .principal) { EmptyView() }
        }
    }

    private func submit() async {
        error = nil
        isLoading = true
        do {
            try await state.signUp(name: name, email: email, password: password) // sets .forward
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
