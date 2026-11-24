/// How the pet feels (each has its own animation).
enum Mood {
  idle('Content'),
  happy('Happy'),
  sleepy('Sleepy'),
  asleep('Asleep'),
  hungry('Hungry'),
  eating('Eating'),
  bored('Bored'),
  scared('Scared');

  const Mood(this.label);
  final String label;
}

/// What the weather adds to the picture.
enum WeatherLook {
  none('No weather'),
  clear('Clear'),
  sun('Hot and sunny'),
  cloud('Cloudy'),
  fog('Foggy'),
  rain('Rain'),
  snow('Snow'),
  storm('Thunderstorm');

  const WeatherLook(this.label);
  final String label;
}
