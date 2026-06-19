import SwiftUI
import AppKit

struct ContentView: View {

    // Parámetros de prueba
    @State private var volumePath: String = "/Volumes/USB_Limpio"
    @State private var smallSizeGiB: String = "4"
    @State private var cycles: String = "5"
    @State private var surfacePercent: String = "20"

    // Estado de la UI
    @State private var logText: String = ""
    @State private var isRunning: Bool = false
    @State private var inputPipe: Pipe? = nil
    @State private var activeProcess: Process? = nil   // T2.1 – referencia para cancelar
    @State private var lastResult: TestResult? = nil   // T2.2 – último resultado JSON
    @State private var envReady: Bool = false
    @State private var showingDiskInfo: Bool = false
    @State private var showingVolumePicker: Bool = false

    private let scriptNames = [
        "usb_lab_test.sh",
        "test_reconexion.sh",
        "stress_integridad_extendido.sh",
        "test_surface_full.sh"
    ]

    private var appSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        return base.appendingPathComponent("USBLab", isDirectory: true)
    }

    private var logsDirectoryURL: URL {
        let base = FileManager.default.urls(for: .libraryDirectory,
                                            in: .userDomainMask).first!
        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("USBLab", isDirectory: true)
    }

    private var logFileURL: URL {
        logsDirectoryURL.appendingPathComponent("usb_lab.log")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Cabecera con logo
            HStack(alignment: .center, spacing: 16) {
                Image("USBLabLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Laboratorio de unidades USB")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("by EDF Developer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // PARÁMETROS
            GroupBox(label: Text("Parámetros")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Volumen:")
                        TextField("/Volumes/USB_Limpio", text: $volumePath)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button {
                            showingVolumePicker = true
                        } label: {
                            Image(systemName: "externaldrive.fill.badge.plus")
                        }
                        .help("Seleccionar volumen montado")
                    }
                    HStack {
                        Text("Tamaño pequeño (GiB):")
                        TextField("4", text: $smallSizeGiB)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 60)

                        Text("Ciclos:")
                        TextField("5", text: $cycles)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 60)

                        Text("Superficie % libre:")
                        TextField("20", text: $surfacePercent)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 60)
                    }
                }
                .padding(8)
            }

            // ACCIONES
            GroupBox(label: Text("Acciones")) {
                HStack {
                    Button("Test completo")   { runLabTest() }
                        .disabled(isRunning || !envReady)

                    Button("Solo reconexión") { runReconexionTest() }
                        .disabled(isRunning || !envReady)

                    Button("Solo stress")     { runStressTest() }
                        .disabled(isRunning || !envReady)

                    Button("Solo superficie") { runSurfaceTest() }
                        .disabled(isRunning || !envReady)

                    Button("Info disco…")     { showingDiskInfo = true }
                        .disabled(isRunning)

                    Button("Enviar ENTER")    { sendEnter() }
                        .disabled(!isRunning || inputPipe == nil)

                    // T2.1 – Cancelar proceso en curso
                    Button("Cancelar") { cancelCurrentTest() }
                        .disabled(!isRunning || activeProcess == nil)
                        .foregroundStyle(.red)

                    Spacer()

                    Button("Limpiar log") { logText = "" }
                }
                .padding(8)
            }

            // T2.2 – Panel de último resultado (visible solo cuando hay datos)
            if let res = lastResult {
                GroupBox(label: Label(res.isOK ? "Resultado — OK" : "Resultado — ERROR",
                                      systemImage: res.isOK ? "checkmark.circle.fill"
                                                            : "xmark.circle.fill")
                            .foregroundStyle(res.isOK ? .green : .red)) {
                    HStack(spacing: 24) {
                        LabeledContent("Test", value: res.test)
                        if let c = res.cycles_ok {
                            LabeledContent("Ciclos OK", value: "\(c)")
                        }
                        if let g = res.speed_gen_mb_s {
                            LabeledContent("Generación", value: "\(g) MB/s")
                        }
                        if let cp = res.speed_copy_mb_s {
                            LabeledContent("Escritura", value: "\(cp) MB/s")
                        }
                        Spacer()
                    }
                    .padding(6)
                    .font(.system(.body, design: .monospaced))
                }
            }

            // LOG
            GroupBox(label: Text("Salida / Log")) {
                ScrollView {
                    Text(logText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                        .textSelection(.enabled)
                }
            }

            HStack {
                Button("Copiar log al portapapeles") { copyLogToClipboard() }
                    .disabled(logText.isEmpty)
                Spacer()
            }

            HStack {
                if isRunning {
                    ProgressView()
                    Text("Ejecutando script…").foregroundColor(.secondary)
                } else if !envReady {
                    ProgressView()
                    Text("Preparando entorno…").foregroundColor(.secondary)
                } else {
                    Text("Listo.").foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 830, minHeight: 600)
        .onAppear { setupEnvironmentIfNeeded() }
        .sheet(isPresented: $showingDiskInfo) {
            DiskInfoView(showing: $showingDiskInfo, initialInput: volumePath)
        }
        .sheet(isPresented: $showingVolumePicker) {
            VolumePickerView(selectedPath: $volumePath, showing: $showingVolumePicker)
        }
    }

    // MARK: - Acciones de alto nivel

    private func runLabTest() {
        runScript(scriptName: "usb_lab_test.sh",
                  arguments: [volumePath, smallSizeGiB, cycles, surfacePercent],
                  title: "lab")
    }

    private func runReconexionTest() {
        runScript(scriptName: "test_reconexion.sh",
                  arguments: [volumePath, smallSizeGiB, cycles],
                  title: "reconexion")
    }

    private func runStressTest() {
        runScript(scriptName: "stress_integridad_extendido.sh",
                  arguments: [volumePath, smallSizeGiB, cycles],
                  title: "stress")
    }

    private func runSurfaceTest() {
        runScript(scriptName: "test_surface_full.sh",
                  arguments: [volumePath, surfacePercent],
                  title: "surface")
    }

    // MARK: - T2.1 – Cancelar

    private func cancelCurrentTest() {
        activeProcess?.terminate()
        activeProcess = nil
        isRunning = false
        inputPipe = nil
        appendLog("\n⚠ Test cancelado por el usuario.\n=========================================\n\n")
    }

    // MARK: - Preparación de entorno

    private func setupEnvironmentIfNeeded() {
        guard !envReady else { return }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)

            for name in scriptNames {
                guard let bundlePath = Bundle.main.path(forResource: name, ofType: nil) else { continue }
                let dstURL = appSupportURL.appendingPathComponent(name)
                if !fm.fileExists(atPath: dstURL.path) {
                    try fm.copyItem(atPath: bundlePath, toPath: dstURL.path)
                }
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstURL.path)
            }

            if !fm.fileExists(atPath: logFileURL.path) {
                fm.createFile(atPath: logFileURL.path, contents: nil)
            }
            envReady = true
            appendLog("Entorno preparado en:\n\(appSupportURL.path)\n\n")
        } catch {
            appendLog("ERROR preparando entorno: \(error.localizedDescription)\n")
        }
    }

    // MARK: - Ejecutor genérico de scripts

    private func runScript(scriptName: String, arguments: [String], title: String) {
        if !envReady { setupEnvironmentIfNeeded() }
        guard envReady else {
            appendLog("No se ha podido preparar el entorno. Abortando.\n")
            return
        }

        let scriptURL = appSupportURL.appendingPathComponent(scriptName)
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            appendLog("ERROR: script \(scriptName) no existe en \(scriptURL.path)\n")
            return
        }

        appendLog("\n=== Ejecutando \(title) ===\n")
        isRunning = true
        lastResult = nil
        inputPipe = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path] + arguments

            let outPipe = Pipe()
            let inPipe  = Pipe()
            process.standardOutput = outPipe
            process.standardError  = outPipe
            process.standardInput  = inPipe

            // T2.1 – exponer proceso y pipe a la UI
            DispatchQueue.main.async {
                self.activeProcess = process
                self.inputPipe = inPipe
            }

            // T2.2 – leer salida y detectar sentinel USBLAB_RESULT
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }

                for line in str.components(separatedBy: "\n") {
                    if let result = TestResult.parse(from: line.trimmingCharacters(in: .whitespaces)) {
                        DispatchQueue.main.async { self.lastResult = result }
                    }
                }
                DispatchQueue.main.async { self.appendLog(str) }
            }

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    self.appendLog("ERROR al lanzar bash: \(error.localizedDescription)\n")
                    self.isRunning = false
                    self.activeProcess = nil
                    self.inputPipe = nil
                }
                return
            }

            process.waitUntilExit()
            outPipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                // Si el proceso terminó con error y no llegó resultado JSON → resultado de error
                if process.terminationStatus != 0 && self.lastResult == nil {
                    self.lastResult = TestResult.error(test: title)
                }
                self.appendLog("\n\(title) terminó con código \(process.terminationStatus)\n")
                self.appendLog("=========================================\n\n")
                self.isRunning = false
                self.activeProcess = nil
                self.inputPipe = nil
            }
        }
    }

    // MARK: - Helpers

    private func sendEnter() {
        guard let inPipe = inputPipe,
              let data = "\n".data(using: .utf8) else { return }
        inPipe.fileHandleForWriting.write(data)
    }

    private func copyLogToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logText, forType: .string)
    }

    private func appendLog(_ text: String) {
        logText.append(text)
        guard let data = text.data(using: .utf8) else { return }
        do {
            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch { /* silencioso */ }
    }
}

#Preview {
    ContentView()
}
