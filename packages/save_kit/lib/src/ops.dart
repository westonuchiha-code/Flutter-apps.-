/// What the save manager's buttons do, the same on every console (ported
/// from the PC's CardOps.gd). Blocks on disk: run it off the UI thread.
/// It reads the card fresh every time and goes by a save's id, so a stale
/// screen can't hit the wrong save. All writing goes through [CardStore]
/// (allowed, closed, unchanged, backed up, checked, swapped).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'bytes.dart';
import 'card_image.dart';
import 'cards.dart';
import 'formats/dreamcast.dart';
import 'formats/gamecube.dart';
import 'formats/n64.dart';
import 'formats/neogeo.dart';
import 'formats/ps1.dart';
import 'formats/ps2.dart';
import 'formats/ps3.dart';
import 'formats/saturn.dart';
import 'model.dart';
import 'prefs.dart';
import 'slots.dart';
import 'store.dart';

typedef Check = String Function(Uint8List);

/// What a button did: ok + a line to show, or what to ask about.
class OpResult {
  OpResult(this.ok, this.text);
  final bool ok;
  final String text;

  /// Copy / import: ask before replacing these ids.
  List<String> conflicts = const [];
}

/// A card as it is on disk right now.
class LiveCard {
  late MemoryCard card;
  Uint8List file = Uint8List(0);
  Uint8List bytes = Uint8List(0);
  String error = '';

