class Task {
  const Task({
    required this.id,
    required this.title,
    required this.isCompleted,
    required this.createdAt,
    required this.completedAt,
    required this.categoryId,
    required this.deletedAt,
  });

  final int id;
  final String title;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int categoryId;
  final DateTime? deletedAt;

  factory Task.fromMap(Map<String, Object?> map) {
    return Task(
      id: map['id']! as int,
      title: map['title']! as String,
      isCompleted: map['is_completed']! as int == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at']! as int,
        isUtc: true,
      ),
      completedAt: switch (map['completed_at']) {
        final int timestamp => DateTime.fromMillisecondsSinceEpoch(
          timestamp,
          isUtc: true,
        ),
        _ => null,
      },
      categoryId: map['category_id']! as int,
      deletedAt: switch (map['deleted_at']) {
        final int timestamp => DateTime.fromMillisecondsSinceEpoch(
          timestamp,
          isUtc: true,
        ),
        _ => null,
      },
    );
  }
}
