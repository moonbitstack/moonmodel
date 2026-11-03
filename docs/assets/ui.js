// A small page errand: a night edition toggle in the page rail, and a
// back-to-top button in the lower-right. Both are optional and cost the page
// nothing when their host element is absent.
(function () {
  // --- the night edition, remembered across the document pages ------------
  var rail = document.querySelector('.pagerail');
  if (rail) {
    var nightBtn = document.createElement('button');
    nightBtn.type = 'button';
    nightBtn.className = 'nightbtn';
    nightBtn.setAttribute('aria-label', 'toggle the day or night edition');

    var SUN = '<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true" fill="none" ' +
      'stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><circle cx="8" cy="8" r="3"/>' +
      '<path d="M8 1.3v1.6M8 13.1v1.6M1.3 8h1.6M13.1 8h1.6M3.2 3.2l1.1 1.1M11.7 11.7l1.1 1.1' +
      'M12.8 3.2l-1.1 1.1M4.3 11.7l-1.1 1.1"/></svg>';
    var MOON = '<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true" fill="none" ' +
      'stroke="currentColor" stroke-width="1.3" stroke-linejoin="round">' +
      '<path d="M11.6 10.4A5 5 0 0 1 5.6 4.4 4.9 4.9 0 1 0 11.6 10.4z"/></svg>';

    var paint = function () {
      var night = document.documentElement.classList.contains('night');
      nightBtn.innerHTML = (night ? MOON : SUN) + '<span>' + (night ? 'NIGHT' : 'DAY') + '</span>';
      nightBtn.setAttribute('aria-pressed', night ? 'true' : 'false');
      nightBtn.title = night ? 'switch to the chart by day' : 'switch to the night edition';
    };

    nightBtn.addEventListener('click', function () {
      var night = document.documentElement.classList.toggle('night');
      try { localStorage.setItem('mm-night', night ? '1' : '0'); } catch (e) {}
      paint();
    });

    rail.appendChild(nightBtn);
    try {
      if (location.search.includes('night') || localStorage.getItem('mm-night') === '1')
        document.documentElement.classList.add('night');
    } catch (e) {}
    paint();
  }

  // --- back to top --------------------------------------------------------
  if (!document.querySelector('.sheet')) return;

  var top = document.createElement('button');
  top.type = 'button';
  top.className = 'totop';
  top.setAttribute('aria-label', 'back to top');
  top.innerHTML = '&#8593; TOP';
  document.body.appendChild(top);

  top.addEventListener('click', function () {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });

  var onScroll = function () {
    top.classList.toggle('show', window.scrollY > 520);
  };
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
})();
