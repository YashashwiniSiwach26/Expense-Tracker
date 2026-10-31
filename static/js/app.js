/* Front-end logic for every page. The page is chosen with <body data-page="...">. */
const $ = (s, el = document) => el.querySelector(s);
const money = n => '₹' + Number(n || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const thisMonth = () => new Date().toISOString().slice(0, 7);
const today = () => new Date().toISOString().slice(0, 10);

function toast(msg, type = 'success') {
  const t = document.createElement('div');
  t.className = 'toast ' + type; t.textContent = msg;
  $('#toasts').appendChild(t);
  setTimeout(() => t.remove(), 3500);
}

async function api(url, method = 'GET', body) {
  const opt = { method, headers: {}, credentials: 'same-origin' };
  if (body !== undefined) { opt.headers['Content-Type'] = 'application/json'; opt.body = JSON.stringify(body); }
  const res = await fetch(url, opt);
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 && !location.pathname.match(/login|register/)) { location.href = '/login'; throw new Error('auth'); }
  if (!res.ok) { toast(data.error || 'Something went wrong', 'error'); throw new Error(data.error); }
  return data;
}

const charts = {};
function drawChart(id, config) {
  if (charts[id]) charts[id].destroy();
  charts[id] = new Chart($('#' + id), config);
}
const PALETTE = ['#4f46e5', '#16a34a', '#f59e0b', '#ef4444', '#06b6d4', '#a855f7', '#ec4899', '#64748b'];

function alertsHtml(list) {
  return list.map(b => {
    const msg = b.status === 'exceeded' ? `exceeded its budget by ${money(-b.remaining)}`
      : b.status === 'reached' ? 'has reached its budget'
      : `is at ${b.percent}% of its budget`;
    return `<div class="alert ${b.status}">⚠️ <b>${esc(b.category)}</b> ${msg} (${money(b.spent)} of ${money(b.amount_limit)})</div>`;
  }).join('');
}

/* ------------------------------------------------------------ auth pages */
function initAuth(isRegister) {
  $('#authForm').addEventListener('submit', async e => {
    e.preventDefault();
    const body = Object.fromEntries(new FormData(e.target));
    try {
      const r = await api(isRegister ? '/api/register' : '/api/login', 'POST', body);
      toast(r.message);
      setTimeout(() => location.href = isRegister ? '/login' : r.redirect, 700);
    } catch (_) { }
  });
}

/* ------------------------------------------------------------ dashboard */
function initDashboard() {
  const mp = $('#monthPicker'); mp.value = thisMonth();
  async function load() {
    const d = await api('/api/summary?month=' + mp.value);
    $('#cIncome').textContent = money(d.total_income);
    $('#cExpense').textContent = money(d.total_expense);
    const bal = $('#cBalance'); bal.textContent = money(d.balance); bal.className = d.balance < 0 ? 'red' : 'green';
    $('#cMonth').textContent = money(d.month_expense);
    $('#alerts').innerHTML = alertsHtml(d.alerts);
    drawChart('catChart', {
      type: 'doughnut',
      data: { labels: d.by_category.map(r => r.category), datasets: [{ data: d.by_category.map(r => r.total), backgroundColor: PALETTE }] },
      options: { maintainAspectRatio: false, plugins: { legend: { position: 'bottom' } } }
    });
    drawChart('trendChart', {
      type: 'bar',
      data: { labels: d.trend.map(r => r.ym), datasets: [
        { label: 'Income', data: d.trend.map(r => r.total_income), backgroundColor: '#16a34a' },
        { label: 'Expenses', data: d.trend.map(r => r.total_expense), backgroundColor: '#ef4444' }] },
      options: { maintainAspectRatio: false, scales: { y: { beginAtZero: true } } }
    });
    $('#recentBody').innerHTML = d.recent.length ? d.recent.map(r => `<tr><td>${r.txn_date}</td>
      <td><span class="badge ${r.type}">${r.type}</span></td><td>${esc(r.category)}</td><td>${esc(r.description)}</td>
      <td class="num">${money(r.amount)}</td></tr>`).join('') : '<tr><td class="empty" colspan="5">No transactions yet</td></tr>';
  }
  mp.addEventListener('change', load); load();
}

