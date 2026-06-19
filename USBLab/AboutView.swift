//
//  AboutView.swift
//  USBLab
//
//  Created by Eugenio de Frutos Sanchez on 10/12/25.
//

import SwiftUI

struct AboutView: View {
    @Binding var showing: Bool

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {

            Image("USBLabLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 80)
                .padding(.top, 8)

            Text("USBLab")
                .font(.title2)
                .fontWeight(.bold)

            Text("Versión \(appVersion) (build \(buildNumber))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("by EDF Developer")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            VStack(spacing: 6) {
                Text("Herramienta de diagnóstico y pruebas de unidades USB en macOS.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)

                if let url = URL(string: "https://edefrutos.me") {
                    Link("Website: edefrutos.me", destination: url)
                        .font(.footnote)
                }
            }

            Spacer()

            Button("Cerrar") {
                showing = false
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 420, height: 320)
    }
}

#Preview {
    AboutView(showing: .constant(true))
}
