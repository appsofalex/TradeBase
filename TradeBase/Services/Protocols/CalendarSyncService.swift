//
//  CalendarSyncService.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation

protocol CalendarSyncService {
    func requestAccess() async throws
    func export(job: Job) async throws
}
