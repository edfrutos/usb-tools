//
//  VolumePickerView.swift
//  USBLab
//
//  Sheet para seleccionar un volumen montado en lugar de teclearlo a mano.
//

import SwiftUI

// MARK: - Modelo

struct VolumeInfo: Identifiable {
    let id = UUID()
    let name: String
    let mountPoint: String
    let totalBytes: Int64
    let availableBytes: Int64
    let isRemovable: Bool
    let isInternal: Bool

    /// Devuelve true si el volumen parece una unidad USB / extraíble real
    var likelyUSB: Bool { isRemovable && !isInternal }
}

// MARK: - Vista

struct VolumePickerView: View {
    @Binding var selectedPath: String
    @Binding var showing: Bool

    @State private var volumes: [VolumeInfo] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Cabecera
            HStack {
                Image(systemName: "externaldrive.fill.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Seleccionar volumen")
                    .font(.title2).bold()
                Spacer()
                Button { loadVolumes() } label: {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .help("Volver a detectar volúmenes")
            }

            Divider()

            if isLoading {
                HStack { ProgressView(); Text("Detectando…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if volumes.isEmpty {
                Text("No se encontraron volúmenes montados.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                List(volumes) { vol in
                    Button {
                        selectedPath = vol.mountPoint
                        showing = false
                    } label: {
                        volumeRow(vol)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Text("\(volumes.count) volúmenes detectados")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cerrar") { showing = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 540, minHeight: 340)
        .onAppear { loadVolumes() }
    }

    // MARK: - Fila de volumen

    @ViewBuilder
    private func volumeRow(_ vol: VolumeInfo) -> some View {
        HStack(spacing: 12) {

            // Icono
            Image(systemName: iconName(for: vol))
                .font(.title2)
                .foregroundStyle(vol.likelyUSB ? .blue : .secondary)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(vol.name)
                        .fontWeight(.medium)
                    if vol.likelyUSB {
                        Text("USB")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if vol.isInternal {
                        Text("Interno")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.gray.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(vol.mountPoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if vol.totalBytes > 0 {
                    Text("\(bytesHuman(vol.availableBytes)) libres de \(bytesHuman(vol.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Lógica

    private func loadVolumes() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let keys: [URLResourceKey] = [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsRemovableKey,
                .volumeIsInternalKey,
                .volumeIsEjectableKey
            ]
            let urls = FileManager.default.mountedVolumeURLs(
                includingPropertiesForKeys: keys,
                options: [.skipHiddenVolumes]
            ) ?? []

            let infos: [VolumeInfo] = urls.compactMap { url in
                guard let vals = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
                return VolumeInfo(
                    name: vals.volumeName ?? url.lastPathComponent,
                    mountPoint: url.path,
                    totalBytes: Int64(vals.volumeTotalCapacity ?? 0),
                    availableBytes: Int64(vals.volumeAvailableCapacity ?? 0),
                    isRemovable: vals.volumeIsRemovable ?? false,
                    isInternal: vals.volumeIsInternal ?? true
                )
            }
            .sorted { a, b in
                // Extraíbles primero, luego alfabético
                if a.likelyUSB != b.likelyUSB { return a.likelyUSB }
                if a.isInternal != b.isInternal { return !a.isInternal }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            DispatchQueue.main.async {
                self.volumes = infos
                self.isLoading = false
            }
        }
    }

    private func iconName(for vol: VolumeInfo) -> String {
        if vol.likelyUSB        { return "externaldrive.fill" }
        if vol.isRemovable      { return "opticaldiscdrive" }
        if vol.mountPoint == "/" { return "desktopcomputer" }
        return "internaldrive"
    }

    private func bytesHuman(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

#Preview {
    VolumePickerView(
        selectedPath: .constant("/Volumes/USB_Limpio"),
        showing: .constant(true)
    )
}
