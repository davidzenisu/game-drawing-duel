// Keeps a pen stroke going when the browser briefly reports the pen as not
// pressed while it's still on the screen.
//
// Chrome on Android may send a pen's first moves after it touches down with
// `buttons: 0` (pressure still near zero), then `buttons: 1`. Flutter's web
// engine reads a move without buttons as the button let go without a
// `pointerup` (meant for a right-click's context menu): it ends the stroke
// there, and takes the rest of the pen's moves as hovering. The stroke stays
// a dot or a short dash.
//
// Between a pen's `pointerdown` and its `pointerup` or `pointercancel`, this
// makes a move without buttons (and each of its coalesced moves) read as the
// pen touching, before Flutter sees it. It runs before Flutter starts and
// listens in the capture phase on window, so it's first for every event.
// Issue #349.
(function () {
  'use strict';

  var down = new Set();
  // How many moves it changed, for the ?pentest diagnostics (#349).
  window.__penFixPatched = 0;

  function touching(event) {
    if (event.buttons !== 0) return;
    try {
      Object.defineProperty(event, 'buttons', { value: 1, configurable: true });
      window.__penFixPatched++;
    } catch (_) {
      // Left as it is: the stroke may end early, as before.
    }
  }

  try {
    window.addEventListener('pointerdown', function (event) {
      if (event.pointerType === 'pen') down.add(event.pointerId);
    }, true);
    ['pointerup', 'pointercancel'].forEach(function (type) {
      window.addEventListener(type, function (event) {
        down.delete(event.pointerId);
      }, true);
    });
    window.addEventListener('pointermove', function (event) {
      if (event.pointerType !== 'pen' || !down.has(event.pointerId)) return;
      touching(event);
      if (typeof event.getCoalescedEvents !== 'function') return;
      // Flutter reads the coalesced moves when there are any: fix those, and
      // hand Flutter the same, fixed ones.
      var coalesced = event.getCoalescedEvents();
      coalesced.forEach(touching);
      try {
        Object.defineProperty(event, 'getCoalescedEvents', {
          value: function () { return coalesced; },
          configurable: true,
        });
      } catch (_) {
        // Flutter reads fresh coalesced moves; the stroke may end early.
      }
    }, true);
  } catch (_) {
    // An old browser: the app runs, without the fix.
  }
})();
