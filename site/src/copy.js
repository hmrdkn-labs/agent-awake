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
