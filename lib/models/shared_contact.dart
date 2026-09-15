class SharedContact {
  final String email;
  final String name;

  const SharedContact({
    required this.email,
    this.name = '',
  });

  String get displayName => name.trim().isNotEmpty ? name.trim() : email;

  String get subtitle =>
      name.trim().isNotEmpty && name.trim().toLowerCase() != email
          ? email
          : '';
}
