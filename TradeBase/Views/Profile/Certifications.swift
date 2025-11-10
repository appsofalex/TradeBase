// AppState+Certifications.swift
import Foundation

extension AppState {

    /// Create and persist a new certification, mirror to CloudKit when signed in.
    func addCertification(title: String, issuer: String, year: Int, fileURL: URL?) async {
        // Resolve a local, identity-scoped copy of the file (if provided)
        let identity = currentAuthIdentity()
        let localFileURL: URL? = {
            guard let src = fileURL else { return nil }
            return copyCertificationFileToDocuments(originalURL: src, identity: identity)
        }()

        var newCert = Certification(title: title, issuer: issuer, year: year, fileURL: localFileURL)

        // Update local state on the main actor
        await MainActor.run {
            self.profile.certifications.append(newCert)
            self.saveProfile()
        }

        // Mirror to CloudKit if we have an authenticated identity
        if let identity = identity {
            try? await cloudProfileStore.upsertCertification(newCert, fileURL: localFileURL, identity: identity)
        }
    }

    /// Update fields for an existing certification by id, mirror to CloudKit when signed in.
    func updateCertification(id: UUID, title: String, issuer: String, year: Int) async {
        var updatedCert: Certification?

        // Update local state on the main actor
        await MainActor.run {
            if let idx = self.profile.certifications.firstIndex(where: { $0.id == id }) {
                var cert = self.profile.certifications[idx]
                cert.title = title
                cert.issuer = issuer
                cert.year = year
                self.profile.certifications[idx] = cert
                updatedCert = cert
                self.saveProfile()
            }
        }

        // Mirror to CloudKit if we have an authenticated identity
        if let cert = updatedCert, let identity = currentAuthIdentity() {
            try? await cloudProfileStore.upsertCertification(cert, fileURL: cert.fileURL, identity: identity)
        }
    }

    /// Delete a certification locally (and its local file), mirror deletion to CloudKit when signed in.
    func deleteCertification(_ cert: Certification) async {
        // Remove local file if we stored one
        if let url = cert.fileURL, url.isFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        // Update local state on the main actor
        await MainActor.run {
            self.profile.certifications.removeAll { $0.id == cert.id }
            self.saveProfile()
        }

        // Mirror to CloudKit if we have an authenticated identity
        if let identity = currentAuthIdentity() {
            // Identity isn't needed for delete by id, but we check availability for parity with other ops
            _ = identity
            try? await cloudProfileStore.deleteCertification(id: cert.id)
        }
    }

    // MARK: - Private helpers

    /// Copy a certification attachment into the app's Documents directory using an identity-prefixed, unique filename.
    /// This keeps files separated per account while remaining compatible with Certification's encoding (which stores only lastPathComponent).
    private func copyCertificationFileToDocuments(originalURL: URL, identity: String?) -> URL? {
        let fm = FileManager.default
        let docs = (try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory

        // Sanitize identity for filesystem usage and prefix the filename.
        let idPrefix = sanitizeIdentity(identity ?? "guest")
        let ext = originalURL.pathExtension.isEmpty ? "bin" : originalURL.pathExtension
        let uniqueName = "cert-\(idPrefix)-\(UUID().uuidString).\(ext)"
        var dest = docs.appendingPathComponent(uniqueName)

        do {
            // If the original is not a file URL or not accessible, bail.
            guard originalURL.isFileURL else { return nil }

            // Copy (not move) so we keep a stable local copy even if the original is a temp URL.
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: dest)
            }
            try fm.copyItem(at: originalURL, to: dest)

            // Harden and avoid backups
            try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: dest.path)
            var rvs = URLResourceValues()
            rvs.isExcludedFromBackup = true
            try? dest.setResourceValues(rvs)

            return dest
        } catch {
            return nil
        }
    }

    private func sanitizeIdentity(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}
