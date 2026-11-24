import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'art/species.dart';
import 'pet.dart';
import 'weather.dart';

/// A pet drawn in Pixel Forge (its frames, flattened).
class CustomSprite {
  const CustomSprite(this.name, this.width, this.height, this.frames);
  final String name;
  final int width, height;
  final List<Uint32List> frames;

  Map<String, Object?> toJson() => {
    'name': name,
    'w': width,
    'h': height,
    'frames': [
      for (final f in frames)
        base64Encode(f.buffer.asUint8List(f.offsetInBytes, f.lengthInBytes)),
    ],
  };

  factory CustomSprite.fromJson(Map j) {
    final w = (j['w'] as num).toInt(), h = (j['h'] as num).toInt();
    return CustomSprite((j['name'] as String?) ?? 'My pet', w, h, [
      for (final f in (j['frames'] as List))
        Uint8List.fromList(base64Decode(f as String)).buffer
            .asUint32List(0, w * h),
    ]);
  }
}

/// Everything saved: the pet, where to get weather, the last weather, and a
/// custom sprite if one is used.
class PetData {
  PetData({PetState? pet, this.place, this.weather, this.custom})
    : pet = pet ?? PetState();

  final PetState pet;
  Place? place;
  Weather? weather;
  CustomSprite? custom;

  PetSpecies get species {
    final c = custom;
    if (pet.species == 'custom' && c != null) {
      return SpritePet(c.name, c.frames, c.width, c.height);
    }
    return speciesById(pet.species) ?? builtInSpecies.first;
  }

  Map<String, Object?> toJson() => {
    'pet': pet.toJson(),
    'place': place?.toJson(),
    'weather': weather?.toJson(),
    'custom': custom?.toJson(),
  };

  factory PetData.fromJson(Map j) => PetData(
    pet: j['pet'] is Map ? PetState.fromJson(j['pet'] as Map) : null,
    place: j['place'] is Map ? Place.fromJson(j['place'] as Map) : null,
    weather: j['weather'] is Map ? Weather.fromJson(j['weather'] as Map) : null,
    custom: j['custom'] is Map
        ? CustomSprite.fromJson(j['custom'] as Map)
        : null,
  );
}

/// Saves the pet where both the app and the home-screen widget's
/// background code can find it.
class PetStore {
  PetStore(this.dir);

  static Future<PetStore> open() async {
    final base = await getApplicationSupportDirectory();
    return PetStore(Directory('${base.path}${Platform.pathSeparator}pet'));
  }

  final Directory dir;
  File get _file => File('${dir.path}${Platform.pathSeparator}pet.json');

  Future<PetData> load() async {
    try {
      if (await _file.exists()) {
        return PetData.fromJson(jsonDecode(await _file.readAsString()) as Map);
      }
    } catch (_) {
      // Broken save: keep a copy and start again.
      try {
        await _file.copy('${_file.path}.broken');
      } catch (_) {}
    }
    return PetData();
  }

  Future<void> save(PetData d) async {
    await dir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(d.toJson()));
    await tmp.rename(_file.path);
  }
}
