# Catalog format

The app downloads these artifacts from this directory on `main`:

| File | Purpose |
|---|---|
| `version.json` | Catalog metadata, checked before download |
| `romdb.db.gz` | Gzipped SQLite database |
| `static/content/ps3/raps/*.rap` | PS3 license files, referenced by catalog URLs |
| `static/content/psv/zrifs/*.txt` | PSVita zRIF keys, referenced by catalog URLs |

## version.json

```json
{
  "version": "20260904",
  "generated_at": "2026-09-04T15:00:00Z",
  "schema_version": 4,
  "min_app_version": "1.2.0",
  "size": 55424693,
  "uncompressed_size": 345706496,
  "entries": 241126,
  "links": 400298,
  "platforms": 50,
  "sources": 4,
  "retroachievements": 9576
}
```

`schema_version` bumps trigger a wipe-and-redownload in the app. `min_app_version` gates catalogs that need newer app features.

## Database schema (v4)

- `platforms(id, brand, name)`
- `entries(slug PK, rom_id, search_key, title, platform, boxart_url, ra_game_id, ra_num_achievements)`
- `entries_fts` — FTS4 over `search_key`, `tokenize=unicode61`
- `regions(id, name)` / `regions_entries(entry, region)`
- `sources(id PK, name, homepage, kind, auth_required, priority, manifest_json)`
- `source_health(source_id PK, status, last_checked, reason, entry_count, link_count)`
- `user_sources(id, name, kind, config_json, created_at)` — app-owned, empty in published catalogs
- `torrents(infohash PK, source_id, name, magnet, torrent_blob, total_size, piece_length, file_count, trackers_json, added_at)`
- `links(entry, name, type, format, url, filename, host, size, size_str, source_url, source_id, requires_auth, torrent_infohash, torrent_file_index, torrent_file_path)`
- `entry_groups(id PK, kind, title, platform, member_count, metadata_json)` / `entry_group_members(group_id, entry, member_index, member_label)` — multi-disc grouping

Indexes: `idx_entries_platform` on `entries(platform)`, `idx_entry_groups_kind` on `entry_groups(kind)`.
