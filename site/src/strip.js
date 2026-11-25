// The bag-trip strip: the rule list lights its mark, and the dashed chord draws once.
(function () {
  var strip = document.getElementById('strip');
  if (!strip) return;

  var buttons = strip.querySelectorAll('[data-rule]');
  var pinned = null;

  function show(rule) {
    if (rule) strip.setAttribute('data-active', rule);
    else strip.removeAttribute('data-active');
  }

  Array.prototype.forEach.call(buttons, function (btn) {
    var rule = btn.getAttribute('data-rule');
    btn.addEventListener('mouseenter', function () { show(rule); });
    btn.addEventListener('mouseleave', function () { show(pinned); });
    btn.addEventListener('focus', function () { show(rule); });
    btn.addEventListener('blur', function () { show(pinned); });
    btn.addEventListener('click', function () {
      pinned = pinned === rule ? null : rule;
      Array.prototype.forEach.call(buttons, function (b) {
        b.setAttribute('aria-pressed', String(b.getAttribute('data-rule') === pinned));
      });
      show(pinned || rule);
    });
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
