// Put this in a shared file, e.g., UI/HeaderTitle.swift
import SwiftUI

struct HeaderTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)   // match baseline with Profile
            .padding(.bottom, 2)
    }
}
