// TEMPORARY diagnostic for issue #349 (pen strokes cut short); remove before
// merging. Only runs with ?pentest in the address. Logs, for each pointer,
// how its stroke ended (up or cancel), after how many moves and how far,
// what it landed on, and the browser events around it, in an overlay that
// lets every touch through (newest line first).
(function () {
  'use strict';
  // Kept for the tab, so it survives the sign-in's redirects.
  var KEY = 'drawing-duel:pentest';
  try {
    if (location.search.indexOf('pentest') >= 0) sessionStorage.setItem(KEY, '1');
    if (!sessionStorage.getItem(KEY)) return;
  } catch (_) {
    if (location.search.indexOf('pentest') < 0) return;
  }

  var lines = [];
  var active = {};
  var box = null;
  var t0 = performance.now();
  // What Flutter reports getting (main.dart's _PenLog), per stroke.
  var flt = {};
  var consoleLog = console.log;
  console.log = function () {
    var text = String(arguments[0]);
    if (text.indexOf('FLT ') === 0) {
      flt[text.slice(4)] = (flt[text.slice(4)] || 0) + 1;
      return;
    }
    return consoleLog.apply(console, arguments);
  };

  function ms() { return Math.round(performance.now() - t0); }

  function show() {
    if (!box) {
      box = document.createElement('div');
      box.style.cssText = 'position:fixed;left:0;right:0;top:0;max-height:33%;overflow:hidden;' +
        'background:rgba(0,0,0,.78);color:#0f0;font:11px/1.3 monospace;white-space:pre-wrap;' +
        'padding:4px;z-index:2147483647;pointer-events:none';
      document.documentElement.appendChild(box);
    }
    box.textContent = lines.slice(-14).reverse().join('\n');
  }

  function log(text) {
    lines.push(ms() + ' ' + text);
    show();
  }

  function describe(el) {
    if (!el || !el.tagName) return String(el);
    var ta = '';
    try { ta = getComputedStyle(el).touchAction; } catch (_) {}
    return el.tagName.toLowerCase() + '[ta=' + ta + ']';
  }

  function path(el) {
    var parts = [];
    for (var n = el; n && n.tagName && parts.length < 6; n = n.parentElement) parts.push(describe(n));
    return parts.join('<');
  }

  window.addEventListener('pointerdown', function (e) {
    active[e.pointerId] = { type: e.pointerType, x: e.clientX, y: e.clientY, moves: 0, far: 0, at: ms(),
      zero: 0, coal: 0, coalZero: 0, fix0: window.__penFixPatched };
    flt = {};
    var others = Object.keys(active).length - 1;
    log('DOWN ' + e.pointerType + '#' + e.pointerId + ' btn=' + e.buttons + ' p=' + e.pressure.toFixed(2) +
      ' others=' + others + ' on ' + path(e.target));
  }, true);

  window.addEventListener('pointermove', function (e) {
    var a = active[e.pointerId];
    if (!a) return;
    a.moves++;
    if (e.buttons === 0) a.zero++;
    if (typeof e.getCoalescedEvents === 'function') {
      e.getCoalescedEvents().forEach(function (c) { a.coal++; if (c.buttons === 0) a.coalZero++; });
    }
    var d = Math.hypot(e.clientX - a.x, e.clientY - a.y);
    if (d > a.far) a.far = d;
    if (e.buttons !== a.buttons && a.buttons !== undefined) log('  buttons ' + a.buttons + '->' + e.buttons + ' #' + e.pointerId);
    a.buttons = e.buttons;
  }, true);

  function end(kind) {
    return function (e) {
      var a = active[e.pointerId];
      if (!a) return;
      delete active[e.pointerId];
      var fix = window.__penFixPatched === undefined ? 'NOT LOADED' : (window.__penFixPatched - a.fix0);
      log((kind === 'pointercancel' ? '**CANCEL** ' : 'UP ') + a.type + '#' + e.pointerId + ' moves=' + a.moves +
        ' far=' + Math.round(a.far) + 'px ' + (ms() - a.at) + 'ms zero=' + a.zero + ' coal=' + a.coal +
        ' coalZero=' + a.coalZero + ' fixed=' + fix);
      // What Flutter got, once it has handled this event too.
      setTimeout(function () {
        var parts = [];
        for (var k in flt) parts.push(k + '\u00d7' + flt[k]);
        log('  flutter: ' + (parts.join(' ') || 'nothing'));
      }, 50);
    };
  }
  window.addEventListener('pointerup', end('pointerup'), true);
  window.addEventListener('pointercancel', end('pointercancel'), true);

  ['touchcancel', 'lostpointercapture', 'contextmenu', 'selectstart', 'dragstart', 'blur', 'visibilitychange',
    'focusin', 'beforeinput', 'compositionstart'].forEach(function (type) {
    window.addEventListener(type, function (e) {
      if (type === 'lostpointercapture' && !active[e.pointerId]) return;
      log('  ' + type + ' on ' + describe(e.target));
    }, true);
  });

  log('pentest on: ' + navigator.userAgent.replace(/^Mozilla\/5\.0 /, '') + ' dpr=' + devicePixelRatio);
  setTimeout(function () {
    var sem = document.querySelector('flt-semantics-host');
    var inputs = document.querySelectorAll('input,textarea,[contenteditable]').length;
    log('semantics=' + (sem ? sem.childElementCount : 'none') + ' editables=' + inputs +
      ' body.ta=' + getComputedStyle(document.body).touchAction);
  }, 4000);
})();
