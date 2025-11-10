//
//  TradeBaseApp.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import GoogleSignIn
import CloudKit
import UIKit
import Observation

final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var state: AppState?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) is CKQueryNotification else {
            completionHandler(.noData)
            return
        }

        Task {
            await state?.refreshCommunity(city: nil)
            await state?.refreshLeads()
            completionHandler(.newData)
        }
    }
}

@main
struct TradeBaseApp: App {
    @State private var state = AppState()
    @State private var customerListings = CustomerJobListingStore()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let largeAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor(TBTheme.offWhite)]
        let smallAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor(TBTheme.offWhite)]
        let navBar = UINavigationBar.appearance()
        navBar.largeTitleTextAttributes = largeAttrs
        navBar.titleTextAttributes = smallAttrs
        UIBarButtonItem.appearance().tintColor = UIColor(TBTheme.offWhite)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Primary injection via environment (for @Observable classes)
                .environment(state)
                // Also inject via custom EnvironmentValues key so views using \.appState get the same instance.
                .environment(\.appState, state)
                // Other custom environment injections
                .environment(\.customerJobListingStore, customerListings)
                .task {
                    do {
                        await state.load()
                        await state.ensureCommunitySubscription(city: nil as String?)
                        try await state.ensureLeadsSubscription()
                    } catch {
                        print("App initialization error: \(error)")
                    }
                    print("[Boot] Using leads service: \(type(of: state.jobLeadService))")
                    let identity = state.currentAuthIdentity()
                    customerListings.setIdentity(identity)
                }
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    if url.scheme?.lowercased() == "tradebase",
                       url.host?.lowercased() == "auth" {
                        TwitterXAuthService.handleRedirectURL(url)
                        return
                    }
                    if url.scheme?.lowercased() == "tradebase" {
                        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                        let path = comps?.path ?? ""
                        let parts = path.split(separator: "/").map(String.init)
                        if parts.count >= 2, parts[0].lowercased() == "job",
                           let uuid = UUID(uuidString: parts[1]) {
                            state.pendingJobResumeID = uuid
                            // Navigate to My Jobs and select Drafts tab
                            state.preferredMyJobsStatus = JobListingStatus.draft
                            state.navigateToMyJobsSignal &+= 1
                            return
                        }
                    }
                }
                .onAppear {
                    appDelegate.state = state
                    UIApplication.shared.registerForRemoteNotifications()
                }
                .onChange(of: state.selectedRole) {
                    let identity = state.currentAuthIdentity()
                    customerListings.setIdentity(identity)
                }
                .onChange(of: state.authProvider) {
                    let identity = state.currentAuthIdentity()
                    customerListings.setIdentity(identity)
                }
        }
    }
}
