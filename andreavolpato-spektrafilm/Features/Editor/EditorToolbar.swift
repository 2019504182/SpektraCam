import SwiftUI

/// Editing modes; Export is a separate command. ED-02.
enum EditorTool: String, CaseIterable, Identifiable {
    case crop
    case develop
    case adjust
    case effects

    var id: Self { self }

    var title: String {
        switch self {
        case .crop: "Crop"
        case .develop: "Develop"
        case .adjust: "Adjust"
        case .effects: "Effects"
        }
    }

    var symbolName: String {
        switch self {
        case .crop: "crop"
        case .develop: "camera.filters"
        case .adjust: "slider.horizontal.3"
        case .effects: "sparkles"
        }
    }
}

/// The system groups adjacent toolbar items. A fixed spacer separates Export.
struct EditorToolbar: ToolbarContent {
    @Binding var activeTool: EditorTool?
    let export: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            ControlGroup {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        activeTool = activeTool == tool ? nil : tool
                    } label: {
                        toolLabel(tool.title, symbol: tool.symbolName, selected: activeTool == tool)
                    }
                    .accessibilityAddTraits(activeTool == tool ? .isSelected : [])
                    .accessibilityIdentifier("editor.tool." + tool.rawValue)
                    .accessibilityShowsLargeContentViewer { Label(tool.title, systemImage: tool.symbolName) }
                }
            }.controlGroupStyle(.navigation).controlSize(.small)
        }
        ToolbarSpacer(.fixed, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button(action: export) { toolLabel("Export", symbol: "square.and.arrow.up", selected: false) }
                .accessibilityIdentifier("editor.export")
                .accessibilityShowsLargeContentViewer { Label("Export", systemImage: "square.and.arrow.up") }
        }
    }
    private func toolLabel(_ title: String, symbol: String, selected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium)).frame(width: 24, height: 22)
            Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1).frame(height: 12)
        }
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .frame(width: 44, height: 44).contentShape(.rect)
    }
}
