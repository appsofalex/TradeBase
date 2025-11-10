extension UserProfile {
    var yearsInIndustry: Int? {
        guard let startYear else { return nil }
        let thisYear = Calendar.current.component(.year, from: Date())
        let years = thisYear - startYear
        return years > 0 ? years : nil
    }
}
