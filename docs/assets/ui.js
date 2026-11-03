// A small page errand: on the document pages (the ones with a `.sheet`), put a
// back-to-top button in the lower-right and let it appear once the reader has
// scrolled past the header. No framework; the class does the styling.
(function () {
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
