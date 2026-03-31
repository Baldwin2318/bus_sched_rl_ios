//
//  NearbyETABackground.swift
//  bus_sched_rl_ios
//
//  Created by Baldwin Kiel Malabanan on 2026-03-30.
//

import SwiftUI

struct NearbyETABackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.20, green: 0.53, blue: 0.89).opacity(0.14))
                .frame(width: 260, height: 260)
                .offset(x: 130, y: -280)
                .blur(radius: 8)

            Circle()
                .fill(Color(red: 0.96, green: 0.63, blue: 0.18).opacity(0.12))
                .frame(width: 220, height: 220)
                .offset(x: -150, y: 290)
                .blur(radius: 10)
        }
        .ignoresSafeArea()
    }
}
