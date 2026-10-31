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

/// System-managed Liquid Glass; four editing modes and a separate Export command.
struct EditorToolbar: ToolbarContent {
    @Binding var activeTool: EditorTool?
    let export: () -> Void

    var body: some ToolbarContent {
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItemGroup(placement: .bottomBar) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    activeTool = activeTool == tool ? nil : tool
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tool.symbolName).font(.system(size: 21, weight: .medium))
                        Text(tool.title).font(.caption2).dynamicTypeSize(...DynamicTypeSize.large)
                    }
                    .frame(width: 48, height: 48)
                    .foregroundStyle(activeTool == tool ? Color.accentColor : Color.primary)
                    .background {
                        if activeTool == tool { Capsule().fill(.primary.opacity(0.08)) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(activeTool == tool ? .isSelected : [])
                .accessibilityIdentifier("editor.tool.\(tool.rawValue)")
                .accessibilityShowsLargeContentViewer {
                    Label(tool.title, systemImage: tool.symbolName)
                }
            }
        }
        ToolbarSpacer(.fixed, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button(action: export) {
                VStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 21, weight: .medium))
                    Text("Export").font(.caption2).dynamicTypeSize(...DynamicTypeSize.large)
                }.frame(width: 48, height: 48)
            }
            .accessibilityIdentifier("editor.export")
            .accessibilityShowsLargeContentViewer { Label("Export", systemImage: "square.and.arrow.up") }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
    }
}
