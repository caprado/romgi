/// A logical group relating several catalog entries. Today the only kind is
/// `disc` (multi-disc games), but the `kind` discriminator mirrors the
/// catalog's `entry_groups.kind` column so future kinds (revisions, bundles)
/// flow through the same model without a schema change on the app side.
class EntryGroup {
  final String id;
  final String kind;

  /// Canonical group title with the grouping token stripped
  /// (e.g. "Final Fantasy VII", not "Final Fantasy VII (Disc 1)").
  final String title;
  final String platform;

  /// Members ordered by [EntryGroupMember.index].
  final List<EntryGroupMember> members;

  const EntryGroup({
    required this.id,
    required this.kind,
    required this.title,
    required this.platform,
    required this.members,
  });

  bool get isDisc => kind == 'disc';

  /// The member matching [slug], or null if [slug] isn't part of the group.
  EntryGroupMember? memberFor(String slug) {
    for (final member in members) {
      if (member.slug == slug) return member;
    }
    return null;
  }
}

class EntryGroupMember {
  final String slug;

  /// The member entry's own title (still carries its disc token).
  final String title;

  /// Ordering position within the group (disc number).
  final int index;

  /// Human label for the position, e.g. "Disc 1".
  final String label;

  const EntryGroupMember({
    required this.slug,
    required this.title,
    required this.index,
    required this.label,
  });
}
