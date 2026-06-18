//
//  USBLabUtils.swift
//  USBLab
//
//  Funciones y tipos compartidos entre vistas y tests.
//

import Foundation

// MARK: - TestResult

/// Resultado estructurado que los scripts bash emiten en stdout como:
///   USBLAB_RESULT: {"result":"ok","test":"stress","cycles_ok":5,...}
struct TestResult: Codable {
    let result: String        // "ok" | "error"
    let test: String          // "stress" | "reconexion" | "surface" | "lab"
    let cycles_ok: Int?
    let speed_gen_mb_s: Int?
    let speed_copy_mb_s: Int?
}

extension TestResult {
    var isOK: Bool { result == "ok" }

    /// Intenta parsear una línea de salida del script que empiece por el sentinel.
    static func parse(from line: String) -> TestResult? {
        let sentinel = "USBLAB_RESULT: "
        guard line.hasPrefix(sentinel) else { return nil }
        let json = String(line.dropFirst(sentinel.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TestResult.self, from: data)
    }

    /// Resultado de error genérico cuando el script termina con código != 0.
    static func error(test: String) -> TestResult {
        TestResult(result: "error", test: test,
                   cycles_ok: nil, speed_gen_mb_s: nil, speed_copy_mb_s: nil)
    }
}

// MARK: - Disk utilities

/// Extrae el Device Node (/dev/diskX) del output de `diskutil info`.
/// Factorizada aquí para poder ser testeada de forma independiente.
func resolveDeviceNode(from diskutilInfo: String) -> String? {
    for line in diskutilInfo.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("Device Node:") else { continue }
        let parts = trimmed.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
    }
    return nil
}
