import SwiftUI
import MuroKit
import CoreFoundation

/// Edits the values declared by a Workshop item, then translates scenes again.
struct WorkshopPropertiesView: View {
    let entry: WallpaperEntry
    let root: URL
    let onApplied: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var project: [String: Any] = [:]
    @State private var values: [String: String] = [:]
    @State private var error: String?
    @State private var saving = false

    private var itemDirectory: URL {
        if let web = entry.web { return root.appendingPathComponent(web, isDirectory: true) }
        return root.appendingPathComponent(entry.scene ?? "", isDirectory: true).appendingPathComponent("item", isDirectory: true)
    }
    private var definitions: [String: [String: Any]] {
        (project["general"] as? [String: Any])?["properties"] as? [String: [String: Any]] ?? [:]
    }
    private var keys: [String] { definitions.keys.filter { definitions[$0]?["value"] != nil }.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wallpaper Properties").font(.title2.bold())
            Text(entry.title).foregroundStyle(.secondary)
            if keys.isEmpty { Text("This wallpaper has no editable properties.").foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(keys, id: \.self) { key in
                        let definition = definitions[key] ?? [:]
                        let label = (definition["text"] as? String) ?? key
                        HStack {
                            Text(label).frame(width: 190, alignment: .leading)
                            if let number = definition["value"] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
                                Toggle("", isOn: Binding(get: { values[key] == "true" }, set: { values[key] = $0 ? "true" : "false" })).labelsHidden()
                            } else {
                                TextField("Value", text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }))
                            }
                        }
                    }
                }
            }.frame(maxHeight: 360)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply") { apply() }.disabled(saving || keys.isEmpty)
            }
        }.padding(24).frame(width: 520).onAppear(perform: load)
    }
    private func load() {
        guard let data = try? Data(contentsOf: itemDirectory.appendingPathComponent("project.json")),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { error = "Could not read wallpaper properties."; return }
        project = object
        for key in keys {
            guard let value = definitions[key]?["value"] else { continue }
            if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { values[key] = n.boolValue ? "true" : "false" }
            else { values[key] = String(describing: value) }
        }
    }
    private func apply() {
        var edited = project
        guard var general = edited["general"] as? [String: Any], var properties = general["properties"] as? [String: [String: Any]] else { return }
        for key in keys {
            guard var definition = properties[key], let old = definition["value"], let text = values[key] else { continue }
            if let number = old as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { definition["value"] = text == "true" }
                else if let value = Double(text), value.isFinite { definition["value"] = value }
                else { error = "Enter a number for \(key)."; return }
            } else if old is String { definition["value"] = text }
            properties[key] = definition
        }
        general["properties"] = properties
        edited["general"] = general
        let path = itemDirectory.appendingPathComponent("project.json")
        let item = entry
        let libraryRoot = root
        do {
            let data = try JSONSerialization.data(withJSONObject: edited, options: [.prettyPrinted, .sortedKeys])
            saving = true
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        let original = try Data(contentsOf: path)
                        try data.write(to: path, options: .atomic)
                        do { if item.scene != nil { _ = try WorkshopImporter.reimport(entry: item, root: libraryRoot) } }
                        catch { try? original.write(to: path, options: .atomic); throw error }
                    }.value
                    saving = false
                    onApplied()
                    dismiss()
                } catch {
                    saving = false
                    self.error = error.localizedDescription
                }
            }
        } catch { self.error = error.localizedDescription }
    }
}
