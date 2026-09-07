import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarPage

    var body: some View {
        List(SidebarPage.allCases, selection: $selection) { page in
            Label(page.title, systemImage: page.systemImage)
                .tag(page)
        }
        .navigationTitle("ClickFlow")
    }
}

private extension SidebarPage {
    var title: LocalizedStringKey {
        switch self {
        case .clicker: "sidebar.clicker"
        case .macros: "sidebar.macros"
        case .combinedMacros: "sidebar.combinedMacros"
        case .settings: "sidebar.settings"
        }
    }

    var systemImage: String {
        switch self {
        case .clicker: "cursorarrow.click.2"
        case .macros: "record.circle"
        case .combinedMacros: "gamecontroller"
        case .settings: "gearshape"
        }
    }
}
