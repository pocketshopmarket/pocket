(function () {
  var top = document.getElementById('top');
  var onScroll = function () { top.classList.toggle('scrolled', window.scrollY > 8); };
  window.addEventListener('scroll', onScroll, { passive: true }); onScroll();

  var btn = document.querySelector('.menu-btn'), mnav = document.getElementById('mnav');
  btn.addEventListener('click', function () {
    var open = mnav.hidden; mnav.hidden = !open; btn.setAttribute('aria-expanded', String(open));
  });
  mnav.addEventListener('click', function (e) { if (e.target.closest('a')) { mnav.hidden = true; btn.setAttribute('aria-expanded', 'false'); } });

  var tabs = Array.prototype.slice.call(document.querySelectorAll('.tab'));
  function select(tab) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute('aria-selected', String(on));
      t.tabIndex = on ? 0 : -1;
      document.getElementById(t.getAttribute('aria-controls')).hidden = !on;
    });
  }
  tabs.forEach(function (t, i) {
    t.addEventListener('click', function () { select(t); });
    t.addEventListener('keydown', function (e) {
      var d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (!d) return;
      var next = tabs[(i + d + tabs.length) % tabs.length]; select(next); next.focus();
    });
  });
  document.querySelectorAll('[data-role="deliver"]').forEach(function (a) {
    a.addEventListener('click', function () { select(document.getElementById('t-deliver')); });
  });
})();
