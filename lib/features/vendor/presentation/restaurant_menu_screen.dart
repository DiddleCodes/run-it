import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/uploads_repository.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/photo_capture_screen.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/presentation/widgets/validated_field.dart';
import '../../ordering/presentation/widgets/ordering_components.dart' show naira;
import '../application/restaurant_menu_controller.dart';
import '../domain/vendor_dashboard_models.dart';

/// Task 12's Menu tab — grouped by category (same grouping the student
/// side's own menu screen uses), each row a tappable card for editing plus
/// its own availability toggle for a quick sold-out mark without opening
/// the edit screen at all.
class RestaurantMenuScreen extends ConsumerWidget {
  const RestaurantMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(restaurantMenuProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        title: const Text('Menu'),
        backgroundColor: AppColors.backgroundCream,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.accentForest),
            onPressed: () => context.push(AppRoutes.restaurantMenuAdd),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.accentForest,
          onRefresh: () => ref.read(restaurantMenuProvider.notifier).refresh(),
          child: itemsAsync.when(
            loading: () => ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 24),
              children: const [SkeletonList(count: 5)],
            ),
            error: (error, stack) => _ErrorState(onRetry: () => ref.read(restaurantMenuProvider.notifier).refresh()),
            data: (items) {
              if (items.isEmpty) return const _EmptyMenu();
              final byCategory = <String, List<VendorMenuItem>>{};
              for (final item in items) {
                byCategory.putIfAbsent(item.category, () => []).add(item);
              }
              final categories = byCategory.keys.toList()..sort();
              return ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 24),
                children: [
                  for (final category in categories) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, top: 14),
                      child: Text(
                        category,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: AppColors.accentForestDeep, fontWeight: FontWeight.w700),
                      ),
                    ),
                    for (final item in byCategory[category]!) ...[
                      _MenuItemRow(item: item),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MenuItemRow extends ConsumerStatefulWidget {
  const _MenuItemRow({required this.item});
  final VendorMenuItem item;

  @override
  ConsumerState<_MenuItemRow> createState() => _MenuItemRowState();
}

class _MenuItemRowState extends ConsumerState<_MenuItemRow> {
  bool _togglingAvailability = false;

  Future<void> _toggleAvailability(bool value) async {
    setState(() => _togglingAvailability = true);
    try {
      await ref.read(restaurantMenuProvider.notifier).setAvailability(widget.item.id, value);
    } catch (e) {
      if (!mounted) return;
      ref
          .read(appNotificationProvider.notifier)
          .error(e is ApiException ? e.message : "Couldn't reach the server. Try again.");
    } finally {
      if (mounted) setState(() => _togglingAvailability = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${widget.item.name}"?'),
        content: const Text('This removes it from your menu for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(restaurantMenuProvider.notifier).deleteItem(widget.item.id);
    } catch (e) {
      if (!mounted) return;
      ref
          .read(appNotificationProvider.notifier)
          .error(e is ApiException ? e.message : "Couldn't reach the server. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: AppElevation.card(false),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.push(AppRoutes.restaurantMenuEdit, extra: item),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: item.photoUrl == null || item.photoUrl!.isEmpty
                  ? Container(
                      width: 64,
                      height: 64,
                      color: AppColors.accentForest.withValues(alpha: 0.1),
                      alignment: Alignment.center,
                      child: const Icon(Icons.restaurant_rounded, color: AppColors.accentForest),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.photoUrl!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      memCacheWidth: 128,
                      memCacheHeight: 128,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => context.push(AppRoutes.restaurantMenuEdit, extra: item),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: AppColors.inkText, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    naira(item.priceKobo ~/ 100),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                  ),
                ],
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: item.isAvailable,
                activeThumbColor: AppColors.accentForest,
                onChanged: _togglingAvailability ? null : _toggleAvailability,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                onPressed: _confirmDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyMenu extends StatelessWidget {
  const _EmptyMenu();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.restaurant_menu_rounded, size: 48, color: AppColors.mutedText),
                  const SizedBox(height: 12),
                  Text(
                    'Your menu is empty',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppColors.inkText, fontSize: 18),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap + Add Item to add your first dish.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(
                    "Couldn't load your menu.",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkText),
                  ),
                  const SizedBox(height: 12),
                  TextButton(onPressed: onRetry, child: const Text('Try again')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Add (item == null) and Edit (item != null) in one screen — same
/// convention as most edit forms in this codebase (e.g. `PayoutAccountForm`
/// handles both "no saved account" and "editing a saved one" internally
/// rather than being two separate widgets).
class RestaurantMenuEditScreen extends ConsumerStatefulWidget {
  const RestaurantMenuEditScreen({super.key, this.item});
  final VendorMenuItem? item;

  @override
  ConsumerState<RestaurantMenuEditScreen> createState() => _RestaurantMenuEditScreenState();
}

class _RestaurantMenuEditScreenState extends ConsumerState<RestaurantMenuEditScreen> {
  late final _nameController = TextEditingController(text: widget.item?.name ?? '');
  late final _descriptionController = TextEditingController(text: widget.item?.description ?? '');
  late final _priceController = TextEditingController(
    text: widget.item == null ? '' : '${widget.item!.priceKobo ~/ 100}',
  );
  final _nameFieldKey = GlobalKey<ValidatedFieldState>();
  final _priceFieldKey = GlobalKey<ValidatedFieldState>();
  late String? _category = widget.item?.category;
  bool _categoryError = false;
  bool _addingNewCategory = false;
  final _newCategoryController = TextEditingController();
  Uint8List? _newPhotoBytes;
  bool _saving = false;

  bool get _isEditing => widget.item != null;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _newCategoryController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => const PhotoCaptureScreen(
          title: 'Menu Item Photo',
          subtitle: 'A clear, appetizing photo helps students choose faster.',
          permissionRationale: "We use your camera just for this photo — it's only shown on this item's listing.",
        ),
      ),
    );
    if (bytes != null && mounted) setState(() => _newPhotoBytes = bytes);
  }

  void _selectCategory(String category) {
    setState(() {
      _category = category;
      _categoryError = false;
      _addingNewCategory = false;
    });
  }

  void _confirmNewCategory() {
    final value = _newCategoryController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _category = value;
      _categoryError = false;
      _addingNewCategory = false;
    });
  }

  Future<void> _save() async {
    final nameOk = _nameFieldKey.currentState?.validateNow() ?? false;
    final priceOk = _priceFieldKey.currentState?.validateNow() ?? false;
    final category = _category;
    setState(() => _categoryError = category == null || category.trim().isEmpty);
    if (!nameOk || !priceOk || category == null || category.trim().isEmpty) return;

    setState(() => _saving = true);
    try {
      String? photoUrl = widget.item?.photoUrl;
      final bytes = _newPhotoBytes;
      if (bytes != null) {
        final session = ref.read(authControllerProvider);
        photoUrl = await ref
            .read(uploadsRepositoryProvider)
            .uploadImage(
              bytes: bytes,
              purpose: 'menu-item-photo',
              contentType: 'image/jpeg',
              token: session?.accessToken ?? '',
            );
      }

      final priceKobo = int.parse(_priceController.text.trim()) * 100;
      final controller = ref.read(restaurantMenuProvider.notifier);
      if (_isEditing) {
        await controller.updateItem(
          itemId: widget.item!.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          priceKobo: priceKobo,
          photoUrl: photoUrl,
          category: category.trim(),
        );
      } else {
        await controller.createItem(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          priceKobo: priceKobo,
          photoUrl: photoUrl,
          category: category.trim(),
        );
      }
      if (!mounted) return;
      ref
          .read(appNotificationProvider.notifier)
          .success(_isEditing ? 'Menu item updated.' : 'Menu item added.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ref
          .read(appNotificationProvider.notifier)
          .error(e is ApiException ? e.message : "Couldn't reach the server. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${widget.item!.name}"?'),
        content: const Text('This removes it from your menu for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(restaurantMenuProvider.notifier).deleteItem(widget.item!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ref
          .read(appNotificationProvider.notifier)
          .error(e is ApiException ? e.message : "Couldn't reach the server. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    const onBg = AppColors.inkText;
    final existingCategories = ref.watch(restaurantMenuCategoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Item' : 'Add Item'),
        backgroundColor: AppColors.backgroundCream,
        elevation: 0,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: _PhotoPicker(bytes: _newPhotoBytes, url: widget.item?.photoUrl, onTap: _capturePhoto)),
                const SizedBox(height: AppSpacing.xl),
                Text('Name', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: onBg)),
                const SizedBox(height: AppSpacing.sm),
                ValidatedField(
                  key: _nameFieldKey,
                  controller: _nameController,
                  hintText: 'e.g. Signature Jollof Rice',
                  validator: (value) => value.trim().length < 2 ? 'Enter an item name.' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Price (₦)', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: onBg)),
                const SizedBox(height: AppSpacing.sm),
                ValidatedField(
                  key: _priceFieldKey,
                  controller: _priceController,
                  hintText: 'e.g. 2500',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value.trim());
                    return parsed == null || parsed <= 0 ? 'Enter a valid price.' : null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Category', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: onBg)),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    // Matches exactly what the student-side filter chips
                    // derive from (EateryMenuScreen's own category-chip
                    // logic) — picking one of these keeps the menu's
                    // categories from fragmenting into near-duplicates.
                    for (final category in existingCategories)
                      _MenuCategoryChip(
                        label: category,
                        selected: _category == category,
                        onTap: () => _selectCategory(category),
                      ),
                    _MenuCategoryChip(
                      label: '+ New',
                      selected: _addingNewCategory,
                      onTap: () => setState(() => _addingNewCategory = !_addingNewCategory),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  child: _addingNewCategory
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Row(
                            children: [
                              Expanded(
                                child: ValidatedField(
                                  controller: _newCategoryController,
                                  hintText: 'New category name',
                                  validator: (_) => null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.check_circle_rounded, color: AppColors.accentForest),
                                onPressed: _confirmNewCategory,
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (_category != null && !existingCategories.contains(_category) && !_addingNewCategory)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Using new category "$_category"',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
                    ),
                  ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  child: _categoryError
                      ? Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(
                            'Choose or add a category.',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.error),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Description (optional)', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: onBg)),
                const SizedBox(height: AppSpacing.sm),
                ValidatedField(
                  controller: _descriptionController,
                  hintText: "What's in it?",
                  validator: (_) => null,
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: _isEditing ? 'Save Changes' : 'Add to Menu',
                  onPressed: _saving ? null : _save,
                  loading: _saving,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({required this.bytes, required this.url, required this.onTap});
  final Uint8List? bytes;
  final String? url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 110.0;
    Widget content;
    if (bytes != null) {
      content = Image.memory(bytes!, width: size, height: size, fit: BoxFit.cover);
    } else if (url != null && url!.isNotEmpty) {
      content = CachedNetworkImage(imageUrl: url!, width: size, height: size, fit: BoxFit.cover);
    } else {
      content = const Icon(Icons.add_a_photo_rounded, size: 32, color: AppColors.accentForest);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accentForest.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(22), child: content),
      ),
    );
  }
}

class _MenuCategoryChip extends StatelessWidget {
  const _MenuCategoryChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentForest : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? AppColors.accentForest : AppColors.borderSubtle),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? Colors.white : AppColors.inkText,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