/* ------------------------------------------------------------ income / expenses */
function initTransactions() {
  const kind = document.body.dataset.kind;           // 'income' or 'expense'
  const dlg = $('#txnDialog'), form = $('#txnForm'), filter = $('#filterForm');
  let cats = [];

  async function loadCats() {
    cats = await api('/api/categories?type=' + kind);
    const opts = cats.map(c => `<option value="${c.category_id}">${esc(c.name)}</option>`).join('');
    $('#formCat').innerHTML = opts;
    $('#filterCat').innerHTML = '<option value="">All</option>' + opts;
  }
  async function load() {
    const q = new URLSearchParams({ type: kind });
    new FormData(filter).forEach((v, k) => { if (v) q.set(k, v); });
    const rows = await api('/api/transactions?' + q);
    const total = rows.reduce((s, r) => s + r.amount, 0);
    $('#totalLabel').textContent = `${rows.length} record(s) · Total ${money(total)}`;
    $('#txnBody').innerHTML = rows.length ? rows.map(r => `<tr>
      <td>${r.txn_date}</td><td>${esc(r.category)}</td><td>${esc(r.description)}</td>
      <td class="num">${money(r.amount)}</td>
      <td><button class="btn sm" data-edit='${r.transaction_id}'>Edit</button>
          <button class="btn sm danger" data-del='${r.transaction_id}'>Delete</button></td></tr>`).join('')
      : '<tr><td class="empty" colspan="5">No records found</td></tr>';
    $('#txnBody').dataset.rows = JSON.stringify(rows);
  }
  function openForm(row) {
    form.reset();
    form.id.value = row ? row.transaction_id : '';
    $('#dialogTitle').textContent = (row ? 'Edit ' : 'Add ') + kind;
    form.txn_date.value = row ? row.txn_date : today();
    if (row) {
      form.category_id.value = row.category_id; form.amount.value = row.amount;
      form.description.value = row.description || '';
    }
    dlg.showModal();
  }
  $('#addBtn').onclick = () => openForm(null);
  $('#cancelBtn').onclick = () => dlg.close();
  filter.addEventListener('submit', e => { e.preventDefault(); load(); });
  $('#clearFilter').onclick = () => { filter.reset(); load(); };

  form.addEventListener('submit', async e => {
    e.preventDefault();
    const f = Object.fromEntries(new FormData(form));
    const body = { type: kind, category_id: f.category_id, amount: f.amount, txn_date: f.txn_date, description: f.description };
    try {
      const r = f.id ? await api('/api/transactions/' + f.id, 'PUT', body) : await api('/api/transactions', 'POST', body);
      toast(r.message); dlg.close(); load();
    } catch (_) { }
  });
  $('#txnBody').addEventListener('click', async e => {
    const rows = JSON.parse($('#txnBody').dataset.rows || '[]');
    if (e.target.dataset.edit) openForm(rows.find(r => r.transaction_id == e.target.dataset.edit));
    if (e.target.dataset.del && confirm('Delete this record?')) {
      try { toast((await api('/api/transactions/' + e.target.dataset.del, 'DELETE')).message); load(); } catch (_) { }
    }
  });
  loadCats().then(load);
}

/* ------------------------------------------------------------ budgets */
function initBudgets() {
  const mp = $('#monthPicker'); mp.value = thisMonth();
  async function load() {
    const rows = await api('/api/budgets?month=' + mp.value);
    $('#alerts').innerHTML = alertsHtml(rows.filter(b => b.status !== 'ok'));
    $('#budgetBody').innerHTML = rows.length ? rows.map(b => `<tr>
      <td>${esc(b.category)}</td><td class="num">${money(b.amount_limit)}</td>
      <td class="num">${money(b.spent)}</td>
      <td class="num ${b.remaining < 0 ? 'red' : ''}">${money(b.remaining)}</td>
      <td><div class="progress"><i class="${b.status}" style="width:${Math.min(b.percent, 100)}%"></i></div>
          <small class="muted">${b.percent}%</small></td>
      <td><button class="btn sm" data-edit="${b.budget_id}" data-limit="${b.amount_limit}">Edit</button>
          <button class="btn sm danger" data-del="${b.budget_id}">Delete</button></td></tr>`).join('')
      : '<tr><td class="empty" colspan="6">No budgets set for this month</td></tr>';
  }
  api('/api/categories?type=expense').then(c => {
    $('#budgetCat').innerHTML = c.map(x => `<option value="${x.category_id}">${esc(x.name)}</option>`).join('');
  });
  mp.addEventListener('change', load);
  $('#budgetForm').addEventListener('submit', async e => {
    e.preventDefault();
    const f = Object.fromEntries(new FormData(e.target));
    try {
      toast((await api('/api/budgets', 'POST', { category_id: f.category_id, amount_limit: f.amount_limit, month: mp.value })).message);
      e.target.amount_limit.value = ''; load();
    } catch (_) { }
  });
  $('#copyBtn').onclick = async () => {
    try { toast((await api('/api/budgets/copy', 'POST', { month: mp.value })).message); load(); } catch (_) { }
  };
  $('#budgetBody').addEventListener('click', async e => {
    const d = e.target.dataset;
    try {
      if (d.edit) {
        const v = prompt('New monthly limit (₹):', d.limit);
        if (v !== null) { toast((await api('/api/budgets/' + d.edit, 'PUT', { amount_limit: v })).message); load(); }
      }
      if (d.del && confirm('Delete this budget?')) { toast((await api('/api/budgets/' + d.del, 'DELETE')).message); load(); }
    } catch (_) { }
  });
  load();
}

