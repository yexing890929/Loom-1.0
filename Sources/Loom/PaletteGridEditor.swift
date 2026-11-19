import AppKit
import SwiftUI

// NSCollectionView provides native dragging sessions, selection and drop feedback.
struct PaletteGridEditor: NSViewRepresentable {
    let layout: PaletteLayout
    let itemSize: CGFloat
    let move: (Action, Int) -> Void
    private static let itemID = NSUserInterfaceItemIdentifier("PaletteGridCell")
    private static let dragType = NSPasteboard.PasteboardType("dev.loom.palette.action")
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSCollectionView {
        let collection = NSCollectionView()
        let flow = NSCollectionViewFlowLayout()
        flow.minimumInteritemSpacing = 4
        flow.minimumLineSpacing = 4
        flow.itemSize = CGSize(width: itemSize, height: itemSize)
        collection.collectionViewLayout = flow
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.allowsMultipleSelection = false
        collection.register(PaletteGridItem.self, forItemWithIdentifier: Self.itemID)
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        collection.registerForDraggedTypes([Self.dragType])
        collection.setDraggingSourceOperationMask(.move, forLocal: true)
        collection.setAccessibilityLabel("Palette 布局，10 列 6 行")
        collection.reloadData()
        return collection
    }
    func updateNSView(_ collection: NSCollectionView, context: Context) {
        let previous = context.coordinator.owner
        context.coordinator.owner = self
        if let flow = collection.collectionViewLayout as? NSCollectionViewFlowLayout {
            flow.itemSize = CGSize(width: itemSize, height: itemSize)
        }
        if previous.layout != layout || previous.itemSize != itemSize { collection.reloadData() }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSCollectionView, context: Context) -> CGSize? {
        let size = layout.size(itemSize: itemSize)
        let proposedWidth = proposal.width ?? size.width
        // At the maximum size, use the Form row's full content width. The native
        // flow layout distributes the extra inter-item space across ten columns.
        let width = itemSize >= 44 && proposedWidth.isFinite ? max(size.width, proposedWidth) : size.width
        return CGSize(width: width, height: size.height)
    }
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var owner: PaletteGridEditor
        init(_ owner: PaletteGridEditor) { self.owner = owner }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { PaletteLayout.count }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: PaletteGridEditor.itemID, for: indexPath) as! PaletteGridItem
            item.configure(action: owner.layout.cells[indexPath.item], index: indexPath.item)
            return item
        }
        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard let action = owner.layout.cells[indexPath.item] else { return nil }
            let item = NSPasteboardItem()
            item.setString(action.rawValue, forType: PaletteGridEditor.dragType)
            return item
        }
        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
                            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            guard draggingInfo.draggingSource as? NSCollectionView === collectionView,
                  let name = draggingInfo.draggingPasteboard.string(forType: PaletteGridEditor.dragType),
                  let action = Action(rawValue: name), owner.layout.cells.contains(action),
                  let index = collectionView.indexPathForItem(at: collectionView.convert(draggingInfo.draggingLocation, from: nil)) else { return [] }
            proposedDropIndexPath.pointee = index as NSIndexPath
            proposedDropOperation.pointee = .on
            return .move
        }
        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
                            indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            guard draggingInfo.draggingSource as? NSCollectionView === collectionView,
                  let name = draggingInfo.draggingPasteboard.string(forType: PaletteGridEditor.dragType),
                  let action = Action(rawValue: name), owner.layout.cells.contains(action),
                  owner.layout.cells.indices.contains(indexPath.item) else { return false }
            owner.move(action, indexPath.item)
            collectionView.selectionIndexPaths = [indexPath]
            return true
        }
    }
}

private final class PaletteGridItem: NSCollectionViewItem {
    private let box = NSBox()
    private let icon = NSImageView()
    override func loadView() {
        box.boxType = .custom
        box.borderWidth = 1
        box.cornerRadius = 6
        box.contentViewMargins = .zero
        view = box
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleNone
        box.contentView?.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 25), icon.heightAnchor.constraint(equalToConstant: 23)
        ])
        updateStyle()
    }
    override var isSelected: Bool { didSet { updateStyle() } }
    override var highlightState: NSCollectionViewItem.HighlightState { didSet { updateStyle() } }
    func configure(action: Action?, index: Int) {
        _ = view
        icon.image = action.map { PaletteIcon.image(for: $0) }
        view.toolTip = action?.title
        view.setAccessibilityLabel("第 \(index / PaletteLayout.columns + 1) 行，第 \(index % PaletteLayout.columns + 1) 列，\(action?.title ?? "空格")")
        updateStyle()
    }
    private func updateStyle() {
        let highlighted = isSelected || highlightState == .asDropTarget
        box.borderColor = highlighted ? .controlAccentColor : .separatorColor
        box.fillColor = highlighted ? .selectedContentBackgroundColor : .controlBackgroundColor
        icon.contentTintColor = highlighted ? .alternateSelectedControlTextColor : .labelColor
    }
}
