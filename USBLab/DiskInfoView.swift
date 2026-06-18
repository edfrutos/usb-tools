//
//  DiskInfoView.swift
//  USBLab
//
//  Created by Eugenio de Frutos Sanchez on 10/12/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DiskInfoView: View {
    @Binding var showing: Bool
    @State private var input: String
    @State private var resolvedDevice: String = ""
    @State private var report: String = ""
    @State private var isRunning: Bool = false

    init(showing: Binding<Bool>, initialInput: String) {
        _showing = showing
        _input = State(initialValue: initialInput)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Información avanzada del disco")
                .font(.title2)
                .bold()

            Text("Introduce un volumen (/Volumes/USB_Limpio) o un dispositivo (/dev/disk8). USBLab intentará resolver el nodo de dispositivo para SMART.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Text("Destino:")
                TextField("/Volumes/USB_Limpio o /dev/diskX", text: $input)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            HStack {
                Button("Actualizar informe") {
                    generateReport()
                }
                .disabled(isRunning || input.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Copiar informe") {
                    copyToClipboard()
                }
                .disabled(report.isEmpty)

                Button("Guardar como…") {
                    saveToFile()
                }
                .disabled(report.isEmpty)

                Spacer()

                Button("Cerrar") {
                    showing = false
                }
                .keyboardShortcut(.cancelAction)
            }

            GroupBox(label: Text("Informe")) {
                ScrollView {
                    Text(report.isEmpty ? "Pulsa “Actualizar informe” para generar los datos." : report)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                        .textSelection(.enabled)
                }
            }

            if isRunning {
                HStack {
                    ProgressView()
                    Text("Generando informe…").foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            if !input.isEmpty {
                generateReport()
            }
        }
    }

    // MARK: - Lógica de informe

    private func generateReport() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isRunning = true
        report = "Generando informe para \(trimmed)…\n\n"
        resolvedDevice = ""

        DispatchQueue.global(qos: .userInitiated).async {
            var out = ""
            let now = ISO8601DateFormatter().string(from: Date())

            out += "========================================\n"
            out += " USBLab — Informe avanzado de disco\n"
            out += " Fecha: \(now)\n"
            out += " Entrada usuario: \(trimmed)\n"
            out += "========================================\n\n"

            // 1) diskutil info
            out += ">>> diskutil info \(trimmed)\n\n"
            let info = runCommand("/usr/sbin/diskutil", ["info", trimmed])
            out += info + "\n\n"

            if let dev = resolveDeviceNode(from: info) {
                resolvedDevice = dev
                out += "Device Node resuelto para SMART: \(dev)\n\n"
            }

            // 2) diskutil verifyVolume (si es volumen)
            if !trimmed.hasPrefix("/dev/") {
                out += ">>> diskutil verifyVolume \(trimmed)\n\n"
                let verify = runCommand("/usr/sbin/diskutil", ["verifyVolume", trimmed])
                out += verify + "\n\n"
            }

            // 3) SMART
            if let smartPath = findSmartctl() {
                let devForSmart: String?
                if trimmed.hasPrefix("/dev/") {
                    devForSmart = trimmed
                } else {
                    devForSmart = resolvedDevice.isEmpty ? nil : resolvedDevice
                }

                if let devNode = devForSmart {
                    out += ">>> \(smartPath) -a \(devNode)\n\n"
                    let smart = runCommand(smartPath, ["-a", devNode])
                    out += smart + "\n\n"
                } else {
                    out += ">>> smartctl disponible, pero no se ha podido resolver un /dev/diskX válido.\n\n"
                }
            } else {
                out += ">>> smartctl no encontrado (instala smartmontools con Homebrew si quieres SMART).\n\n"
            }

            DispatchQueue.main.async {
                self.report = out
                self.isRunning = false
            }
        }
    }

    // Ejecutar comando y devolver stdout+stderr
    private func runCommand(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return "ERROR al ejecutar \(launchPath): \(error.localizedDescription)\n"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // Busca smartctl en rutas típicas
    private func findSmartctl() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/sbin/smartctl",
            "/usr/local/sbin/smartctl",
            "/usr/sbin/smartctl"
        ]
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    // resolveDeviceNode(from:) viene de USBLabUtils.swift (función libre del módulo).

    // MARK: - Utilidades UI

    private func copyToClipboard() {
        guard !report.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(report, forType: .string)
    }

    private func saveToFile() {
        guard !report.isEmpty else { return }
        let panel = NSSavePanel()

        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "USBLab_DiskInfo.txt"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Error al guardar informe: \(error)")
            }
        }
    }
}

#Preview {
    DiskInfoView(showing: .constant(true),
                 initialInput: "/Volumes/USB_Limpio")
}
