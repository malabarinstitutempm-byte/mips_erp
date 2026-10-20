import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/responsive.dart';
import 'skeleton_loader.dart';

class AppDataTable<T> extends StatefulWidget {
  final List<String> columns;
  final List<int> flexes;
  final List<T> data;
  final Widget Function(BuildContext context, T item) rowBuilder;
  final Widget Function(BuildContext context, T item)? cardBuilder;
  final Widget? emptyState;
  final bool isLoading;
  final int skeletonCount;
  final bool selectable;
  final List<T> selectedItems;
  final ValueChanged<List<T>>? onSelectionChanged;
  // Simple pagination
  final int? totalItems;
  final int? rowsPerPage;
  final int? currentPage;
  final ValueChanged<int>? onPageChanged;

  const AppDataTable({
    super.key,
    required this.columns,
    required this.flexes,
    required this.data,
    required this.rowBuilder,
    this.cardBuilder,
    this.emptyState,
    this.isLoading = false,
    this.skeletonCount = 5,
    this.selectable = false,
    this.selectedItems = const [],
    this.onSelectionChanged,
    this.totalItems,
    this.rowsPerPage = 10,
    this.currentPage = 1,
    this.onPageChanged,
  }) : assert(columns.length == flexes.length, 'Columns and flexes must match in length');

  @override
  State<AppDataTable<T>> createState() => _AppDataTableState<T>();
}

class _AppDataTableState<T> extends State<AppDataTable<T>> {
  
  void _toggleItem(T item) {
    if (widget.onSelectionChanged == null) return;
    final List<T> newSelection = List.from(widget.selectedItems);
    if (newSelection.contains(item)) {
      newSelection.remove(item);
    } else {
      newSelection.add(item);
    }
    widget.onSelectionChanged!(newSelection);
  }

  void _toggleAll() {
    if (widget.onSelectionChanged == null) return;
    if (widget.selectedItems.length == widget.data.length) {
      widget.onSelectionChanged!([]); // Deselect all
    } else {
      widget.onSelectionChanged!(List.from(widget.data)); // Select all
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading && widget.data.isEmpty && widget.emptyState != null) {
      return widget.emptyState!;
    }

    final bool allSelected = widget.data.isNotEmpty && widget.selectedItems.length == widget.data.length;

    final tableContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sticky Header
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: const BoxDecoration(
            color: AppColors.bg,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              if (widget.selectable)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.lg),
                  child: Checkbox(
                    value: widget.data.isEmpty ? false : allSelected,
                    onChanged: widget.data.isEmpty ? null : (_) => _toggleAll(),
                    activeColor: AppColors.brand,
                  ),
                ),
              ...List.generate(widget.columns.length, (index) {
                return Expanded(
                  flex: widget.flexes[index],
                  child: Text(
                    widget.columns[index],
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                  ),
                );
              }),
            ],
          ),
        ),
        
        // Rows
        Expanded(
          child: widget.isLoading
              ? ListView.separated(
                  itemCount: widget.skeletonCount,
                  separatorBuilder: (_,__) => const Divider(height: 1),
                  itemBuilder: (_,__) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
                    child: SkeletonLoader(width: double.infinity, height: 28),
                  ),
                )
              : ListView.builder(
                  itemCount: widget.data.length,
                  itemBuilder: (context, index) {
                    final item = widget.data[index];
                    final isSelected = widget.selectedItems.contains(item);
                    return _HoverRow(
                      isSelected: isSelected,
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppColors.border)),
                        ),
                        child: Row(
                          children: [
                            if (widget.selectable)
                              Padding(
                                padding: const EdgeInsets.only(right: AppSpacing.lg),
                                child: Checkbox(
                                  value: isSelected,
                                  onChanged: (_) => _toggleItem(item),
                                  activeColor: AppColors.brand,
                                ),
                              ),
                            Expanded(child: widget.rowBuilder(context, item)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Pagination Footer
        if (widget.totalItems != null && widget.onPageChanged != null)
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Showing ${((widget.currentPage! - 1) * widget.rowsPerPage!) + 1} - ${(widget.currentPage! * widget.rowsPerPage!).clamp(0, widget.totalItems!)} of ${widget.totalItems}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: AppSpacing.lg),
                IconButton(
                  icon: Icon(Icons.chevron_left, size: 20, color: AppColors.textMuted),
                  onPressed: widget.currentPage! > 1 
                      ? () => widget.onPageChanged!(widget.currentPage! - 1) 
                      : null,
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
                  onPressed: (widget.currentPage! * widget.rowsPerPage!) < widget.totalItems!
                      ? () => widget.onPageChanged!(widget.currentPage! + 1)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Responsive.phoneBreakpoint) {
          return _buildMobileCardList(context, constraints);
        }
        if (constraints.maxWidth < 750) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 750,
              height: constraints.maxHeight,
              child: tableContent,
            ),
          );
        }
        return tableContent;
      },
    );
  }

  Widget _buildMobileCardList(BuildContext context, BoxConstraints constraints) {
    if (widget.isLoading) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: widget.skeletonCount,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: SkeletonLoader(width: double.infinity, height: 90, borderRadius: AppRadius.card),
        ),
      );
    }

    if (widget.data.isEmpty && widget.emptyState != null) {
      return widget.emptyState!;
    }

    return Column(
      children: [
        if (widget.selectable && widget.data.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${widget.selectedItems.length} selected',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                ),
                TextButton(
                  onPressed: _toggleAll,
                  child: Text(
                    widget.selectedItems.length == widget.data.length ? 'Deselect All' : 'Select All',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: widget.data.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = widget.data[index];
              final isSelected = widget.selectedItems.contains(item);
              Widget cardChild;
              if (widget.cardBuilder != null) {
                cardChild = widget.cardBuilder!(context, item);
              } else {
                cardChild = Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.brandTint : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: isSelected ? AppColors.brand : AppColors.border),
                  ),
                  child: widget.rowBuilder(context, item),
                );
              }

              if (widget.selectable) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleItem(item),
                        activeColor: AppColors.brand,
                      ),
                      Expanded(child: cardChild),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: cardChild,
              );
            },
          ),
        ),
        if (widget.totalItems != null && widget.onPageChanged != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Showing ${((widget.currentPage! - 1) * widget.rowsPerPage!) + 1} - ${(widget.currentPage! * widget.rowsPerPage!).clamp(0, widget.totalItems!)} of ${widget.totalItems}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20, color: AppColors.textMuted),
                      onPressed: widget.currentPage! > 1 
                          ? () => widget.onPageChanged!(widget.currentPage! - 1) 
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
                      onPressed: (widget.currentPage! * widget.rowsPerPage!) < widget.totalItems!
                          ? () => widget.onPageChanged!(widget.currentPage! + 1)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HoverRow extends StatefulWidget {
  final Widget child;
  final bool isSelected;
  const _HoverRow({required this.child, this.isSelected = false});

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _isHovered = false;
  
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        color: widget.isSelected 
            ? AppColors.brandTint 
            : (_isHovered ? AppColors.bg : AppColors.surface),
        child: widget.child,
      ),
    );
  }
}
