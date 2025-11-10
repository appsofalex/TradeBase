// CertificationsSettingsView.swift
import SwiftUI
import UniformTypeIdentifiers

// Simple identifiable wrapper for document preview items.
struct PreviewItem: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
}

struct CertificationsSettingsView: View {
    @Environment(\.appState) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var showingPicker = false
    @State private var pickedURL: URL?
    @State private var showingEditor = false
    @State private var editorTitle = ""
    @State private var editorIssuer = ""
    @State private var editorYear: Int = Calendar.current.component(.year, from: Date())
    @State private var previewItem: PreviewItem?
    @State private var editingCertID: UUID? = nil

    var body: some View {
        List {
            certificationsSection

            Section {
                Button {
                    showingPicker = true
                } label: {
                    Label("Add certification", systemImage: "plus.circle.fill")
                }
                .fullWidthCardRow()
            }
        }
        .listStyle(.plain) // Make rows use the full width; we draw our own card background.
        .scrollContentBackground(.hidden)
        .background(TBTheme.gradient.ignoresSafeArea())
        .navigationTitle("Edit Certifications")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            DocumentPicker(allowedContentTypes: [.item]) { url in
                // Prepare editor with defaults from file
                pickedURL = url
                editorTitle = url.deletingPathExtension().lastPathComponent
                editorIssuer = ""
                editorYear = Calendar.current.component(.year, from: Date())
                editingCertID = nil
                showingEditor = true
            }
        }
        .sheet(isPresented: $showingEditor) {
            CertificationEditorSheet(
                navTitle: editingCertID == nil ? "New Certification" : "Edit Certification",
                initialTitle: editorTitle,
                initialIssuer: editorIssuer,
                initialYear: editorYear
            ) { title, issuer, year in
                if let editingID = editingCertID {
                    Task {
                        await state.updateCertification(id: editingID, title: title, issuer: issuer, year: year)
                        state.saveProfile()
                    }
                } else if let pickedURL {
                    Task {
                        do {
                            let storedURL = try storeDocument(from: pickedURL)
                            await state.addCertification(title: title, issuer: issuer, year: year, fileURL: storedURL)
                            state.saveProfile()
                        } catch {
                            print("File store error: \(error)")
                        }
                    }
                }
                // Reset transient state
                self.pickedURL = nil
                self.editingCertID = nil
            }
        }
        .sheet(item: $previewItem) { item in
            DocumentPreviewWithClose(url: item.url)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Sections

    private var certificationsSection: some View {
        Section {
            if state.profile.certifications.isEmpty {
                HStack {
                    Text("No certifications added yet.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .fullWidthCardRow()
            } else {
                ForEach(state.profile.certifications) { cert in
                    CertificationRow(
                        cert: cert,
                        onTap: {
                            if let url = cert.fileURL {
                                previewItem = PreviewItem(url: url)
                            }
                        },
                        onRename: { beginRename(cert) },
                        onDelete: {
                            Task {
                                await state.deleteCertification(cert)
                            }
                        }
                    )
                    .fullWidthCardRow()
                    // Provide an explicit swipe-to-delete using the standard Apple destructive red.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await state.deleteCertification(cert) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red) // Ensure default destructive red styling
                    }
                }
                .onDelete { idx in
                    for i in idx {
                        let cert = state.profile.certifications[i]
                        Task { await state.deleteCertification(cert) }
                    }
                }
            }
        } header: {
            Text("Your certifications")
                .foregroundStyle(TBTheme.offWhite)
        }
    }

    // MARK: - Actions

    private func beginRename(_ cert: Certification) {
        editorTitle = cert.title
        editorIssuer = cert.issuer
        editorYear = cert.year
        pickedURL = cert.fileURL
        editingCertID = cert.id
        showingEditor = true
    }

    private func storeDocument(from url: URL) throws -> URL {
        let fm = FileManager.default
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var dest = docs.appendingPathComponent("\(base).\(ext)")
        // Ensure unique filename
        var i = 1
        while fm.fileExists(atPath: dest.path) {
            dest = docs.appendingPathComponent("\(base)-\(i).\(ext)")
            i += 1
        }
        // Start accessing if security-scoped
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        try fm.copyItem(at: url, to: dest)

        // Apply encryption-at-rest to the stored document
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: dest.path)

        // If you want strictly local (no iCloud backup), uncomment:
        // var rvs = URLResourceValues()
        // rvs.isExcludedFromBackup = true
        // try? dest.setResourceValues(rvs)

        return dest
    }
}

