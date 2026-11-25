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
  }, { threshold: 0.5 });
  io.observe(fig);
})();
