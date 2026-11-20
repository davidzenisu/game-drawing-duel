/// The parts of the browser's session history `BrowserBack` works with.
///
/// The app marks each entry it adds with its [BrowserEntry]: its index
/// counted from the entry the app opened on (0).
abstract interface class BrowserHistory {
  /// The app's mark on the current entry, null if it has none.
  BrowserEntry? get current;

  /// Marks the current entry with [entry], keeping its address.
  void replace(BrowserEntry entry);

  /// Adds an entry marked with [entry] after the current one, with the
  /// same address, dropping the entries forward of it.
  void push(BrowserEntry entry);

  /// Moves [delta] entries back (negative) or forward, like the browser's
  /// buttons. [onPop] reports where it lands, unless that's another page.
  void go(int delta);

  /// Called with the mark of the entry the browser moved to within the app
  /// (back, forward or [go]), null if it has none.
  set onPop(void Function(BrowserEntry? entry)? callback);

  /// Called when the page comes back from the browser's cache, e.g. with
  /// forward after leaving it.
  set onRestore(void Function()? callback);
}

/// The app's mark on a history entry.
class BrowserEntry {
  const BrowserEntry(this.index, {this.skip = 0});

  /// The entry's index counted from the entry the app opened on.
  final int index;

  /// How many entries before the one the app opened on were the app's
  /// too, from before a reload: leaving the game goes back past them.
  final int skip;

  @override
  bool operator ==(Object other) => other is BrowserEntry && other.index == index && other.skip == skip;

  @override
  int get hashCode => Object.hash(index, skip);

  @override
  String toString() => 'BrowserEntry($index, skip: $skip)';
}
