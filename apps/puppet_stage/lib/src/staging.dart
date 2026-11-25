import 'animals.dart';
import 'cast.dart';
import 'figure.dart';
import 'movie.dart';
import 'places.dart';
import 'props.dart';

/// The figure for a built-in actor (a person, animal or prop; not an
/// imported model, which needs its file).
Figure builtFigure(Actor a) {
  final Figure fig;
  final animal = a.animal, prop = a.prop;
  if (prop != null) {
    fig = PropFigure(buildProp(prop, a.look), scale: a.scale);
  } else if (animal != null) {
    fig = BuiltFigure(
      buildAnimal(animal, a.look),
      labels: {'call': animal.call},
    );
  } else {
    fig = BuiltFigure(
      buildCharacter(a.kind, a.look, body: a.body, extras: a.extras),
    );
  }
  fig.root.scale.setValues(a.scale, a.scale, a.scale);
  fig.hold(a.holds);
  return fig;
}

/// A whole movie built for rendering without the app (tools and tests):
/// every place, every built-in actor in its place.
class Staging {
  Staging._(this.movie, this.places, this.figures);
  final Movie movie;
  final List<BuiltPlace> places;
  final Map<String, Figure> figures;

  static Future<Staging> build(Movie m) async {
    final places = [
      for (var i = 0; i < m.placeCount; i++) await buildPlace(m.placeAt(i)),
    ];
    final figures = <String, Figure>{};
    for (final a in m.actors) {
      if (a.model != null) continue;
      final f = figures[a.id] = builtFigure(a);
      places[a.place.clamp(0, places.length - 1)].scene.root.add(f.root);
    }
    return Staging._(m, places, figures);
  }

  /// Poses everyone at [t].
  void pose(double t) {
    for (final a in movie.actors) {
      final f = figures[a.id];
      if (f == null) continue;
      final st = stateAt(a, t);
      final ground = places[a.place.clamp(0, places.length - 1)].ground(
        st.x,
        st.z,
      );
      f.show(st, groundY: ground, now: t);
    }
  }
}