  CardSave? find(String id) {
    for (final s in card.saves) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// What Undelete offers: a PS1 save still on the card ([slot] > 0), or a
/// backed-up one.
class LostSave {
  LostSave(this.id, {this.slot = 0, this.backup});
  final String id;
  final int slot;
  final Backup? backup;
  int get time => backup?.time ?? 0;
  String get what => backup?.what ?? CardOps.ps1Deleted;
}

class CardOps {
  /// [isApp]: may it change real cards (only the installed app may).
  /// [looseDir] = the downloaded saves: no emulator ever has those open.
  /// [running] = the emulators running now (null: ask the system, which
  /// Android can't; the host must then say).
  CardOps({
    required CardSafety safety,
    required String backupRoot,
    required this.exportDir,
    String favoritesFile = '',
    this.looseDir = '',
    this.slots,
    List<String>? Function()? running,
  }) : store = CardStore(safety: safety, root: backupRoot),
       favorites = CardFavorites(
         favoritesFile.isNotEmpty
             ? favoritesFile
             : p.join(backupRoot, 'favorites.json'),
         safety,
       ) {
    final loose = looseDir.isEmpty ? '' : '${_norm(looseDir)}/';
    store.ownerRunning = (path) {
      // no emulator holds an exported file or a downloaded save open
      if (_norm(p.dirname(path)) == _norm(exportDir)) return '';
      if (loose.isNotEmpty && _norm(path).startsWith(loose)) return '';
      if (running == null) return CardOwners.inUse(path);
      final names = running();
      return names == null
          ? CardOwners.cantTell
          : CardOwners.reason(path, names);
    };
  }

  static const saveExt = {
    'PS1': 'mcs', 'PS2': 'psu', 'DC': 'dci', 'GC': 'gci', 'N64': 'note', //
    'SATURN': 'bup', 'NEO GEO': 'ngs', 'PS3': 'zip',
  };

  /// Backup key of one save: the card's key, this, the save's id.
  static const saveMark = '|';

  /// How much of an exported save says where it sat, rather than what it is.
  static const entryBytes = {
    'PS1': 128, 'PS2': 0, 'DC': 32, 'GC': 64, 'N64': 32, 'SATURN': 64, //
    'NEO GEO': 4, 'PS3': 0,
  };
  static const importMax = 70 << 20;
  static const ps1Deleted = 'on the card';
  static const folderPs2 =
      'PCSX2 folder cards can be looked at here, but not changed';
  static const folderNo =
      'That needs a card file: this card is a folder of separate saves';
  static const deletedCard = 'delete card';
  static String kept(String what) =>
      "$what is a favorite, so it can't be deleted or replaced. Take its star off first";

  final CardStore store;
  final CardFavorites favorites;
  final String exportDir, looseDir;

  /// Which card is in which console slot (null = none).
  CardSlots? slots;

  /// [path] is one of the read-only copies ([CardSafety.readOnly]).
  bool _locked(String path) => store.safety.isReadOnly(path);

  static String _norm(String path) =>
      p.normalize(p.absolute(path)).replaceAll(r'\', '/').toLowerCase();

  // ---- saves ---------------------------------------------------------------

  OpResult backUpSaves(MemoryCard card, List<String> ids) {
    final from = openCard(card);
    if (from.error.isNotEmpty) return _no(from.error);
    final no = _keepSaves(from, ids, 'backup');
    return no.isNotEmpty ? _no(no) : _yes('Backed up ${_saves(ids.length)}');
  }

  OpResult deleteSaves(MemoryCard card, List<String> ids) {
    if (_locked(card.path)) return _no(CardSafety.readOnlyNotice);
    final from = openCard(card);
    if (from.error.isNotEmpty) return _no(from.error);
    if (ids.isEmpty) return _no('No saves were chosen');
    var no = favoriteAmong(from, ids);
    if (no.isEmpty) no = _keepSaves(from, ids, 'delete');
    if (no.isEmpty) no = _remove(from, ids, 'delete');
    return no.isNotEmpty
        ? _no(no)
        : _yes('Deleted ${_saves(ids.length)}. Restore brings back the backup');
  }

  /// Same names come back as conflicts until [replace] says yes. A move
  /// deletes only once the copy has read back.
  OpResult copySaves(
    MemoryCard card,
    List<String> ids,
    MemoryCard target, {
    bool replace = false,
    bool move = false,
  }) {
    if (card.key() == target.key()) {
      return _no("That's the card it's already on");
    }
    return copyMany(
      [(card: card, ids: ids)],
      target,
      replace: replace,
      move: move,
    );
  }

  /// All of them land on the target in one write, or none do.
  OpResult copyMany(
    List<({MemoryCard card, List<String> ids})> groups,
    MemoryCard target, {
    bool replace = false,
    bool move = false,
  }) {
    // Copying from a read-only copy is fine; onto one, or moving out of
    // one (it deletes there), is not.
    if (_locked(target.path) ||
        (move && groups.any((g) => _locked(g.card.path)))) {
      return _no(CardSafety.readOnlyNotice);
    }
    final cards = <MemoryCard>[];
    final lists = <List<String>>[];
    var count = 0;
    for (final g in groups) {
      if (g.card.key() == target.key() || g.ids.isEmpty) {
        continue; // there already
      }
      if (g.card.system != target.system) {
        return _no(
          'A ${g.card.system} save only works on a ${g.card.system} card',
        );
      }
      cards.add(g.card);
      lists.add(g.ids);
      count += g.ids.length;
    }
    if (count == 0) {
      return _no(
        groups.isEmpty
            ? 'No saves were chosen'
            : 'Those are already on that card',
      );
    }
    final to = openCard(target);
    if (to.error.isNotEmpty) return _no(to.error);
    favorites.reload();
    if (move && favorites.error.isNotEmpty) return _no(favorites.error);
    final packs = <Uint8List>[];
    final names = <String>[]; // what they'll be called over there
    final starredFrom = <String>[], starredNames = <String>[];
    var serial = Uint8List(0);
    for (var k = 0; k < cards.length; k++) {
      final from = openCard(cards[k]);
      if (from.error.isNotEmpty) return _no(from.error);
      if (cards.length == 1 && from.card.system == 'GC' && !cards[k].isFolder) {
        serial = GcWriter.serial(from.bytes);
      }
      for (final id in lists[k]) {
        final pack = exportBytes(from, id);
        if (!pack.ok) return _no(pack.error);
        final name = idIn(from.card.system, pack.data);
        final s = from.find(id);
        if (names.contains(name)) {
          final who = s != null && s.titleLines.isNotEmpty
              ? s.titleLines.first
              : name;
          return _no(
            '"$who" is selected twice, from two cards. A card holds one of each',
          );
        }
        names.add(name);
        packs.add(pack.data);
        if (s != null && favorites.has(from.card, s)) {
          starredFrom.add(CardFavorites.keyOf(from.card, s));
          starredNames.add(name);
        }
      }
    }
    final out = _putIn(
      to,
      names,
      packs,
      replace,
      serial,
      move ? 'move' : 'copy',
    );
    if (!out.ok) return out;
    if (!move) return _yes('Copied ${_saves(count)} to ${target.name}');
    var at = 0, gone = 0;
    var no = '';
    for (var k = 0; k < cards.length; k++) {
      final from = openCard(
        cards[k],
      ); // fresh: paks can share the file just written
      no = from.error;
      if (no.isEmpty) {
        for (var i = 0; i < lists[k].length; i++) {
          // only what was copied may be deleted
          if (!Bytes.same(exportBytes(from, lists[k][i]).data, packs[at + i])) {
            no = 'it changed while it was being moved';
            break;
          }
        }
      }
      if (no.isEmpty) no = _keepSaves(from, lists[k], 'move');
      if (no.isEmpty) no = _remove(from, lists[k], 'move');
      if (no.isNotEmpty) break;
      at += lists[k].length;
      gone += lists[k].length;
    }
    // the stars of those that did leave go along
    if (gone > 0 && starredFrom.isNotEmpty) {
      final keysFrom = <String>[], keysTo = <String>[];
      final there = openCard(target);
      if (there.error.isEmpty) {
        for (var i = 0; i < starredFrom.length; i++) {
          final landed = there.find(starredNames[i]);
          if (landed != null && names.indexOf(starredNames[i]) < gone) {
            keysFrom.add(starredFrom[i]);
            keysTo.add(CardFavorites.keyOf(there.card, landed));
          }
        }
      }
      if (favorites.carry(keysFrom, keysTo).isNotEmpty && no.isEmpty) {
        return _no(
          "Moved, but the stars didn't come along: mark those favorites again",
        );
      }
    }
    if (no.isNotEmpty) {
      return _no(
        'Copied all $count, but ${count - gone} are still on the old card too: $no',
      );
    }
    return _yes('Moved ${_saves(count)} to ${target.name}');
  }

  OpResult exportSaves(MemoryCard card, List<String> ids) {
    final from = openCard(card);
    if (from.error.isNotEmpty) return _no(from.error);
    try {
      Directory(exportDir).createSync(recursive: true);
    } catch (_) {
      return _no("Couldn't make the export folder");
    }
    for (final id in ids) {
      final pack = exportBytes(from, id);
      if (!pack.ok) return _no(pack.error);
      final base = p.join(exportDir, fileSafe(id));
      final ext = saveExt[card.system]!;
      var path = '$base.$ext';
      for (var n = 2; File(path).existsSync(); n++) {
        path = '$base ($n).$ext';
      }
      final no = store.create(path, pack.data, _notEmpty);
      if (no.isNotEmpty) return _no(no);
    }
    return _yes('Exported ${_saves(ids.length)} to ${p.basename(exportDir)}');
  }

  OpResult importFile(MemoryCard card, String path, {bool replace = false}) {
    if (_locked(card.path)) return _no(CardSafety.readOnlyNotice);
    final pack = saveFile(card.system, path);
    if (!pack.ok) return _no(pack.error);
    return _takeIn(card, pack.data, replace, 'import');
  }

  /// Backups of one save, newest first.
  List<Backup> saveHistory(MemoryCard card, String id) =>
      store.history(card.key() + saveMark + id);

  OpResult restoreSave(MemoryCard card, Backup entry, {bool replace = false}) {
    if (_locked(card.path)) return _no(CardSafety.readOnlyNotice);
    final bytes = store.readBackup(entry);
    if (bytes.isEmpty) {
      return _no('That backup is damaged, so nothing was changed');
    }
    final file = namedFile(entry.path);
    if (card.isFolder && card.system == 'GC' && file.isNotEmpty) {
      return _backAsFile(card, file, bytes, replace);
    }
    return _takeIn(card, bytes, replace, 'restore');
  }

  /// PS1's own deleted saves, and backed-up saves that aren't on the card.
  List<LostSave> lostSaves(MemoryCard card) {
    final out = <LostSave>[];
    final now = openCard(card);
    if (now.error.isNotEmpty) return out;
    final have = {for (final s in now.card.saves) s.id};
    if (card.system == 'PS1') {
      for (final slot in Ps1Writer.deleted(now.bytes)) {
        final id = Bytes.ascii(
          now.bytes,
          slot * Ps1Writer.frame + Ps1Writer.nameAt,
          20,
        );
        if (have.add(id)) out.add(LostSave(id, slot: slot));
      }
    }
    final prefix = card.key() + saveMark;
    for (final e in store.allBackups()) {
      final key = e.path;
      final file = card.isFolder ? namedFile(key) : '';
      if (file.isNotEmpty && File(p.join(card.path, file)).existsSync()) {
        continue; // back already
      }
      if (!key.startsWith(prefix)) continue;
      final id = key.substring(prefix.length);
      if (have.add(id)) out.add(LostSave(id, backup: e));
    }
    return out;
  }

  OpResult undelete(MemoryCard card, LostSave entry) {
    if (_locked(card.path)) return _no(CardSafety.readOnlyNotice);
    if (entry.slot <= 0) return restoreSave(card, entry.backup!);
    final now = openCard(card);
    if (now.error.isNotEmpty) return _no(now.error);
    final edit = Ps1Writer.undelete(now.bytes, entry.slot);
    final no = edit.ok ? _commit(now, edit.data, 'undelete') : edit.error;
    return no.isNotEmpty ? _no(no) : _yes("It's back on the card");
  }

  // ---- whole cards ---------------------------------------------------------

  OpResult backUpCards(List<MemoryCard> cards) {
    final done = <String>{}; // four paks can share one file
    final failed = <String>[];
    var saved = 0;
    for (final c in cards) {
      if (!done.add(c.path)) continue;
      final no = _backUpCard(c);
      if (no.isEmpty) {
        saved++;
      } else {
        failed.add('${c.name}: $no');
      }
    }
    if (failed.isNotEmpty) {
      return _no('Backed up $saved, but not ${failed.join('; ')}');
    }
    return _yes('Backed up $saved card${saved == 1 ? '' : 's'}');
  }

  List<Backup> cardHistory(MemoryCard card) =>
      card.isFolder ? [] : store.history(card.path);

  /// The whole card file goes, backed up first. Never one with a favorite on
  /// it, one a console has in its slot, or one sharing its file.
  OpResult deleteCard(MemoryCard card) {
    if (_locked(card.path)) return _no(CardSafety.readOnlyNotice);
    if (card.isFolder) return _no(folderNo);
    final f = File(card.path);
    final shared =
        card.system == 'N64' &&
        card.span > 0 &&
        f.existsSync() &&
        card.span < f.lengthSync();
    if (card.offset > 0 || shared) {
      return _no(
        "That card shares its file with other paks, so it can't be deleted on its own",
      );
    }
    if (card.inSlot.isNotEmpty || slots?.slotOf(card.path) != null) {
      return _no(
        '${card.name} is in the console. Take it out of the console first',
      );
    }
    if (!f.existsSync()) return _no("That card isn't there any more");
    favorites.reload();
    if (favorites.error.isNotEmpty) return _no(favorites.error);
    for (final s in card.saves) {
      if (favorites.has(card, s)) {
        return _no(
          '${card.name} has a favorite on it (${s.displayName()}). '
          'Take its star off or move it first',
        );
      }
    }
    final no = store.remove(card.path, f.readAsBytesSync(), deletedCard);
    return no.isNotEmpty
        ? _no(no)
        : _yes(
            'Deleted ${card.name}. More > Bring back a deleted card undoes it',
          );
  }

  /// Deleted cards that aren't back: the newest backup of each, newest first.
  List<Backup> deletedCards() {
    final out = <Backup>[];
    final seen = <String>{};
    for (final e in store.allBackups()) {
      if (e.what != deletedCard || e.path.isEmpty) continue;
      if (!seen.add(e.path.toLowerCase()) || File(e.path).existsSync()) {
        continue;
      }
      out.add(e);
    }
    return out;
  }

  OpResult bringBack(Backup entry) {
    if (_locked(entry.path)) return _no(CardSafety.readOnlyNotice);
    if (entry.path.isEmpty || File(entry.path).existsSync()) {
      return _no("There's a card there already");
    }
    final no = store.restore(entry.path, entry, _notEmpty);
    return no.isNotEmpty
        ? _no(no)
        : _yes('Brought back ${p.basename(entry.path)}');
  }

  /// One pak of a shared file comes back on its own; the others stay.
  OpResult restoreCard(MemoryCard card, Backup entry) {
    if (_locked(card.path)) return _no(CardSafety.readOnlyNotice);
    if (card.isFolder) return _no(folderNo);
    final old = store.readBackup(entry);
    if (old.isEmpty) {
      return _no('That backup is damaged, so nothing was changed');
    }
    final f = File(card.path);
    if (!f.existsSync()) return _no("That card isn't there any more");
    final now = f.readAsBytesSync();
    final was = CardImage.take(old, _fresh(card, old.length));
    if (was.isEmpty || check(card.system, was).isNotEmpty) {
      return _no("That backup isn't a whole card");
    }
    final here = _fresh(card, now.length);
    final file = card.offset > 0 ? CardImage.put(now, here, was) : old;
    if (file.isEmpty) return _no("That backup doesn't fit this card");
    var no = _favoritesSurvive(card, was);
    if (no.isEmpty) {
      no = store.change(
        card.path,
        now,
        file,
        'before restore',
        _fileCheck(here),
      );
    }
    return no.isNotEmpty ? _no(no) : _yes('Restored ${card.name}');
  }

  OpResult formatCard(MemoryCard card) {
    if (_locked(card.path)) return _no(CardSafety.readOnlyNotice);
    if (card.unformatted) return _formatBlank(card);
    final now = openCard(card);
    if (now.error.isNotEmpty) return _no(now.error);
    if (card.isFolder) return _no(folderNo);
    final blank = blankLike(card.system, now.bytes);
    if (blank.isEmpty) return _no("That size of card can't be formatted here");
    final ids = [for (final s in now.card.saves) s.id];
    var no = favoriteAmong(now, ids);
    if (no.isEmpty) no = _keepSaves(now, ids, 'format');
    if (no.isEmpty) no = _commit(now, blank, 'format');
    return no.isNotEmpty
        ? _no(no)
        : _yes('Formatted ${card.name}. Restore card undoes it');
  }

  OpResult _formatBlank(MemoryCard card) {
    final f = File(card.path);
    if (!f.existsSync()) return _no("That card isn't there any more");
    final was = f.readAsBytesSync();
    final ext = p.extension(card.path).replaceFirst('.', '').toLowerCase();
    if (!CardImage.isBlankPs2(was, ext)) {
      return _no("That card isn't blank any more. Open the Save Manager again");
    }
    final no = store.change(
      card.path,
      was,
      blankLike(card.system, was),
      'format',
      Ps2Writer.check,
    );
    return no.isNotEmpty
        ? _no(no)
        : _yes("Formatted ${card.name}: it's ready for saves");
  }

  OpResult newCard(MemoryCard like) {
    // a new card goes beside it: not among the PC's copies
    if (_locked(like.path)) return _no(CardSafety.readOnlyNotice);
    if (like.system == 'PS3') {
      // a PS3 copies saves to a USB stick: RPCS3's own is dev_usb000
      final usb = ps3UsbFor(like.path);
      if (usb.isEmpty) {
        return _no("Couldn't tell where RPCS3 is from that save folder");
      }
      if (Directory(usb).existsSync()) {
        return _no('The PS3 USB stick is there already');
      }
      final made = store.makeFolder(usb);
      return made.isNotEmpty
          ? _no(made)
          : _yes('Made the PS3 USB stick: copy saves to it to keep them safe');
    }
    final now = openCard(like);
    if (now.error.isNotEmpty) return _no(now.error);
    if (like.isFolder) return _no(folderNo);
    var blank = blankLike(like.system, now.bytes);
    if (blank.isEmpty) return _no("That size of card can't be made here");
    var ext = p.extension(like.path).replaceFirst('.', '');
    if (like.offset > 0) {
      ext = 'mpk'; // a single pak, out of a shared file
    } else if (like.gzip ||
        like.system == 'SATURN' ||
        like.system == 'NEO GEO') {
      blank = CardImage.put(now.file, now.card, blank);
    }
    final path = _freePath(
      p.join(p.dirname(like.path), 'New ${like.system} card'),
      ext,
    );
    final no = store.create(
      path,
      blank,
      _fileCheck(_fresh(like, blank.length, alone: true)),
    );
    return no.isNotEmpty ? _no(no) : _yes('Made ${p.basename(path)}');
  }

  OpResult duplicateCard(MemoryCard card) {
    if (_locked(card.path)) return _no(CardSafety.readOnlyNotice);
    final now = openCard(card);
    if (now.error.isNotEmpty) return _no(now.error);
    if (card.isFolder) return _no(folderNo);
    final path = _freePath(
      '${p.withoutExtension(card.path)} (copy)',
      p.extension(card.path).replaceFirst('.', ''),
    );
    final no = store.create(path, now.file, _fileCheck(now.card));
    return no.isNotEmpty ? _no(no) : _yes('Made ${p.basename(path)}');
  }

  OpResult checkCard(MemoryCard card) {
    final now = openCard(card);
    if (now.error.isNotEmpty) return _no(now.error);
    if (card.isFolder) {
      for (final s in now.card.saves) {
        final pack = exportBytes(now, s.id);
        if (!pack.ok) return _no('Problem found: ${pack.error}');
      }
      return _yes('No damage found');
    }
    final bad = check(card.system, now.bytes);
    return bad.isNotEmpty
        ? _no('Problem found: $bad')
        : _yes('No damage found');
  }

  // ---- reading -------------------------------------------------------------

  LiveCard openCard(MemoryCard card) {
    final out = LiveCard();
    if (card.isFolder) {
      if (card.system != 'GC' && card.system != 'PS3') {
        out.error = folderPs2;
      } else if (!Directory(card.path).existsSync()) {
        out.error = "That card isn't there any more";
      } else if (card.system == 'PS3') {
        out.card = Ps3Card.parseFolder(
          card.path,
          MemoryCard()..name = card.name,
        );
      } else {
        out.card = GcCard.parseFolder(
          card.path,
          MemoryCard()
            ..path = card.path
            ..name = card.name,
        );
      }
      return out;
    }
    final f = File(card.path);
    if (!f.existsSync()) {
      out.error = "That card isn't there any more";
      return out;
    }
    out.file = f.readAsBytesSync();
    final fresh = _fresh(card, out.file.length);
    out.bytes = CardImage.take(out.file, fresh);
    if (out.bytes.isEmpty) {
      out.error = "That card can't be read";
      return out;
    }
    out.card = MemoryCards.parse(out.bytes, fresh);
    if (out.card.error.isNotEmpty) {
      out.error = "That card can't be read (${out.card.error})";
    }
    return out;
  }

  CardEdit exportBytes(LiveCard from, String id) {
    final s = from.find(id);
    if (s == null) return CardEdit.fail("That save isn't on the card any more");
    if (!from.card.isFolder) return exportFrom(from.card.system, from.bytes, s);
    if (from.card.system == 'PS3') {
      return ps3Pack(p.join(from.card.path, s.file));
    }
    final f = File(p.join(from.card.path, s.file));
    final bytes = f.existsSync() ? f.readAsBytesSync() : Uint8List(0);
    final bad = _gciCheck(bytes);
    return bad.isNotEmpty
        ? CardEdit.fail('${s.file} is $bad')
        : CardEdit.done(bytes);
  }

  /// A PS3 save's folder as a zip. Fails on sub-folders: PS3 saves have none.
  static CardEdit ps3Pack(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) {
      return CardEdit.fail("That save isn't on the card any more");
    }
    final entries = d.listSync();
    if (entries.whereType<Directory>().isNotEmpty) {
      return CardEdit.fail(
        "That save's folder has folders inside it, so it isn't a PS3 save",
      );
    }
    final files = entries.whereType<File>().toList();
    if (files.length > Ps3Writer.maxFiles) {
      return CardEdit.fail('That save has too many files to be a PS3 save');
    }
    return Ps3Writer.pack(p.basename(dir), {
      for (final f in files) p.basename(f.path): f.readAsBytesSync(),
    });
  }

  /// A zip made by another tool (compressed): packed again our plain way.
  static CardEdit ps3FromZip(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return CardEdit.fail("That zip can't be opened");
    }
    var folder = '';
    final files = <String, List<int>>{};
    for (final entry in zip.files) {
      if (!entry.isFile) continue;
      final parts = entry.name.split('/').where((x) => x.isNotEmpty).toList();
      if (parts.length != 2 || (folder.isNotEmpty && parts[0] != folder)) {
        return CardEdit.fail(
          'That zip should hold one PS3 save folder, nothing else',
        );
      }
      folder = parts[0];
      files[parts[1]] = entry.content;
    }
    return Ps3Writer.pack(folder, files);
  }

  /// A save from the internet, in its console's usual file.
  static CardEdit saveFile(String system, String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    Uint8List? read(String at) {
      final f = File(at);
      try {
        return f.lengthSync() > importMax ? null : f.readAsBytesSync();
      } catch (_) {
        return null;
      }
    }

    if (system == 'PS3' && ext == 'zip') {
      final bytes = read(path);
      if (bytes == null) return CardEdit.fail("That file can't be read");
      return Ps3Writer.check(bytes).isEmpty
          ? CardEdit.done(bytes)
          : ps3FromZip(bytes);
    }
    final pair = system == 'DC' && (ext == 'vmi' || ext == 'vms');
    if (!pair && ext != saveExt[system]) {
      return CardEdit.fail("That file isn't a $system save");
    }
    final bytes = read(path);
    if (bytes == null) return CardEdit.fail("That file can't be read");
    if (!pair) return CardEdit.done(bytes);
    final other = read(
      '${p.withoutExtension(path)}.${ext == 'vmi' ? 'vms' : 'vmi'}',
    );
    if (other == null) {
      return CardEdit.fail(
        'A Dreamcast save needs its .vmi and its .vms side by side',
      );
    }
    return ext == 'vmi'
        ? VmuWriter.fromVmi(bytes, other)
        : VmuWriter.fromVmi(other, bytes);
  }

  // ---- the writers ---------------------------------------------------------

  static CardEdit exportFrom(String system, Uint8List d, CardSave s) =>
      switch (system) {
        'PS1' => Ps1Writer.exportSave(d, s.slot),
        'PS2' => Ps2Writer.exportSave(d, s.id),
        'DC' => VmuWriter.exportSave(d, s.slot),
        'GC' => GcWriter.exportSave(d, s.slot),
        'N64' => PakWriter.exportSave(d, s.slot),
        'SATURN' => SaturnWriter.exportSave(d, s.slot),
        'NEO GEO' => NeoWriter.exportSave(d, s.slot),
        _ => CardEdit.fail('Unknown console'),
      };

  static CardEdit deleteFrom(String system, Uint8List d, CardSave s) =>
      switch (system) {
        'PS1' => Ps1Writer.delete(d, s.slot),
        'PS2' => Ps2Writer.delete(d, s.id),
        'DC' => VmuWriter.delete(d, s.slot),
        'GC' => GcWriter.delete(d, s.slot),
        'N64' => PakWriter.delete(d, s.slot),
        'SATURN' => SaturnWriter.delete(d, s.slot),
        'NEO GEO' => NeoWriter.delete(d, s.slot),
        _ => CardEdit.fail('Unknown console'),
      };

  static CardEdit importInto(
    String system,
    Uint8List d,
    Uint8List pack,
    Uint8List serial,
  ) => switch (system) {
    'PS1' => Ps1Writer.importSave(d, pack),
    'PS2' => Ps2Writer.importSave(d, pack),
    'DC' => VmuWriter.importSave(d, pack),
    'GC' => GcWriter.importSave(d, pack, serial),
    'N64' => PakWriter.importSave(d, pack),
    'SATURN' => SaturnWriter.importSave(d, pack),
    'NEO GEO' => NeoWriter.importSave(d, pack),
    _ => CardEdit.fail('Unknown console'),
  };

  static String check(String system, Uint8List d) => switch (system) {
    'PS1' => Ps1Writer.check(d),
    'PS2' => Ps2Writer.check(d),
    'DC' => VmuWriter.check(d),
    'GC' => GcWriter.check(d),
    'N64' => PakWriter.check(d),
    'SATURN' => SaturnWriter.check(d),
    'NEO GEO' => NeoWriter.check(d),
    'PS3' => Ps3Writer.check(d),
    _ => 'an unknown console',
  };

  /// An empty card of the same kind and size, keeping what identifies it
  /// (serial, region). Empty = can't be made that size.
  static Uint8List blankLike(String system, Uint8List d) {
    var out = Uint8List(0);
    switch (system) {
      case 'PS1':
        out = Ps1Writer.blank();
      case 'PS2':
        out = Ps2Writer.blank(d.length != Ps2Writer.total * 2 * Ps2Writer.page);
      case 'DC':
        out = VmuWriter.blank();
      case 'GC':
        out = GcWriter.blank(d.length ~/ GcWriter.mbit);
        if (out.isNotEmpty && GcWriter.isCard(d)) {
          out.setRange(0, GcWriter.block, d);
        }
      case 'N64':
        out = PakWriter.blank();
        if (PakWriter.idFine(d)) out.setRange(0, PakWriter.page, d);
      case 'SATURN':
        out = SaturnWriter.blank(d.length);
      case 'NEO GEO':
        if (d.length > 0x30) out = NeoWriter.blank(d[0x30], d.length);
    }
    return out.length == d.length ? out : Uint8List(0);
  }

  /// The id the reader would give this save file: what "same name" means.
  static String idIn(String system, Uint8List pack) {
    switch (system) {
      case 'PS1':
        return Bytes.ascii(pack, Ps1Writer.nameAt, 20);
      case 'PS2':
        return Bytes.ascii(pack, Ps2Writer.nameAt, Ps2Writer.nameLen);
      case 'DC':
        return Bytes.ascii(pack, VmuWriter.nameAt, VmuWriter.nameLen).trim();
      case 'GC':
        return '${Bytes.ascii(pack, 0, 6)} ${Bytes.ascii(pack, GcWriter.nameAt, GcWriter.nameLen)}';
      case 'N64':
        var title = PakCard.n64Text(pack, 0x10, 16);
        final ext = PakCard.n64Text(pack, 0x0C, 4);
        if (ext.isNotEmpty) title += '.$ext';
        return '${Bytes.ascii(pack, 0, 4)}${Bytes.ascii(pack, 4, 2)} $title';
      case 'SATURN':
        return Bytes.ascii(pack, 0x10, SaturnWriter.nameLen);
      case 'NEO GEO':
        final ngh = Bytes.be16(
          pack,
          1,
        ).toRadixString(16).toUpperCase().padLeft(3, '0');
        return 'NGH-$ngh #${Bytes.u8(pack, 0) + 1}';
      case 'PS3':
        return Ps3Writer.idIn(pack);
    }
    return '';
  }

  /// A save's id as a file name Windows takes. Ids come out of other
  /// people's files.
  static String fileSafe(String id) {
    final sb = StringBuffer();
    for (final c in id.split('')) {
      final fine = RegExp(r'[a-zA-Z0-9 \-_#()]').hasMatch(c);
      sb.write(fine ? c : '_');
    }
    var out = sb.toString().trim();
    if (out.length > 80) out = out.substring(0, 80);
    final reserved = RegExp(
      r'^(con|prn|aux|nul|com\d|lpt\d)$',
      caseSensitive: false,
    ).hasMatch(out);
    return out.isEmpty || reserved ? 'save $out' : out;
  }

  /// ".../RPCS3/dev_hdd0/home/00000001/savedata" ->
  /// ".../RPCS3/dev_usb000/PS3/SAVEDATA" ('' = not RPCS3's).
  static String ps3UsbFor(String savedata) {
    final s = savedata.replaceAll(r'\', '/');
    final at = s.toLowerCase().lastIndexOf('/dev_hdd0/');
    return at >= 0 ? p.join(s.substring(0, at), Ps3Card.usbSaves) : '';
  }

  // ---- inside --------------------------------------------------------------

  OpResult _takeIn(MemoryCard card, Uint8List pack, bool replace, String what) {
    final to = openCard(card);
    if (to.error.isNotEmpty) return _no(to.error);
    final id = idIn(card.system, pack);
    var serial = Uint8List(0);
    if (what == 'restore' && card.system == 'GC' && !card.isFolder) {
      serial = GcWriter.serial(
        to.bytes,
      ); // back onto the card it was backed up from
    }
    final out = _putIn(to, [id], [pack], replace, serial, what);
    return out.ok ? _yes("It's on ${card.name} now") : out;
  }

  OpResult _putIn(
    LiveCard to,
    List<String> ids,
    List<Uint8List> packs,
    bool replace,
    Uint8List serial,
    String what,
  ) {
    final clash = <String>[];
    for (final id in ids) {
      if (to.find(id) != null) {
        clash.add(id);
      } else if (to.card.isFolder &&
          to.card.saves.any((s) => s.id.startsWith('$id ['))) {
        return _no(
          'That folder has several copies of this save. Delete the extras first',
        );
      }
    }
    final keep = favoriteAmong(to, clash);
    if (keep.isNotEmpty) return _no(keep);
    if (clash.isNotEmpty && !replace) {
      final many = clash.length == 1 ? "It's" : '${clash.length} are';
      return _no('$many already on ${to.card.name}')..conflicts = clash;
    }
    if (to.card.isFolder) {
      final no = _putInFolder(to, ids, packs, what);
      return no.isNotEmpty ? _no(no) : _yes('');
    }
    var d = to.bytes;
    for (final id in clash) {
      final cut = deleteFrom(to.card.system, d, to.find(id)!);
      if (!cut.ok) return _no(cut.error);
      d = cut.data;
    }
    for (final pack in packs) {
      final put = importInto(to.card.system, d, pack, serial);
      if (!put.ok) return _no(put.error);
      d = put.data;
    }
    var no = _keepSaves(to, clash, 'replaced');
    if (no.isEmpty) no = _commit(to, d, what);
    return no.isNotEmpty ? _no(no) : _yes('');
  }

  /// One of several same-named .gci goes back as the file it was.
  OpResult _backAsFile(
    MemoryCard card,
    String file,
    Uint8List bytes,
    bool replace,
  ) {
    final bad = _gciCheck(bytes);
    if (bad.isNotEmpty) return _no('That backup is $bad');
    final path = p.join(card.path, file);
    final f = File(path);
    String no;
    if (f.existsSync()) {
      final live = openCard(card);
      if (live.error.isEmpty) {
        for (final s in live.card.saves) {
          if (s.file.toLowerCase() == file.toLowerCase()) {
            final keep = favoriteAmong(live, [s.id]);
            if (keep.isNotEmpty) return _no(keep);
          }
        }
      }
      if (!replace) return _no('$file is already there')..conflicts = [file];
      no = store.change(
        path,
        f.readAsBytesSync(),
        bytes,
        'before restore',
        _gciCheck,
      );
    } else {
      no = store.create(path, bytes, _gciCheck);
    }
    return no.isNotEmpty ? _no(no) : _yes("It's on ${card.name} now");
  }

  /// The file in "GAME name [file.gci]", only if it's a plain file name.
  static String namedFile(String key) {
    final at = key.lastIndexOf(' [');
    if (at < 0 || !key.endsWith(']')) return '';
    final file = key.substring(at + 2, key.length - 1);
    final plain =
        !file.contains('/') && !file.contains(r'\') && !file.contains(':');
    return plain && file.toLowerCase().endsWith('.gci') ? file : '';
  }

  /// '' = none of these is a favorite. An unreadable list counts as all.
  String favoriteAmong(LiveCard on, List<String> ids) {
    if (ids.isEmpty) return '';
    favorites.reload();
    if (favorites.error.isNotEmpty) return favorites.error;
    for (final id in ids) {
      final s = on.find(id);
      if (s != null && favorites.has(on.card, s)) {
        return kept(s.titleLines.isNotEmpty ? s.titleLines.first : s.id);
      }
    }
    return '';
  }

  /// An older card may come back only if every favorite on it now is in
  /// there just as it is.
  String _favoritesSurvive(MemoryCard card, Uint8List was) {
    favorites.reload();
    if (favorites.error.isNotEmpty) return favorites.error;
    final now = openCard(card);
    if (now.error.isNotEmpty) {
      return ''; // a card too damaged to read stays restorable
    }
    final old = MemoryCards.parse(was, _fresh(card, was.length, alone: true));
    final from = entryBytes[card.system]!;
    for (final s in now.card.saves) {
      if (!favorites.has(now.card, s)) continue;
      var same = false;
      for (final then in old.saves) {
        if (then.id != s.id) continue;
        final a = exportFrom(card.system, now.bytes, s);
        final b = exportFrom(card.system, was, then);
        same =
            a.ok &&
            b.ok &&
            a.data.length >= from &&
            b.data.length >= from &&
            Bytes.same(a.data.sublist(from), b.data.sublist(from));
      }
      if (!same) {
        return kept(s.titleLines.isNotEmpty ? s.titleLines.first : s.id);
      }
    }
    return '';
  }

  String _putInFolder(
    LiveCard to,
    List<String> ids,
    List<Uint8List> packs,
    String what,
  ) {
    if (to.card.system == 'PS3') return _putInPs3(to, ids, packs, what);
    for (final pack in packs) {
      // every one checked before the first is written
      final bad = _gciCheck(pack);
      if (bad.isNotEmpty) return 'That save file is $bad';
      if (GcWriter.tiedToCard.contains(Bytes.ascii(pack, 0, 4))) {
        return "This game locks its save to the card it was made on, so a copy wouldn't load";
      }
    }
    for (var i = 0; i < packs.length; i++) {
      final old = to.find(ids[i]);
      var no = '';
      if (old != null) {
        no = _keepSaves(to, [ids[i]], 'replaced');
        if (no.isEmpty) {
          final path = p.join(to.card.path, old.file);
          no = store.change(
            path,
            File(path).readAsBytesSync(),
            packs[i],
            what,
            _gciCheck,
          );
        }
      } else {
        no = store.create(
          _freePath(p.join(to.card.path, fileSafe(ids[i])), 'gci'),
          packs[i],
          _gciCheck,
        );
      }
      if (no.isNotEmpty) return no;
    }
    return '';
  }

  /// PS3: each zip becomes its folder. Every one is checked before the
  /// first is written; one already there is backed up and then changed
  /// file by file, so it ends up exactly as the zip has it.
  String _putInPs3(
    LiveCard to,
    List<String> ids,
    List<Uint8List> packs,
    String what,
  ) {
    final unpacked =
        <({String name, Map<String, Uint8List> files, String error})>[];
    for (var i = 0; i < packs.length; i++) {
      final got = Ps3Writer.unpack(packs[i]);
      if (got.error.isNotEmpty) {
        return 'That PS3 save is damaged (${got.error})';
      }
      if (got.name != ids[i]) {
        return "That PS3 save isn't the one that was chosen";
      }
      unpacked.add(got);
    }
    for (var i = 0; i < unpacked.length; i++) {
      final dir = p.join(to.card.path, unpacked[i].name);
      var no = store.makeFolder(dir);
      if (no.isEmpty && to.find(ids[i]) != null) {
        no = _keepSaves(to, [ids[i]], 'replaced');
      }
      if (no.isNotEmpty) return no;
      final files = unpacked[i].files;
      for (final e in files.entries) {
        final f = File(p.join(dir, e.key));
        no = f.existsSync()
            ? store.change(f.path, f.readAsBytesSync(), e.value, what, _any)
            : store.create(f.path, e.value, _any);
        if (no.isNotEmpty) return no;
      }
      for (final f in Directory(dir).listSync().whereType<File>()) {
        // what the old save had and this one doesn't
        if (files.containsKey(p.basename(f.path))) continue;
        no = store.remove(f.path, f.readAsBytesSync(), what);
        if (no.isNotEmpty) return no;
      }
    }
    return '';
  }

  /// A PS3 save folder goes: each file through the store (so each is backed
  /// up), then the empty folder.
  String _removePs3(String dir, String what) {
    final d = Directory(dir);
    if (!d.existsSync()) return "That save isn't on the card any more";
    for (final f in d.listSync().whereType<File>()) {
      final no = store.remove(f.path, f.readAsBytesSync(), what);
      if (no.isNotEmpty) return no;
    }
    return store.removeFolder(dir);
  }

  String _remove(LiveCard from, List<String> ids, String what) {
    if (from.card.isFolder) {
      for (final id in ids) {
        final s = from.find(id);
        if (s == null) return "That save isn't on the card any more";
        final path = p.join(from.card.path, s.file);
        final no = from.card.system == 'PS3'
            ? _removePs3(path, what)
            : store.remove(path, File(path).readAsBytesSync(), what);
        if (no.isNotEmpty) return no;
      }
      return '';
    }
    var d = from.bytes;
    for (final id in ids) {
      final s = from.find(id);
      if (s == null) return "That save isn't on the card any more";
      final cut = deleteFrom(from.card.system, d, s);
      if (!cut.ok) return cut.error;
      d = cut.data;
    }
    return _commit(from, d, what);
  }

  String _keepSaves(LiveCard from, List<String> ids, String what) {
    for (final id in ids) {
      final pack = exportBytes(from, id);
      if (!pack.ok) return pack.error;
      final no = store.backUp(from.card.key() + saveMark + id, pack.data, what);
      if (no.isNotEmpty) return no;
    }
    return '';
  }

  String _backUpCard(MemoryCard card) {
    if (!card.isFolder) {
      final f = File(card.path);
      if (!f.existsSync()) return "it isn't there any more";
      return store.backUp(card.path, f.readAsBytesSync(), 'backup');
    }
    final now = openCard(card);
    if (now.error.isNotEmpty) return now.error;
    return _keepSaves(now, [for (final s in now.card.saves) s.id], 'backup');
  }

  String _commit(LiveCard on, Uint8List bytes, String what) {
    final bad = check(on.card.system, bytes);
    if (bad.isNotEmpty) {
      return "The changed card didn't pass its check ($bad), so nothing was written";
    }
    final file = CardImage.put(on.file, on.card, bytes);
    if (file.isEmpty) return "The changed card doesn't fit back into its file";
    return store.change(on.card.path, on.file, file, what, _fileCheck(on.card));
  }

  /// Checks the card inside a file that's about to be written.
  static Check _fileCheck(MemoryCard card) => (file) {
    final inside = CardImage.take(file, _fresh(card, file.length));
    return inside.isNotEmpty ? check(card.system, inside) : 'unreadable';
  };

  static String _gciCheck(Uint8List b) {
    if (b.length <= GcCard.entrySize ||
        b.length != GcCard.entrySize + Bytes.be16(b, 0x38) * GcWriter.block) {
      return 'not a whole .gci';
    }
    return '';
  }

  /// A PS3 save's own files: the whole save was checked as a zip first.
  static String _any(Uint8List _) => '';

  static String _notEmpty(Uint8List b) => b.isEmpty ? 'empty' : '';

  /// The same card, ready to be parsed again. A gzipped card's file changes
  /// size with every write.
  static MemoryCard _fresh(
    MemoryCard card,
    int fileSize, {
    bool alone = false,
  }) {
    final shared =
        !alone && card.system == 'N64' && card.span > 0 && card.span < fileSize;
    return MemoryCard()
      ..system = card.system
      ..name = card.name
      ..path = card.path
      ..modified = card.modified
      ..gzip = card.gzip
      ..offset = alone ? 0 : card.offset
      ..span = shared ? card.span : fileSize;
  }

  static String _freePath(String base, String ext) {
    var path = '$base.$ext';
    for (
      var n = 2;
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
      n++
    ) {
      path = '$base $n.$ext';
    }
    return path;
  }

  static String _saves(int n) => n == 1 ? '1 save' : '$n saves';
  static OpResult _yes(String text) => OpResult(true, text);
  static OpResult _no(String text) => OpResult(false, text);
}
