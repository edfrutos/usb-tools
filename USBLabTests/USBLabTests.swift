//
//  USBLabTests.swift
//  USBLabTests
//
//  Created by Eugenio de Frutos Sanchez on 9/12/25.
//

import Testing
@testable import USBLab

// MARK: - TestResult

struct TestResultTests {

    // 1. Parseo de línea sentinel válida con todos los campos
    @Test func parseFullResultLine() throws {
        let line = #"USBLAB_RESULT: {"result":"ok","test":"stress","cycles_ok":5,"speed_gen_mb_s":45,"speed_copy_mb_s":30}"#
        let result = try #require(TestResult.parse(from: line))
        #expect(result.result == "ok")
        #expect(result.test == "stress")
        #expect(result.cycles_ok == 5)
        #expect(result.speed_gen_mb_s == 45)
        #expect(result.speed_copy_mb_s == 30)
        #expect(result.isOK == true)
    }

    // 2. Parseo de resultado de error (campo result != "ok")
    @Test func parseErrorResult() throws {
        let line = #"USBLAB_RESULT: {"result":"error","test":"reconexion","cycles_ok":2}"#
        let result = try #require(TestResult.parse(from: line))
        #expect(result.result == "error")
        #expect(result.isOK == false)
        #expect(result.cycles_ok == 2)
        #expect(result.speed_gen_mb_s == nil)
    }

    // 3. Parseo de línea sin sentinel → nil
    @Test func parseLineWithoutSentinel() {
        let line = "Algún mensaje de log normal sin el prefijo sentinel."
        #expect(TestResult.parse(from: line) == nil)
    }

    // 4. Parseo de línea con sentinel pero JSON inválido → nil
    @Test func parseMalformedJSON() {
        let line = "USBLAB_RESULT: {not valid json}"
        #expect(TestResult.parse(from: line) == nil)
    }

    // 5. Factory TestResult.error(test:)
    @Test func errorFactory() {
        let r = TestResult.error(test: "surface")
        #expect(r.result == "error")
        #expect(r.test == "surface")
        #expect(r.isOK == false)
        #expect(r.cycles_ok == nil)
    }

    // 6. Parseo de campos opcionales ausentes
    @Test func parseMinimalResult() throws {
        let line = #"USBLAB_RESULT: {"result":"ok","test":"lab"}"#
        let result = try #require(TestResult.parse(from: line))
        #expect(result.result == "ok")
        #expect(result.cycles_ok == nil)
        #expect(result.speed_gen_mb_s == nil)
        #expect(result.speed_copy_mb_s == nil)
    }
}

// MARK: - resolveDeviceNode

struct ResolveDeviceNodeTests {

    // 7. Línea Device Node en output típico de diskutil info
    @Test func extractsDeviceNodeFromDiskutilOutput() {
        let diskutilOutput = """
           Device Node:              /dev/disk8
           Device Identifier:        disk8
           Volume Name:              USB_Limpio
           """
        #expect(resolveDeviceNode(from: diskutilOutput) == "/dev/disk8")
    }

    // 8. Salida de diskutil sin línea Device Node → nil
    @Test func returnsNilWhenDeviceNodeAbsent() {
        let diskutilOutput = """
           Volume Name:              USB_Limpio
           Mounted:                  Yes
           """
        #expect(resolveDeviceNode(from: diskutilOutput) == nil)
    }

    // 9. String vacío → nil
    @Test func returnsNilForEmptyString() {
        #expect(resolveDeviceNode(from: "") == nil)
    }

    // 10. Device Node con ruta de disco físico (sin partición)
    @Test func extractsDiskWithoutPartition() {
        let diskutilOutput = "   Device Node:              /dev/disk0s1"
        #expect(resolveDeviceNode(from: diskutilOutput) == "/dev/disk0s1")
    }
}
