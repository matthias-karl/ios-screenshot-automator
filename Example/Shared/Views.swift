import SwiftUI

struct RootView: View {
    @State private var selection = LaunchOptions.screen == "detail" ? "items" : "home"

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("tab.home", systemImage: "house.fill") }
                .accessibilityIdentifier("screen.home")
                .tag("home")
            ItemsView()
                .tabItem { Label("tab.items", systemImage: "leaf.fill") }
                .accessibilityIdentifier("screen.items")
                .tag("items")
            SettingsView()
                .tabItem { Label("tab.settings", systemImage: "gearshape.fill") }
                .accessibilityIdentifier("screen.settings")
                .tag("settings")
        }
    }
}

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("home.headline").font(.title2.bold())
                    ForEach(Mock.items.prefix(3)) { item in
                        HStack(spacing: 14) {
                            Image(systemName: item.symbol)
                                .font(.title2)
                                .frame(width: 48, height: 48)
                                .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text(item.note).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .navigationTitle(Text("tab.home"))
        }
    }
}

struct ItemsView: View {
    @State private var path: [Item] = LaunchOptions.screen == "detail" ? [Mock.items[0]] : []
    @State private var showingAdd = false

    var body: some View {
        NavigationStack(path: $path) {
            List(Mock.items) { item in
                NavigationLink(value: item) {
                    Label(item.name, systemImage: item.symbol)
                }
            }
            .navigationTitle(Text("tab.items"))
            .navigationDestination(for: Item.self) { DetailView(item: $0) }
            .toolbar {
                ToolbarItem {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("button.add")
                }
            }
            .sheet(isPresented: $showingAdd) { AddItemSheet() }
        }
    }
}

struct DetailView: View {
    let item: Item

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: item.symbol)
                .font(.system(size: 80))
                .foregroundStyle(.green)
            Text(item.name).font(.largeTitle.bold())
            Text(item.note).foregroundStyle(.secondary)
            Text("detail.hint").font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle(item.name)
    }
}

struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("add.name", text: $name)
            }
            .navigationTitle(Text("add.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("add.done") { dismiss() }.accessibilityIdentifier("button.done")
                }
            }
        }
    }
}

struct SettingsView: View {
    @State private var reminders = true
    @State private var compact = false

    var body: some View {
        NavigationStack {
            Form {
                Toggle("settings.reminders", isOn: $reminders)
                Toggle("settings.compact", isOn: $compact)
                Text("settings.about")
            }
            .navigationTitle(Text("tab.settings"))
        }
    }
}
