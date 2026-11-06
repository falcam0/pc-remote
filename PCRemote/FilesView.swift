import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct FilesView: View {
    @EnvironmentObject var conn: RemoteConnection
    @State private var selected: FSEntry?
    @State private var shared: SharedFile?

    var body: some View {
        NavigationStack {
            List {
                if let dir = conn.directory, dir.path != nil {
                    Button {
                        if let parent = dir.parent { conn.list(parent) } else { conn.listRoots() }
                    } label: {
                        Label("Cartella superiore", systemImage: "arrow.up.left")
                    }
                }

                ForEach(conn.directory?.entries ?? []) { entry in
                    Button {
                        if entry.isDir { conn.list(entry.path) } else { selected = entry }
                    } label: {
                        HStack {
                            Image(systemName: entry.isDir ? "folder.fill" : "doc")
                                .foregroundStyle(entry.isDir ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading) {
                                Text(entry.name).lineLimit(1)
                                if !entry.isDir {
                                    Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                if conn.directory?.entries.isEmpty == true {
                    Text("Cartella vuota").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(conn.directory?.title ?? "File")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if conn.directory == nil { conn.listRoots() } }
            .confirmationDialog(
                selected?.name ?? "",
                isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
                titleVisibility: .visible,
                presenting: selected
            ) { entry in
                Button("Apri sul PC") { conn.openOnPC(entry.path) }
                Button("Scarica su iPhone") { conn.download(entry.path) }
                Button("Annulla", role: .cancel) {}
            }
            .onReceive(conn.$downloadedFile.compactMap { $0 }) { file in
                shared = file
                conn.downloadedFile = nil
            }
            .sheet(item: $shared) { file in
                ShareSheet(url: file.url)
            }
        }
    }
}
