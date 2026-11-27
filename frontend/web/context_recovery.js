// Brings the app back when the browser drops Flutter's WebGL context.
//
// Android may take the GPU context of a page in the background (another app,
// a locked phone, another tab). Flutter then draws nothing: the page stays
// alive but blank. This script watches every WebGL context the page creates;
// when one is lost and not restored, it reloads the page once the app is
// visible again, so the player never has to close the app to get it back.
//
// It runs before Flutter starts, so it sees the contexts Flutter creates.
(function () {
  'use strict';

  // How long a lost context gets to come back before the page reloads.
  var RESTORE_GRACE_MS = 1000;
  // Never reload again within this time of the last recovery reload.
  var RELOAD_COOLDOWN_MS = 10000;
  var RELOADED_AT_KEY = 'drawing-duel:context-recovery-reloaded-at';

  var lost = new Set();
  var timer = null;

  function visible() {
    return document.visibilityState === 'visible';
  }

  // Milliseconds until the cooldown of the last recovery reload ends.
  function cooldownLeft() {
    try {
      var at = Number(sessionStorage.getItem(RELOADED_AT_KEY));
      return at > 0 ? Math.max(0, at + RELOAD_COOLDOWN_MS - Date.now()) : 0;
    } catch (_) {
      return 0;
    }
  }

  function reload() {
    try {
      sessionStorage.setItem(RELOADED_AT_KEY, String(Date.now()));
    } catch (_) {
      // Without session storage, the cooldown is skipped.
    }
    window.location.reload();
  }

  // Reloads after the grace time if a context is still lost and the app shows.
  // Right after a recovery reload, waits for the cooldown to end instead, so
  // a context that keeps getting lost can't reload the page in a loop.
  function check() {
    if (timer !== null || lost.size === 0 || !visible()) return;
    timer = setTimeout(function () {
      timer = null;
      if (lost.size === 0 || !visible()) return;
      if (cooldownLeft() > 0) {
        timer = setTimeout(function () {
          timer = null;
          check();
        }, cooldownLeft());
        return;
      }
      reload();
    }, RESTORE_GRACE_MS);
  }

  function watch(canvas) {
    if (!canvas || canvas.__drawingDuelWatched) return;
    canvas.__drawingDuelWatched = true;
    canvas.addEventListener('webglcontextlost', function () {
      lost.add(canvas);
      check();
    });
    canvas.addEventListener('webglcontextrestored', function () {
      lost.delete(canvas);
    });
  }

  function patch(prototype) {
    if (!prototype || typeof prototype.getContext !== 'function') return;
    var getContext = prototype.getContext;
    prototype.getContext = function (type) {
      var context = getContext.apply(this, arguments);
      try {
        if (context && typeof type === 'string' && type.indexOf('webgl') === 0) watch(this);
      } catch (_) {
        // Watching is best effort; the context is returned either way.
      }
      return context;
    };
  }

  try {
    patch(window.HTMLCanvasElement && window.HTMLCanvasElement.prototype);
    patch(window.OffscreenCanvas && window.OffscreenCanvas.prototype);
    document.addEventListener('visibilitychange', check);
    window.addEventListener('pageshow', check);
    window.addEventListener('focus', check);
  } catch (_) {
    // An old browser: the app runs, without the recovery.
  }
})();
