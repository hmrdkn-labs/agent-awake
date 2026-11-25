// Agent Awake page script: header surface, the bag-trip chart, and the Copy control. The page reads fully without it.
(function () {
  document.documentElement.classList.add('js');
  var top = document.getElementById('top'), sentinel = document.getElementById('sentinel');
  if (top && sentinel && 'IntersectionObserver' in window) {
    new IntersectionObserver(function (e) { top.classList.toggle('solid', !e[0].isIntersecting); }).observe(sentinel);
  }
})();

// The bag-trip strip: the rule list lights its mark, and the dashed chord draws once.
(function () {
  var strip = document.getElementById('strip');
  if (!strip) return;

  var radios = strip.querySelectorAll('input[name="rule"]');
  var labels = strip.querySelectorAll('.rules label');
  var pinned = null;
  var hint = document.getElementById('rules-hint');
  if (hint) hint.hidden = false;

  function show(rule) {
    if (rule) strip.setAttribute('data-active', rule);
    else strip.removeAttribute('data-active');
  }

  Array.prototype.forEach.call(radios, function (r) {
    r.addEventListener('change', function () { pinned = r.checked && r.value ? r.value : null; show(pinned); });
  });
  Array.prototype.forEach.call(labels, function (l) {
    var rule = l.querySelector('input').value;
    l.addEventListener('mouseenter', function () { show(rule || null); });
    l.addEventListener('mouseleave', function () { show(pinned); });
  });

  // Signature motion: once, and only when motion is welcome.
  var ok = window.matchMedia && window.matchMedia('(prefers-reduced-motion: no-preference)').matches;
  if (!ok || !('IntersectionObserver' in window)) return;
  var fig = strip.querySelector('.strip-fig');
  strip.classList.add('anim');
  var io = new IntersectionObserver(function (entries) {
    if (!entries.some(function (e) { return e.isIntersecting; })) return;
    io.disconnect();
    strip.classList.add('play');
    // Once the last label has landed, drop both classes: the strip goes back to its plain final markup,
    // so a later restyle (a resize, a full-page capture) cannot restart the forwards-filled animations.
    var done = false;
    function finish() {
      if (done) return;
      done = true;
      strip.classList.remove('anim', 'play');
    }
    strip.addEventListener('animationend', function (e) {
      if (e.target.classList && e.target.classList.contains('final')) finish();
    });
    setTimeout(finish, 3000);
  }, { threshold: 0.5 });
  io.observe(fig);
})();

// Copy button for the Homebrew command. The command stays selectable without this script.
(function () {
  var btn = document.getElementById('copy-btn');
  var note = document.getElementById('copy-note');
  if (!btn || !note) return;
  var src = document.getElementById(btn.getAttribute('data-target'));
  if (!src) return;
  btn.hidden = false;
  var timer;

  function done(ok) {
    clearTimeout(timer);
    btn.textContent = ok ? 'Copied' : 'Select it';
    btn.setAttribute('data-state', ok ? 'copied' : 'failed');
    note.textContent = ok ? 'Command copied.' : 'Copying failed. Select the command and copy it.';
    timer = setTimeout(function () {
      btn.textContent = 'Copy';
      btn.removeAttribute('data-state');
      note.textContent = '';
    }, 2400);
  }

  function select() {
    var range = document.createRange();
    range.selectNodeContents(src);
    var sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
  }

  btn.addEventListener('click', function () {
    var text = src.textContent.trim();
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { done(true); }, function () { select(); done(false); });
    } else {
      select();
      done(false);
    }
  });
})();
