import SwiftUI

struct TabBackupRestoreView: View {
    @EnvironmentObject private var store: ChatStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "arrow.clockwise.icloud", title: "Backup & Restore")
            
            settingGroup {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Chats are exported into plaintext, unencrypted JSON file. You can import them back later.")
                        .foregroundColor(Color.secondary)
                        .font(.callout)
                        .padding(.bottom, 4)

                    HStack {
                        Text("Export chats history")
                            .fontWeight(.medium)
                        Spacer()
                        Button("Export to file...") {
                            store.loadFromCoreData { result in
                                switch result {
                                case .failure(let error):
                                    fatalError(error.localizedDescription)
                                case .success(let chats):
                                    let encoder = JSONEncoder()
                                    encoder.outputFormatting = .prettyPrinted
                                    let data = try! encoder.encode(chats)
                                    let savePanel = NSSavePanel()
                                    savePanel.allowedContentTypes = [.json]
                                    savePanel.nameFieldStringValue = "chats_\(getCurrentFormattedDate()).json"
                                    savePanel.begin { (result) in
                                        if result == .OK {
                                            do {
                                                try data.write(to: savePanel.url!)
                                            }
                                            catch {
                                                print(error)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Material.ultraThinMaterial)
                            .opacity(0.3)
                    )

                    HStack {
                        Text("Import chats history")
                            .fontWeight(.medium)
                        Spacer()
                        Button("Import from file...") {
                            let openPanel = NSOpenPanel()
                            openPanel.allowedContentTypes = [.json]
                            openPanel.begin { (result) in
                                if result == .OK {
                                    do {
                                        let data = try Data(contentsOf: openPanel.url!)
                                        let decoder = JSONDecoder()
                                        let chats = try decoder.decode([Chat].self, from: data)

                                        store.saveToCoreData(chats: chats) { result in
                                            print("State saved")
                                            if case .failure(let error) = result {
                                                fatalError(error.localizedDescription)
                                            }
                                        }

                                    }
                                    catch {
                                        print(error)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Material.ultraThinMaterial)
                            .opacity(0.3)
                    )
                }
            }
        }
    }
    
    // MARK: - Section Header Style
    private func sectionHeader(icon: String, title: String, iconColor: Color = .accentColor, animate: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title2.weight(.semibold))
                .symbolEffect(.pulse, options: animate ? .repeating : .nonRepeating, value: animate)
                .frame(width: 30)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Material.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Setting Group Style
    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
    }
}

// MARK: - Inline Version for Main Window
struct InlineTabBackupRestoreView: View {
    @EnvironmentObject private var store: ChatStore
    
    // Colors matching the chat app theme
    private let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    private var cardBackgroundColor: Color {
        Color(NSColor.controlBackgroundColor)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "arrow.clockwise.icloud", title: "Backup & Restore")
            
            settingGroup {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Chats are exported into plaintext, unencrypted JSON file. You can import them back later.")
                        .foregroundColor(Color.secondary)
                        .font(.callout)
                        .padding(.bottom, 4)

                    HStack {
                        Text("Export chats history")
                            .fontWeight(.medium)
                        Spacer()
                        Button("Export to file...") {
                            store.loadFromCoreData { result in
                                switch result {
                                case .failure(let error):
                                    fatalError(error.localizedDescription)
                                case .success(let chats):
                                    let encoder = JSONEncoder()
                                    encoder.outputFormatting = .prettyPrinted
                                    let data = try! encoder.encode(chats)
                                    let savePanel = NSSavePanel()
                                    savePanel.allowedContentTypes = [.json]
                                    savePanel.nameFieldStringValue = "chats_\(getCurrentFormattedDate()).json"
                                    savePanel.begin { (result) in
                                        if result == .OK {
                                            do {
                                                try data.write(to: savePanel.url!)
                                            }
                                            catch {
                                                print(error)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Material.ultraThinMaterial)
                            .opacity(0.3)
                    )

                    HStack {
                        Text("Import chats history")
                            .fontWeight(.medium)
                        Spacer()
                        Button("Import from file...") {
                            let openPanel = NSOpenPanel()
                            openPanel.allowedContentTypes = [.json]
                            openPanel.begin { (result) in
                                if result == .OK {
                                    do {
                                        let data = try Data(contentsOf: openPanel.url!)
                                        let decoder = JSONDecoder()
                                        let chats = try decoder.decode([Chat].self, from: data)

                                        store.saveToCoreData(chats: chats) { result in
                                            print("State saved")
                                            if case .failure(let error) = result {
                                                fatalError(error.localizedDescription)
                                            }
                                        }

                                    }
                                    catch {
                                        print(error)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Material.ultraThinMaterial)
                            .opacity(0.3)
                    )
                }
            }
        }
    }
    
    // MARK: - Section Header Style
    private func sectionHeader(icon: String, title: String, iconColor: Color? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(iconColor ?? primaryBlue)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Setting Group Style
    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Legacy BackupRestoreView (for compatibility)
struct BackupRestoreView: View {
    @ObservedObject var store: ChatStore

    var body: some View {
        VStack {
            HStack {
                Text("Chats are exported into plaintext, unencrypted JSON file. You can import them back later.")
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.bottom, 16)

            HStack {
                Text("Export chats history")
                Spacer()
                Button("Export to file...") {

                    store.loadFromCoreData { result in
                        switch result {
                        case .failure(let error):
                            fatalError(error.localizedDescription)
                        case .success(let chats):
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = .prettyPrinted
                            let data = try! encoder.encode(chats)
                            let savePanel = NSSavePanel()
                            savePanel.allowedContentTypes = [.json]
                            savePanel.nameFieldStringValue = "chats_\(getCurrentFormattedDate()).json"
                            savePanel.begin { (result) in
                                if result == .OK {
                                    do {
                                        try data.write(to: savePanel.url!)
                                    }
                                    catch {
                                        print(error)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Text("Import chats history")
                Spacer()
                Button("Import from file...") {
                    let openPanel = NSOpenPanel()
                    openPanel.allowedContentTypes = [.json]
                    openPanel.begin { (result) in
                        if result == .OK {
                            do {
                                let data = try Data(contentsOf: openPanel.url!)
                                let decoder = JSONDecoder()
                                let chats = try decoder.decode([Chat].self, from: data)

                                store.saveToCoreData(chats: chats) { result in
                                    print("State saved")
                                    if case .failure(let error) = result {
                                        fatalError(error.localizedDescription)
                                    }
                                }

                            }
                            catch {
                                print(error)
                            }
                        }
                    }
                }
            }
        }
        .padding(32)
    }
}
