/// No browser back button outside the web: back is the platform's own.
class BackGuard {
  void start(void Function() onBack) {}

  void leave() {}
}
