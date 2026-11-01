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

/// One native glass surface for modes and one for Export. Captions share a baseline.
struct EditorToolbar: View {
    @Binding var activeTool: EditorTool?
    let export: () -> Void
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(EditorTool.allCases) { tool in
                        Button {
                            activeTool = activeTool == tool ? nil : tool
                        } label: {
                            toolLabel(tool.title, symbol: tool.symbolName, selected: activeTool == tool)
                                .frame(maxWidth: .infinity).contentShape(.capsule)
                                .background {
                                    if activeTool == tool { Capsule().fill(.primary.opacity(0.08)) }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(activeTool == tool ? .isSelected : [])
                        .accessibilityIdentifier("editor.tool." + tool.rawValue)
                        .accessibilityShowsLargeContentViewer {
                            Label(tool.title, systemImage: tool.symbolName)
                        }
                    }
                }
                .padding(4).glassEffect(.regular, in: .capsule)
                Button(action: export) {
                    toolLabel("Export", symbol: "square.and.arrow.up", selected: false).frame(width: 52)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain).padding(4)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityIdentifier("editor.export")
                .accessibilityShowsLargeContentViewer { Label("Export", systemImage: "square.and.arrow.up") }
            }
        }.frame(height: 56)
    }
    private func toolLabel(_ title: String, symbol: String, selected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .frame(width: 24, height: 22)
            Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1).frame(height: 12)
        }
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .frame(height: 48).contentShape(.capsule)
    }
}
