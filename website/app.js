'use strict';

const toggle = document.querySelector('.menu-toggle');
const nav = document.querySelector('#primary-navigation');
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
document.addEventListener('click', event => { if (!event.target.closest('.site-header')) closeMenu(); });
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && toggle.getAttribute('aria-expanded') === 'true') {
    closeMenu(); toggle.focus();
  }
});
window.matchMedia('(min-width: 761px)').addEventListener('change', closeMenu);

// Switch explanatory panels; these are illustrations, not an in-browser editor.
const tabs = [...document.querySelectorAll('[data-tab]')];
function selectTab(tab) {
  for (const button of tabs) {
    const active = button === tab;
    button.classList.toggle('active', active);
    button.setAttribute('aria-selected', String(active));
    button.tabIndex = active ? 0 : -1;
    document.getElementById(button.dataset.tab).hidden = !active;
  }
}
for (const tab of tabs) {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', event => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    const index = tabs.indexOf(tab);
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1
      : (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
    selectTab(tabs[next]); tabs[next].focus();
  });
}

function node(tag, className, text) {
  const result = document.createElement(tag);
  if (className) result.className = className;
  if (text) result.textContent = text;
  return result;
}
function releaseURL(value) {
  const url = new URL(value);
  if (url.origin !== 'https://github.com' || url.username || url.password
      || !url.pathname.startsWith('/zhaoo/gremote/releases/')) throw new Error('Invalid release URL');
  return url.href;
}
fetch('releases.json').then(response => {
  if (!response.ok) throw new Error('Release data unavailable');
  return response.json();
}).then(releases => {
  if (!Array.isArray(releases) || !releases.length) return;
  const fragment = document.createDocumentFragment();
  let latestDownload;
  let latestChecksums;
  for (const [index, release] of releases.entries()) {
    const url = releaseURL(release.url);
    if (!/^\d+\.\d+\.\d+$/.test(release.version) || !/^\d{4}-\d{2}-\d{2}$/.test(release.date)
        || !Array.isArray(release.changes) || !release.changes.every(change => typeof change === 'string')) {
      throw new Error('Invalid release data');
    }
    if (index === 0 && release.download) {
      latestDownload = releaseURL(release.download);
      latestChecksums = releaseURL(release.checksums);
      const prefix = `https://github.com/zhaoo/gremote/releases/download/v${release.version}/`;
      if (!latestDownload.startsWith(prefix) || !latestDownload.endsWith('.apk')
          || latestChecksums !== `${prefix}SHA256SUMS.txt`
          || !/^[a-f0-9]{64}$/.test(release.sha256) || !Number.isSafeInteger(release.bytes) || release.bytes <= 0) {
        throw new Error('Invalid release asset');
      }
    }
    const article = node('article', 'release');
    const meta = node('div', 'release-meta');
    const date = node('time', '', release.date.replaceAll('-', '.')); date.dateTime = release.date;
    meta.append(node('span', 'release-dot'), node('h3', '', `v${release.version}`), date, node('span', 'badge', release.platform));
    const body = node('div', 'release-body');
    const list = node('ul');
    for (const change of release.changes) list.append(node('li', '', change));
    const link = node('a', 'text-link', '发布说明与校验文件 ↗'); link.href = url;
    body.append(node('h3', '', release.title), list, node('p', 'release-evidence', release.evidence), link);
    article.append(meta, body); fragment.append(article);
  }
  document.querySelector('#release-list').replaceChildren(fragment);
  if (latestDownload) {
    document.querySelectorAll('[data-download]').forEach(link => { link.href = latestDownload; });
    document.querySelectorAll('[data-checksums]').forEach(link => { link.href = latestChecksums; });
    document.querySelectorAll('[data-release-version]').forEach(label => { label.textContent = `v${releases[0].version}`; });
  }
}).catch(() => { /* Keep the usable static release record and download on network or data failure. */ });