/* ------------------------------------------------------------ reports */
function initReports() {
  const period = $('#period'), val = $('#periodValue'), wrap = $('#valueWrap');
  function setInput() {
    const p = period.value;
    wrap.style.display = p === 'yearly' ? 'none' : '';
    if (p === 'daily') { val.type = 'month'; val.value = thisMonth(); }
    if (p === 'monthly') { val.type = 'number'; val.min = 2000; val.max = 2100; val.value = new Date().getFullYear(); wrap.firstChild.textContent = 'Year'; }
    if (p === 'daily') wrap.firstChild.textContent = 'Month';
  }
  async function load() {
    const d = await api(`/api/reports?period=${period.value}&value=${encodeURIComponent(val.value)}`);
    const inc = d.rows.reduce((s, r) => s + r.income, 0), exp = d.rows.reduce((s, r) => s + r.expense, 0);
    $('#repIncome').textContent = money(inc); $('#repExpense').textContent = money(exp);
    $('#highCat').textContent = d.highest_category ? `${d.highest_category.category} (${money(d.highest_category.total)})` : 'No data';
    drawChart('repChart', {
      type: period.value === 'daily' ? 'line' : 'bar',
      data: { labels: d.rows.map(r => r.label), datasets: [
        { label: 'Income', data: d.rows.map(r => r.income), backgroundColor: '#16a34a', borderColor: '#16a34a' },
        { label: 'Expenses', data: d.rows.map(r => r.expense), backgroundColor: '#ef4444', borderColor: '#ef4444' }] },
      options: { maintainAspectRatio: false, scales: { y: { beginAtZero: true } } }
    });
    const none = n => `<tr><td class="empty" colspan="${n}">No data</td></tr>`;
    $('#repBody').innerHTML = d.rows.length ? d.rows.map(r => `<tr><td>${esc(r.label)}</td><td class="num">${money(r.income)}</td>
      <td class="num">${money(r.expense)}</td><td class="num ${r.income - r.expense < 0 ? 'red' : 'green'}">${money(r.income - r.expense)}</td>
      <td class="num">${r.txn_count}</td></tr>`).join('') : none(5);
    $('#topBody').innerHTML = d.top_categories.length ? d.top_categories.map(r => `<tr><td>${esc(r.category)}</td>
      <td class="num">${money(r.total)}</td><td class="num">${r.txn_count}</td></tr>`).join('') : none(3);
    $('#bigBody').innerHTML = d.above_average.length ? d.above_average.map(r => `<tr><td>${r.txn_date}</td><td>${esc(r.category)}</td>
      <td>${esc(r.description)}</td><td class="num">${money(r.amount)}</td></tr>`).join('') : none(4);
    $('#auditBody').innerHTML = d.audit.length ? d.audit.map(r => `<tr><td>${r.action}</td><td>${r.transaction_id}</td>
      <td class="num">${r.old_amount == null ? '–' : money(r.old_amount)}</td><td class="num">${r.new_amount == null ? '–' : money(r.new_amount)}</td>
      <td>${esc(String(r.logged_at).replace('T', ' '))}</td></tr>`).join('') : none(5);
  }
  period.addEventListener('change', () => { setInput(); load(); });
  $('#reportForm').addEventListener('submit', e => { e.preventDefault(); load(); });
  setInput(); load();
}

/* ------------------------------------------------------------ start */
document.addEventListener('DOMContentLoaded', () => {
  const mb = $('#menuBtn'); if (mb) mb.onclick = () => $('#sidebar').classList.toggle('open');
  const page = document.body.dataset.page;
  ({ login: () => initAuth(false), register: () => initAuth(true), dashboard: initDashboard,
     income: initTransactions, expenses: initTransactions, budgets: initBudgets, reports: initReports }[page] || (() => { }))();
});
