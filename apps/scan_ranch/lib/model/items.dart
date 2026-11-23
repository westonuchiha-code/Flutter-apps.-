// Things that can be dropped in the ranch. Only food for now; toys, cleaning
// tools and battle items can be added as new [ItemKind]s.

enum ItemCategory { food, toy }

class ItemKind {
  const ItemKind({
    required this.id,
    required this.name,
    required this.category,
    required this.color,
    this.nutrition = 0,
    this.joy = 0,
    this.bites = 3,
    this.unlimited = false,
  });

  /// Stored in saves; never rename.
  final String id;
  final String name;
  final ItemCategory category;

  /// Drawing colour (ARGB).
  final int color;

  /// Hunger restored per bite (0–1 scale).
  final double nutrition;

  /// Happiness gained per bite.
  final double joy;

  /// Bites before it is gone.
  final int bites;

  /// Always available (no inventory count).
  final bool unlimited;
}

const berry = ItemKind(
  id: 'berry',
  name: 'Ranch Berry',
  category: ItemCategory.food,
  color: 0xFFD8344F,
  nutrition: 0.12,
  joy: 0.02,
  unlimited: true,
);

const cake = ItemKind(
  id: 'cake',
  name: 'Sweet Cake',
  category: ItemCategory.food,
  color: 0xFFF2B6C9,
  nutrition: 0.15,
  joy: 0.08,
  bites: 4,
);

const meat = ItemKind(
  id: 'meat',
  name: 'Hearty Meat',
  category: ItemCategory.food,
  color: 0xFFB5573A,
  nutrition: 0.3,
  joy: 0.03,
  bites: 3,
);

const itemKinds = [berry, cake, meat];

ItemKind itemKind(String id) =>
    itemKinds.firstWhere((k) => k.id == id, orElse: () => berry);
