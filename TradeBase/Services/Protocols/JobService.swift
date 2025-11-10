//
//  JobService.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation

protocol JobService {
    func upcomingJobs() async throws -> [Job]
}
