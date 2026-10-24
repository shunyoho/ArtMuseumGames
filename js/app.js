// 共用：Supabase client、登入檢查、icon、提示訊息
const db = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

const ICONS = {
  palette: '<path d="M12 3a9 9 0 1 0 0 18c1.1 0 1.7-.8 1.7-1.7 0-.5-.2-.9-.5-1.2-.3-.3-.5-.7-.5-1.2 0-.9.8-1.7 1.7-1.7H16a5 5 0 0 0 5-5c0-4-4-7.2-9-7.2z"/><circle cx="7.5" cy="11" r="1.2"/><circle cx="10" cy="7" r="1.2"/><circle cx="15" cy="7.5" r="1.2"/>',
  sculpture: '<path d="M7 21h10M9 21v-4h6v4M12 17v-3"/><path d="M12 14c-3 0-5-2.5-4-5.5S11 3 12 3s5 2.5 4 5.5-1 5.5-4 5.5z"/>',
  camera: '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
  leaf: '<path d="M5 19C5 11 10 5 20 5c0 10-6 15-14 15"/><path d="M5 19l8-8"/>',
  frame: '<rect x="3" y="4" width="18" height="16" rx="1"/><rect x="6.5" y="7.5" width="11" height="9"/><path d="M6.5 16.5l3.5-4 2.5 2.5 2-2 3 3.5"/>',
};

function icon(name) {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ICONS.frame}</svg>`;
}

// 只允許站內相對路徑，避免 ?next= 被拿來導到別的網站
function safeNext(next, fallback) {
  if (!next || next.includes('//') || next.includes(':') || next.startsWith('/')) return fallback;
  return next;
}

// 沒登入就導回登入頁，並記住原本要去的頁面（包含 ?code=）
async function requireLogin() {
  const { data: { session } } = await db.auth.getSession();
  if (!session) {
    const here = location.pathname.split('/').pop() + location.search;
    location.replace('index.html?next=' + encodeURIComponent(here));
    return null;
  }
  return session.user;
}

// 登出：scope 'local' 只清除這台裝置的登入狀態，不需要連線，所以不會因為網路或伺服器錯誤而登出失敗
async function logout() {
  try {
    await db.auth.signOut({ scope: 'local' });
  } finally {
    location.replace('index.html');
  }
}

function toast(msg, type = 'info') {
  let el = document.getElementById('toast');
  if (!el) {
    el = document.createElement('div');
    el.id = 'toast';
    document.body.appendChild(el);
  }
  el.textContent = msg;
  el.className = 'toast show ' + type;
  clearTimeout(el._t);
  el._t = setTimeout(() => (el.className = 'toast'), 3200);
}

function escapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
