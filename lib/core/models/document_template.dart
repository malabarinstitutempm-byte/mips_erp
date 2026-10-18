class DocumentTemplate {
  final int? id;
  final String name;
  final String content;

  DocumentTemplate({this.id, required this.name, required this.content});

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'content': content,
    };
  }

  factory DocumentTemplate.fromMap(Map<String, dynamic> map) {
    return DocumentTemplate(
      id: map['id'],
      name: map['name'],
      content: map['content'],
    );
  }
}
