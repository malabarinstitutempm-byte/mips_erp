class FeeHead {
  final int? id;
  final String name;
  final String? description;

  FeeHead({this.id, required this.name, this.description});

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'description': description,
  };

  factory FeeHead.fromMap(Map<String, dynamic> map) => FeeHead(
    id: map['id'],
    name: map['name'],
    description: map['description'],
  );
}
