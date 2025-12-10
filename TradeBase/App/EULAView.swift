//
//  EULAView.swift
//  TradeBase
//
//  Created by Alex Walters on 09/12/2025.
//


import SwiftUI
import Observation

struct EULAView: View {
    var appState: AppState
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Terms of Use")
                        .font(.largeTitle)
                        .bold()
                        .padding(.bottom, 8)
                    
                    Text("Please read and agree to the terms below to continue using TradeBase.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1. Content Policy")
                            .font(.headline)
                        
                        Text("TradeBase has a zero-tolerance policy for objectionable content and abusive behavior. Any user posting content that is offensive, hateful, defamatory, or illegal will have their content removed and their account permanently suspended.")
                            .font(.body)
                        
                        Text("2. User Conduct")
                            .font(.headline)
                        
                        Text("By using this app, you agree to treat all other users with respect. Harassment of any kind is strictly prohibited.")
                            .font(.body)
                        
                        Text("3. EULA Agreement")
                            .font(.headline)

                        Text("By clicking 'I Agree', you acknowledge that you have read and agree to the standard Apple End User License Agreement (EULA).")
                            .font(.body)

                        Link("Read Apple Standard EULA", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                    .padding(.vertical)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            appState.hasAcceptedEULA = true
                        }
                    }) {
                        Text("I Agree")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.top, 20)
                }
                .padding()
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
