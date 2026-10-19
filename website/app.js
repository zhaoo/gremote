'use strict';
const toggle = document.querySelector('.menu-toggle');
const nav = document.querySelector('#navigation');
function closeMenu() {
  toggle.setAttribute('aria-expanded', 'false');
  nav.classList.remove('is-open');
}
toggle.addEventListener('click', () => {
  const opened = toggle.getAttribute('aria-expanded') !== 'true';
  toggle.setAttribute('aria-expanded', String(opened));
  nav.classList.toggle('is-open', opened);
});
nav.addEventListener('click', event => { if (event.target.closest('a')) closeMenu(); });
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && toggle.getAttribute('aria-expanded') === 'true') {
    closeMenu(); toggle.focus();
  }
});
function node(tag, className, text) {
  const result = document.createElement(tag);
  if (className) result.className = className;
  if (text) result.textContent = text;
  return result;
}
fetch('releases.json').then(response => {
  if (!response.ok) throw new Error('Release data unavailable');
  return response.json();
}).then(releases => {
  if (!Array.isArray(releases) || !releases.length) return;
  const fragment = document.createDocumentFragment();
  for (const release of releases) {
    const url = new URL(release.url);
    if (url.origin !== 'https://github.com' || !url.pathname.startsWith('/zhaoo/gremote/releases/')) throw new Error('Invalid release URL');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(release.date) || !Array.isArray(release.changes)) throw new Error('Invalid release data');
    const article = node('article', 'release');
    const meta = node('div', 'release-meta');
    const date = node('time', '', release.date.replaceAll('-', '.')); date.dateTime = release.date;
    meta.append(node('span', 'release-dot'), node('h3', '', `v${release.version}`), date, node('span', 'badge', release.platform));
    const body = node('div', 'release-body');
    const list = node('ul');
    for (const change of release.changes) list.append(node('li', '', change));
    const link = node('a', 'text-link', '发布说明与校验文件 ↗'); link.href = url.href;
    body.append(node('h3', '', release.title), list, node('p', 'release-evidence', release.evidence), link);
    article.append(meta, body); fragment.append(article);
  }
  document.querySelector('#release-list').replaceChildren(fragment);
}).catch(() => { /* Keep the usable static release record on network or data failure. */ });
